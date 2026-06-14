import Flutter
import Combine
import UIKit
import MediaPlayer
import AVFoundation
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin"

internal var currentPublicationUrlStr: String?
internal var currentPublication: Publication?
internal weak var currentReaderView: ReadiumReaderView?
internal weak var currentPdfReaderView: PdfReaderView?
internal weak var currentImageReaderView: ImageReaderView?

func getCurrentPublication() -> Publication? {
  return currentPublication
}

public class FlureadiumPlugin: NSObject, FlutterPlugin, ReadiumShared.WarningLogger, TimebasedListener {

  static var registrar: FlutterPluginRegistrar? = nil

  /// TTS Decoration style
  internal var ttsUtteranceDecorationStyle: Decoration.Style? = .highlight(tint: .yellow)
  internal var ttsRangeDecorationStyle: Decoration.Style? = .underline(tint: .black)

  /// Timebased player events & state
  internal var timebasedPlayerStateStreamHandler: EventStreamHandler?
  internal var lastTimebasedPlayerState: ReadiumTimebasedState? = nil

  /// Timebased Navigator. Can be TTS, Audio or MediaOverlay implementations.
  internal var timebasedNavigator: FlutterTimebasedNavigator? = nil

  lazy var fallbackChapterTitle: LocalizedString = LocalizedString.localized([
    "en": "Chapter",
    "da": "Kapitel",
    "sv": "Kapitel",
    "no": "Kapittel",
    "is": "Kafli",
  ])

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dev.mulev.flureadium/main", binaryMessenger: registrar.messenger())
    let instance = FlureadiumPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.timebasedPlayerStateStreamHandler = EventStreamHandler(withName: "timebased-state", messenger: registrar.messenger())

    // Register reader view factory
    let factory = ReadiumReaderViewFactory(registrar: registrar)
    registrar.register(factory, withId: readiumReaderViewType)

    self.registrar = registrar
  }

  public func log(_ warning: Warning) {
    print(TAG, "Error in Readium: \(warning)")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setCustomHeaders":
      guard let args = call.arguments as? [String: Any],
            let httpHeaders = args["httpHeaders"] as? [String: String] else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "Invalid custom headers map",
          details: nil))
      }
      sharedReadium.setAdditionalHeaders(httpHeaders)
      result(nil)
    case "dispose":
      Task.detached(priority: .high) {
        await self.closePublication()
        await MainActor.run {
          self.timebasedPlayerStateStreamHandler?.dispose()
          self.timebasedPlayerStateStreamHandler = nil
          result(nil)
        }
      }
    case "closePublication":
      Task.detached(priority: .high) {
        await self.closePublication()
        await MainActor.run { result(nil) }
      }
    case "openPublication":
      let args = call.arguments as! [Any?]
      let pubUrlStr = args[0] as! String

      Task.detached(priority: .high) {
        do {
          // Fast path: if the same publication is already open, return its manifest.
          if let existingPub = currentPublication,
             currentPublicationUrlStr == pubUrlStr {
            let jsonManifest = existingPub.jsonManifest
            await MainActor.run { result(jsonManifest) }
            return
          }

          if (currentPublication != nil) {
            await self.closePublication()
          }
          let pub: Publication = try await self.loadPublication(fromUrlStr: pubUrlStr).get()
          currentPublication = pub
          currentPublicationUrlStr = pubUrlStr

          let jsonManifest = pub.jsonManifest
          await MainActor.run {
            result(jsonManifest)
          }
        } catch let err as ReadiumError {
          await MainActor.run {
            result(err.toFlutterError())
          }
        }
      }
    case "loadPublication":
      let args = call.arguments as! [Any?]
      let pubUrlStr = args[0] as! String

      Task.detached(priority: .high) {
        do {
          let pub: Publication = try await self.loadPublication(fromUrlStr: pubUrlStr).get()

          let jsonManifest = pub.jsonManifest
          pub.close()

          await MainActor.run {
            result(jsonManifest)
          }
        } catch let err as ReadiumError {
          await MainActor.run {
            result(err.toFlutterError())
          }
        }
      }
    case "getLinkContent":
      let args = call.arguments as! [Any?]
      // TODO: Do we need asString?
      //let asString = args[1] as? Bool ?? true
      let asString = true
      guard let linkStr = args[0] as? String,
            let publication = currentPublication,
            let link = try? Link(fromJsonString: linkStr) else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "Failed to get link content",
          details: nil))
      }
      Task.detached(priority: .background) {
        let resource = publication.get(link)
        do {
          if (asString) {
            let linkContent = try await resource?.readAsString(encoding: .utf8).get()
            await MainActor.run {
              result(linkContent)
            }
          } else {
            let data = try await resource!.read().get()
            await MainActor.run {
              result(FlutterStandardTypedData(bytes: data))
            }
          }
        } catch let err {
          await MainActor.run {
            print("\(TAG).getLinkContent exception: \(err)")
            result(
              FlutterError.init(
                code: "InternalError",
                message: err.localizedDescription,
                details: "Something went wrong fetching link content."))
          }
        }
      }
    case "extractPageThumbnail":
      guard let args = call.arguments as? [Any?],
            args.count >= 3,
            let href = args[0] as? String,
            let maxHeight = args[1] as? Int,
            let quality = args[2] as? Int else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "extractPageThumbnail requires [href: String, maxHeight: Int, quality: Int]",
          details: nil))
      }
      guard let publication = currentPublication,
            let url = AnyURL(legacyHREF: href) else {
        return result(nil)
      }
      Task.detached(priority: .userInitiated) {
        let resource = publication.get(url)
        guard let data = try? await resource?.read().get() else {
          await MainActor.run { result(nil) }
          return
        }
        let jpeg = PageThumbnailExtractor.extract(
          data: data, maxHeight: maxHeight, quality: quality
        )
        await MainActor.run {
          if let jpeg = jpeg {
            result(FlutterStandardTypedData(bytes: jpeg))
          } else {
            result(nil)
          }
        }
      }

    case "ttsEnable":
      guard let args = call.arguments as? [Any?] else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "Invalid parameters to ttsEnable: \(call.arguments.debugDescription)",
          details: nil))
      }
      Task.detached(priority: .high) {
        do {
          let prefsMap = args[0] as? Dictionary<String, Any>,
              ttsPrefs = (try? TTSPreferences(fromMap: prefsMap ?? [:])) ?? TTSPreferences()

          var locator: Locator? = nil
          if let locatorJson = args[1] as? Dictionary<String, Any> {
            locator = try? Locator(json: locatorJson, warnings: self)
          }

          guard let publication = getCurrentPublication() else {
            throw ReadiumError.notFound("No publication opened")
          }

          let navigator = await MainActor.run { () -> FlutterTTSNavigator in
            let initialLocation = locator ?? currentReaderView?.getCurrentLocation()
            let nav = FlutterTTSNavigator(publication: publication, preferences: ttsPrefs, initialLocator: initialLocation)
            nav.listener = self
            self.timebasedNavigator = nav
            return nav
          }

          try await navigator.initNavigator()

          await MainActor.run {
            result(nil)
          }
        } catch {
          await MainActor.run {
            self.timebasedNavigator = nil
            result(FlutterError.init(
              code: "TTSError",
              message: "Failed to enable TTS: \(error.localizedDescription)",
              details: nil))
          }
        }
      }
    case "ttsGetAvailableVoices":
      guard let ttsNavigator = self.timebasedNavigator as? FlutterTTSNavigator else {
        return result(FlutterError.init(
          code: "TTSError",
          message: "TTS Navigator not initialized",
          details: nil))
      }
      let availableVoices = ttsNavigator.ttsGetAvailableVoices()
      result(availableVoices.compactMap { $0.jsonString })
    case "ttsGetSystemVoices":
      let voices = AVSpeechSynthesisVoice.speechVoices()
      let voiceJsons: [String] = voices.compactMap { voice in
        let json: [String: Any] = [
          "identifier": voice.identifier,
          "name": voice.name,
          "language": voice.language,
          "networkRequired": false,
          "gender": "unspecified",
          "quality": voice.quality.rawValue >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue ? "high" : "normal"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
      }
      result(voiceJsons)
    case "ttsCanSpeak":
      guard let publication = currentPublication else {
        result(false)
        return
      }
      result(PublicationSpeechSynthesizer.canSpeak(publication: publication))
    case "ttsRequestInstallVoice":
      result(nil) // No-op on iOS — voices managed by OS
    case "ttsSetVoice":
      let args = call.arguments as! [Any?]
      let voiceIdentifier = args[0] as! String
      // TODO: language might be supplied as args[1], ignored on iOS for now.

      guard let ttsNavigator = self.timebasedNavigator as? FlutterTTSNavigator else {
        return result(FlutterError.init(
          code: "TTSError",
          message: "TTS Navigator not initialized",
          details: nil))
      }

      do {
        try ttsNavigator.ttsSetVoice(voiceIdentifier: voiceIdentifier)
        result(nil)
      } catch {
        result(FlutterError.init(
          code: "TTSError",
          message: "Invalid voice identifier: \(error.localizedDescription)",
          details: nil))
      }
    case "setDecorationStyle":
      let args = call.arguments as! [Any?]

      if let uttDecorationMap = args[0] as? Dictionary<String, String> {
        ttsUtteranceDecorationStyle = try! Decoration.Style(fromMap: uttDecorationMap)
      }

      if let rangeDecorationMap = args[1] as? Dictionary<String, String> {
        ttsRangeDecorationStyle = try! Decoration.Style(fromMap: rangeDecorationMap)
      }
      result(nil)
    case "ttsSetPreferences":
      let args = call.arguments as? Dictionary<String, Any> ?? [:]
      guard let ttsNavigator = self.timebasedNavigator as? FlutterTTSNavigator else {
        return result(FlutterError.init(
          code: "TTSError",
          message: "TTS Navigator not initialized",
          details: nil))
      }
      do {
        let ttsPrefs = try TTSPreferences(fromMap: args)
        ttsNavigator.ttsSetPreferences(prefs: ttsPrefs)
        result(nil)
      } catch {
        result(FlutterError.init(
          code: "TTSError",
          message: "Failed to deserialize TTSPreferences: \(error.localizedDescription)",
          details: nil))
      }
    case "play":
      let args = call.arguments as! [Any?]
      var locator: Locator? = nil
      if let locatorJson = args.first as? Dictionary<String, Any> {
        locator = try? Locator(json: locatorJson, warnings: self)
      }

      Task.detached(priority: .high) {
        // If no locator provided, try to start from current ReaderView position.
        if (locator == nil) {
          locator = await currentReaderView?.getFirstVisibleLocator()
        }
        await self.timebasedNavigator?.play(fromLocator: locator)

        await MainActor.run {
          result(nil)
        }
      }
    case "stop":
      Task.detached(priority: .high) {
        await MainActor.run {
          self.timebasedNavigator?.dispose()
          self.timebasedNavigator = nil
          CarPlayPlaybackBridge.shared.unregister()
          self.updateReaderViewTimebasedDecorations([])
        }
        await MainActor.run { result(nil) }
      }
    case "pause":
      Task { @MainActor in
        await self.timebasedNavigator?.pause()
      }
      result(nil)
    case "resume":
      Task { @MainActor in
        await self.timebasedNavigator?.resume()
      }
      result(nil)
    case "togglePlayback":
      Task { @MainActor in
        await self.timebasedNavigator?.togglePlayPause()
      }
      result(nil)
    case "next":
      Task { @MainActor in
        await self.timebasedNavigator?.seekForward()
      }
      result(nil)
    case "previous":
      Task { @MainActor in
        await self.timebasedNavigator?.seekBackward()
      }
      result(nil)
    case "goToLocator":
      Task.detached(priority: .high) {
        guard let args = call.arguments as? [Any?],
              let locatorJson = args.first as? Dictionary<String, Any>,
              let locator = try? Locator(json: locatorJson, warnings: self)
        else {
          await MainActor.run {
            result(FlutterError.init(
              code: "InvalidArgument",
              message: "Failed to parse locator",
              details: nil))
          }
          return
        }
        var navigated = false

        // Timebased Naviagor seek
        if (self.timebasedNavigator != nil) {
          navigated = await self.timebasedNavigator?.seek(toLocator: locator) ?? false
        }
        // ReaderView goTo (EPUB)
        else if (currentReaderView != nil) {
          await currentReaderView?.goToLocator(locator: locator, animated: false)
          navigated = true
        }
        // ImageReaderView goTo (CBZ / DiViNa)
        else if (currentImageReaderView != nil) {
          navigated = await currentImageReaderView?.goToLocator(locator: locator, animated: false) ?? false
        }
        // PdfReaderView goTo
        else if (currentPdfReaderView != nil) {
          await currentPdfReaderView?.goToLocator(locator: locator, animated: false)
          navigated = true
        }
        await MainActor.run { [navigated] in
          result(navigated)
        }
      }
    case "audioEnable":
      guard let args = call.arguments as? [Any?],
            let publication = currentPublication,
            let pubUrlStr = currentPublicationUrlStr else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "No publication open or Invalid parameters to audioEnable: \(call.arguments.debugDescription)",
          details: nil))
      }
      Task.detached(priority: .high) {
        // Get preferences via arg, or use defaults (empty map).
        let prefsMap = args[0] as? Dictionary<String, Any>,
            prefs = try FlutterAudioPreferences.init(fromMap: prefsMap ?? [:])
        var locator: Locator? = nil
        if let locatorJson = args[1] as? Dictionary<String, Any> {
          locator = try? Locator(json: locatorJson, warnings: self)
        }

        if (publication.containsMediaOverlays) {
          do {
            // MediaOverlayNavigator will modify the Publication readingOrder, so we first load a modifiable copy.
            let modifiablePublicationCopy = try await self.loadPublication(fromUrlStr: pubUrlStr).get()
            await MainActor.run { [locator] in
              self.timebasedNavigator = FlutterMediaOverlayNavigator(publication: modifiablePublicationCopy, preferences: prefs, initialLocator: locator)
            }
          } catch (let err) {
            return result(FlutterError.init(
              code: "Error",
              message: "Failed to reload a modifiable publication copy from: \(pubUrlStr)",
              details: err))
          }
        } else {
          if (!publication.conforms(to: Publication.Profile.audiobook)) {
            return result(FlutterError.init(
              code: "InvalidArgument",
              message: "Publication does not contain MediaOverlays or conforms to AudioBook profile. Args: \(call.arguments.debugDescription)",
              details: nil))
          }
          let audioNavigator = await FlutterAudioNavigator(publication: publication, preferences: prefs, initialLocator: locator)
          self.timebasedNavigator = audioNavigator
          CarPlayPlaybackBridge.shared.register(publication: publication) { [weak audioNavigator] selected in
            Task { @MainActor in
              await audioNavigator?.play(fromLocator: selected)
            }
          }
        }

        self.timebasedNavigator?.listener = self
        try await self.timebasedNavigator?.initNavigator()

        await MainActor.run {
          result(nil)
        }
      }
    case "audioSetPreferences":
      Task.detached(priority: .high) {
        guard let audioNavigator = self.timebasedNavigator as? FlutterAudioNavigator,
              let prefsMap = call.arguments as? Dictionary<String, Any>,
              let prefs = try? FlutterAudioPreferences.init(fromMap: prefsMap) else {
          return result(FlutterError.init(
            code: "InvalidArgument",
            message: "AudioNavigator not initialized or Invalid parameters to audioSetPreferences: \(call.arguments.debugDescription)",
            details: nil))
        }
        Task { @MainActor in
          audioNavigator.setAudioPreferences(prefs)
          result(nil)
        }
      }
    case "audioSeekBy":
      Task { @MainActor in
        guard let seekOffset = call.arguments as? Double else {
          return result(FlutterError.init(
            code: "InvalidArgument",
            message: "Invalid parameters to audioSeek: \(call.arguments.debugDescription)",
            details: nil))
        }
        let _ = await self.timebasedNavigator?.seekRelative(byOffsetSeconds: seekOffset)
        result(nil)
      }

    case "renderFirstPage":
      let args = call.arguments as! [Any?]
      let pubUrlStr = args[0] as! String
      let maxWidth = args[1] as! Int
      let maxHeight = args[2] as! Int

      Task.detached(priority: .background) {
        let imageData = Self.renderFirstPage(
          pubUrlStr: pubUrlStr,
          maxWidth: maxWidth,
          maxHeight: maxHeight
        )
        await MainActor.run {
          if let data = imageData {
            result(FlutterStandardTypedData(bytes: data))
          } else {
            result(nil)
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func timebasedNavigator(_: any FlutterTimebasedNavigator, didChangeState state: ReadiumTimebasedState) {
    print(TAG, "TimebasedNavigator state: \(state)")
    timebasedPlayerStateStreamHandler?.sendEvent(state.toJsonString())
  }

  public func timebasedNavigator(_: any FlutterTimebasedNavigator, encounteredError error: any Error, withDescription description: String?) {
    print(TAG, "TimebasedNavigator error: \(error), description: \(String(describing: description))")
    // TODO: submit on error stream
  }

  public func timebasedNavigator(_: any FlutterTimebasedNavigator, reachedLocator locator: ReadiumShared.Locator, readingOrderLink: ReadiumShared.Link?) {
    print(TAG, "TimebasedNavigator reachedLocator: \(locator), readingOrderLink: \(String(describing: readingOrderLink))")

    Task { @MainActor [locator] in
      await currentReaderView?.goToLocator(locator: locator, animated: false)
    }
  }

  public func timebasedNavigator(_: any FlutterTimebasedNavigator, requestsHighlightAt locator: ReadiumShared.Locator?, withWordLocator wordLocator: ReadiumShared.Locator?) {
    print(TAG, "TimebasedNavigator requestsHighlightAt: \(String(describing: locator)), withWordLocator: \(String(describing: wordLocator))")

    // Update Reader text decorations
    var decorations: [Decoration] = []
    if let uttLocator = locator,
       let uttDecorationStyle = ttsUtteranceDecorationStyle {
      decorations.append(Decoration(
        id: "tts-utt", locator: uttLocator, style: uttDecorationStyle
      ))
    }
    if let rangeLocator = wordLocator,
       let rangeDecorationStyle = ttsRangeDecorationStyle {
      decorations.append(Decoration(
        id: "tts-range", locator: rangeLocator, style: rangeDecorationStyle
      ))
    }
    Task { @MainActor [decorations] in
      updateReaderViewTimebasedDecorations(decorations)
    }
  }
}

/// Extension for handling publication interactions
extension FlureadiumPlugin {

  @MainActor
  func updateReaderViewTimebasedDecorations(_ decorations: [Decoration]) {
    currentReaderView?.applyDecorations(decorations, forGroup: "timebased-highlight")
  }

  func clearNowPlaying() {
    NowPlayingInfo.shared.clear()
  }

  private func loadPublication (
    fromUrlStr: String,
  ) async -> Result<Publication, ReadiumError> {
    var pubUrlStr = fromUrlStr
    if (!pubUrlStr.hasPrefix("http") && !pubUrlStr.hasPrefix("file")) {
      // Assume URLs without a supported prefix are local file paths.
      pubUrlStr = "file://\(pubUrlStr)"
    }

    let encodedUrlStr = "\(pubUrlStr)".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
    guard let url = URL(string: encodedUrlStr!) else {
      return .failure(ReadiumError.notFound("Invalid pub URL: \(pubUrlStr)"))
    }
    guard let absUrl = url.anyURL.absoluteURL else {
      return .failure(ReadiumError.notFound("Failed to get AbsoluteUrl: \(pubUrlStr)"))
    }

    print("Attempting to open publication at: \(absUrl)")
    do {
      let pub: (Publication, Format) = try await self.openPublication(at: absUrl, allowUserInteraction: true, sender: nil)
      let mediaType: String = pub.1.mediaType?.string ?? "unknown"
      print("Opened publication: identifier: \(pub.0.metadata.identifier ?? "[no-ident]") format: \(mediaType)")
      return .success(pub.0)
    } catch let error {
      print("Failed to open publication: \(error)")
      return .failure(error)
    }
  }

  private func openPublication(
    at url: AbsoluteURL,
    allowUserInteraction: Bool,
    sender: UIViewController?
  ) async throws(ReadiumError) -> (Publication, Format) {
    do {
      let asset = try await sharedReadium.assetRetriever!.retrieve(url: url).get()

      let publication = try await sharedReadium.publicationOpener!.open(
        asset: asset,
        allowUserInteraction: allowUserInteraction,
        sender: sender
      ).get()

      return (publication, asset.format)
    } catch let err {
      throw err.toReadiumError()
    }
  }

  private func closePublication() async {
    // Clean-up any resources associated with the publication.
    await MainActor.run {
      self.timebasedNavigator?.dispose()
      self.timebasedNavigator = nil
      CarPlayPlaybackBridge.shared.unregister()
      currentReaderView = nil
      currentPdfReaderView = nil
      currentImageReaderView = nil
      currentPublication?.close()
      currentPublication = nil
      currentPublicationUrlStr = nil
    }
  }

  /// Renders the first page of a PDF file as a JPEG image using Core Graphics.
  static func renderFirstPage(pubUrlStr: String, maxWidth: Int, maxHeight: Int) -> Data? {
    var urlStr = pubUrlStr
    if !urlStr.hasPrefix("file://") && !urlStr.hasPrefix("http") {
      urlStr = "file://\(urlStr)"
    }

    guard let url = URL(string: urlStr),
          let document = CGPDFDocument(url as CFURL),
          let page = document.page(at: 1) else {
      return nil
    }

    let pageRect = page.getBoxRect(.mediaBox)
    let scale = min(
      CGFloat(maxWidth) / pageRect.width,
      CGFloat(maxHeight) / pageRect.height,
      1.0
    )
    let width = Int(pageRect.width * scale)
    let height = Int(pageRect.height * scale)

    UIGraphicsBeginImageContextWithOptions(
      CGSize(width: width, height: height),
      true,
      1.0
    )
    guard let context = UIGraphicsGetCurrentContext() else {
      UIGraphicsEndImageContext()
      return nil
    }

    context.setFillColor(UIColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    context.drawPDFPage(page)

    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return image?.jpegData(compressionQuality: 0.85)
  }
}
