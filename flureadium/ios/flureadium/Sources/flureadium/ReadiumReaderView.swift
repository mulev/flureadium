import Foundation
import ReadiumNavigator
import ReadiumAdapterGCDWebServer
import ReadiumShared
import Flutter
import UIKit
import WebKit

private let TAG = "ReadiumReaderView"
private let ReadiumReaderStatusReady = "ready"
private let ReadiumReaderStatusLoading = "loading"
private let ReadiumReaderStatusClosed = "closed"
private let ReadiumReaderStatusError = "error"

let readiumReaderViewType = "dev.mulev.flureadium/ReadiumReaderWidget"

class ReadiumBugLogger: ReadiumShared.WarningLogger {
  func log(_ warning: Warning) {
    print(TAG, "Error in Readium: \(warning)")
  }
}

private let readiumBugLogger = ReadiumBugLogger()

func parseLocatorFragmentsResult(_ result: Any?) -> Locator? {
  guard let json = result as? Dictionary<String, Any?> else {
    return nil
  }

  return try? Locator(json: json, warnings: readiumBugLogger)
}

class ReadiumReaderView: NSObject, FlutterPlatformView, EPUBNavigatorDelegate, VisualNavigatorDelegate {

  private let channel: ReadiumReaderChannel
  // reader-status and text-locator are owned by FlureadiumPlugin: this view is
  // shorter-lived than the Dart subscription to them.
  private let _view: UIView
  private let readiumViewController: EPUBNavigatorViewController
  private var isVerticalScroll = false
  private var hasSentReady = false
  private var isDisposed = false
  private var edgeNavigation = ReaderEdgeNavigationState()
  private var tapObserverToken: InputObservableToken?
  private let userScripts: [WKUserScript]

  // Retain the navigation adapter to prevent ARC deallocation
  private var directionalNavigationAdapter: DirectionalNavigationAdapter?

  // Scroll-mode position memory: remembers the last scroll position per spine item
  // so swipe-back can restore where the user was in the previous chapter.
  private var spineItemHistory: [String: Locator] = [:]
  private var lastSpineItemLocator: Locator?
  private var currentSpineItemHref: String?

  var publicationIdentifier: String?

  /// The pointer policy handed to Readium's `DirectionalNavigationAdapter`.
  ///
  /// Empty on purpose: `EdgeTapInterceptView` is the sole pointer edge owner on
  /// iOS, carrying the host's width (`edgeTapAreaPoints`) and its gate
  /// (`enableEdgeTapNavigation`). Two owners meant the adapter's own
  /// `max(80, 0.3 × width)` band turned pages with edge tap switched off.
  /// Keeping this as a static constant makes the constructed policy testable.
  static let edgeTapPointerPolicy = DirectionalNavigationAdapter.PointerPolicy(types: [])

  func view() -> UIView {
    print(TAG, "::getView")
    return _view
  }

  deinit {
    print(TAG, "::deinit")
    readiumViewController.view.removeFromSuperview()
  }

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    registrar: FlutterPluginRegistrar
  ) {
    print(TAG, "::init")
    let creationParams = args as! Dictionary<String, Any?>

    let publication = getCurrentPublication()!

    let preferencesMap = creationParams["preferences"] as? [String: String]
    let defaultPreferences = preferencesMap.map { EPUBPreferences.init(fromMap: $0) }

    let locatorStr = creationParams["initialLocator"] as? String
    let locator = locatorStr == nil ? nil : try! Locator.init(jsonString: locatorStr!)
    print(TAG, "publication = \(publication)")

    channel = ReadiumReaderChannel(
      name: "\(readiumReaderViewType):\(viewId)", binaryMessenger: registrar.messenger())
    FlureadiumPlugin.shared?.sendReaderStatus(ReadiumReaderStatusLoading)

    print(TAG, "Publication: (identifier=\(String(describing: publication.metadata.identifier)),title=\(String(describing: publication.metadata.title)))")
    print(TAG, "Added publication at \(String(describing: publication.baseURL))")

    let config = makeEpubNavigatorConfiguration(preferences: defaultPreferences)

    readiumViewController = try! EPUBNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      config: config,
      httpServer: sharedReadium.httpServer!
    )

    userScripts = EpubUserScripts.make(registrar: registrar)

    _view = EdgeTapInterceptView()
    super.init()

    channel.setMethodCallHandler(onMethodCall)
    readiumViewController.delegate = self

    // Set initial scroll mode from preferences and configure edge tap handlers accordingly
    isVerticalScroll = defaultPreferences?.scroll ?? false
    configureEdgeTapHandlers(isScrollMode: isVerticalScroll)

    _view.addPinnedSubview(readiumViewController.view)

    currentReaderView = self
    publicationIdentifier = publication.metadata.identifier

    /// Readium's adapter is kept for keyboard paging only — arrow keys and the
    /// space bar. `bind(to:)` skips every pointer type absent from
    /// `pointerPolicy.types` and registers the key observer unconditionally, so
    /// an empty policy hands every touch to `EdgeTapInterceptView`.
    ///
    /// Bind it to the navigator before adding your own observers to prevent
    /// triggering your actions when turning pages.
    /// NOTE: Store in property to prevent ARC deallocation
    directionalNavigationAdapter = DirectionalNavigationAdapter(pointerPolicy: Self.edgeTapPointerPolicy)
    directionalNavigationAdapter?.bind(to: readiumViewController)

    tapObserverToken = observeTaps(
      on: readiumViewController, reportingTo: channel,
      isDisposed: { [weak self] in self?.isDisposed ?? true })

    print(TAG, "::init success")
  }

  @objc public func onCustomEditingAction() {
    print(TAG, "EditingAction::NOTA")
    // NOTE: This method will not actually be hit. It will try to find an "onEditingActionNota" function in the Responder chain!
    // see https://github.com/readium/swift-toolkit/issues/466

    // This methos should actually be implemented in the Flutter AppDelegate!
    // TODO: Find a way to trigger the code below, from the AppDelegate.
    if let selection = readiumViewController.currentSelection {
      let selectionLocator = selection.locator
      currentReaderView?.readiumViewController.apply(decorations: [Decoration(id: "highlight", locator: selectionLocator, style: .highlight(), userInfo: [:])], in: "user-highlight")
      readiumViewController.clearSelection()
    }
  }

  // override EPUBNavigatorDelegate::navigator:setupUserScripts
  func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
    print(TAG, "setupUserScripts: adding \(userScripts.count) scripts")
    for script in userScripts {
      userContentController.addUserScript(script)
    }
  }

  // override EPUBNavigatorDelegate::middleTapHandler
  func middleTapHandler() {
  }

  func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
    // All margin & safe-area is handled on the Flutter side.
    return .init(top: 0, left: 0, bottom: 0, right: 0)
  }

  // override EPUBNavigatorDelegate::navigator:presentError
  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    print(TAG, "presentError: \(error)")
  }

  // override EPUBNavigatorDelegate::navigator:didFailToLoadResourceAt
  func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    print(TAG, "didFailToLoadResourceAt: \(href). err: \(error)")

    // TODO: Should we send resource-load error like this?
    FlureadiumPlugin.shared?.sendReaderStatus(ReadiumReaderStatusError)

    // Route through the plugin, which owns the single "error" channel.
    FlureadiumPlugin.shared?.sendError(
      message: error.localizedDescription, code: "DidFailToLoadResource", data: href.string)
  }

  // override NavigatorDelegate::navigator:locationDidChange
  func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    print(TAG, "onPageChanged: \(locator)")

    let newHref = strippedHref(locator.href.string)

    if isVerticalScroll, let oldHref = currentSpineItemHref, newHref != oldHref {
      // Store last known position for the spine item we are leaving
      if let outgoing = lastSpineItemLocator {
        spineItemHistory[oldHref] = outgoing
      }

      // Restore position if swiping backward and we have a stored position
      let readingOrder = readiumViewController.publication.readingOrder
      if isBackwardNavigation(from: oldHref, to: newHref, in: readingOrder),
         let stored = spineItemHistory[newHref] {
        Task { @MainActor in
          // emitOnPageChanged fires inside goToLocator — persistent save
          // correctly updates to the restored position as a side effect.
          await self.goToLocator(locator: stored, animated: false)
        }
      }
    }

    currentSpineItemHref = newHref
    lastSpineItemLocator = locator

    if !hasSentReady {
      FlureadiumPlugin.shared?.sendReaderStatus(ReadiumReaderStatusReady)
      hasSentReady = true
    }
    emitOnPageChanged(locator: locator)
  }

  func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      print(TAG, "skipped non-http external URL: \(url)")
      return
    }
    emitOnExternalLinkActivated(url: url)
  }

  func applyDecorations(_ decorations: [Decoration], forGroup groupIdentifier: String) {
    print(TAG, "onMethodApplyDecorations: \(decorations) identifier: \(groupIdentifier)")
    self.readiumViewController.apply(decorations: decorations, in: groupIdentifier)
  }

  func getFirstVisibleLocator() async -> Locator? {
    return await self.readiumViewController.firstVisibleElementLocator()
  }

  func getCurrentLocation() -> Locator? {
    return self.readiumViewController.currentLocation
  }

  func getCurrentSelection() -> Locator? {
    return self.readiumViewController.currentSelection?.locator
  }

  private func evaluateJavascript(_ code: String) async -> Result<Any, Error> {
    return await self.readiumViewController.evaluateJavaScript(code)
  }

  private func evaluateJSReturnResult(_ code: String, result: @escaping FlutterResult) {
    Task.detached(priority: .high) {
      do {
        let data = try await self.evaluateJavascript(code).get()
        print(TAG, "evaluateJSReturnResult result: \(data)")
        await MainActor.run() {
          return result(data)
        }
      } catch (let err) {
        print(TAG, "evaluateJSReturnResult error: \(err)")
        await MainActor.run() {
          return result(nil)
        }
      }
    }
  }

  private func setUserPreferences(preferences: EPUBPreferences) {
    isVerticalScroll = preferences.scroll ?? false
    self.readiumViewController.submitPreferences(preferences)
    configureEdgeTapHandlers(isScrollMode: isVerticalScroll)
  }

  /// Re-applies edge tap and swipe wiring for the current scroll mode.
  private func configureEdgeTapHandlers(isScrollMode: Bool) {
    guard let edgeTapView = _view as? EdgeTapInterceptView else { return }
    edgeNavigation.configure(
      edgeTapView: edgeTapView,
      navigator: readiumViewController,
      isScrollMode: isScrollMode,
      animated: true
    )
  }

  private func emitOnPageChanged(locator: Locator) -> Void {
    let json = locator.jsonString ?? "null"

    print(TAG, "emitOnPageChanged:locator=\(String(describing: locator))")

    Task.detached(priority: .high) { [isVerticalScroll, weak self] in
      guard let self else { return }
      let isDisposed = await MainActor.run { self.isDisposed }
      guard !isDisposed else { return }
      guard let locatorWithFragments = await self.getLocatorFragments(json, isVerticalScroll) else {
        print(TAG, "emitOnPageChanged failed!")
        return
      }
      await MainActor.run {
        guard !self.isDisposed else { return }
        self.channel.onPageChanged(locator: locatorWithFragments)
        FlureadiumPlugin.shared?.sendTextLocator(locatorWithFragments.jsonString)
      }
    }
  }

  private func emitOnExternalLinkActivated(url: URL) {
    print(TAG, "emitOnExternalLinkActivated: \(url)")
    Task.detached(priority: .high) {
      await MainActor.run() {
        self.channel.onExternalLinkActivated(url: url)
      }
    }
  }

  internal func getLocatorFragments(_ locatorJson: String, _ isVerticalScroll: Bool) async -> Locator? {
    guard !isDisposed else {
      return nil
    }

    switch await self.evaluateJavascript("window.epubPage.getLocatorFragments(\(locatorJson), \(isVerticalScroll));") {
      case .success(let jresult):
        guard let locatorWithFragments = parseLocatorFragmentsResult(jresult) else {
          print(TAG, "getLocatorFragments: failed to parse locator from JS result")
          return nil
        }
        return locatorWithFragments
      case .failure(let err):
        print(TAG, "getLocatorFragments failed! \(err)")
        return nil
      }
  }

  private func scrollTo(locations: Locator.Locations, toStart: Bool) async -> Void {
    let json = locations.jsonString ?? "null"
    print(TAG, "scrollTo: Go to locations \(json), toStart: \(toStart)")

    let _ = await evaluateJavascript("window.epubPage.scrollToLocations(\(json),\(isVerticalScroll),\(toStart));")
  }

  func goToLocator(locator: Locator, animated: Bool) async -> Void {
    // Explicit navigation (TOC, skipToPrevious, etc.) must not trigger restoration.
    // Clearing history for this target prevents a subsequent swipe-back from
    // landing at a stale stored position rather than the TOC-specified location.
    spineItemHistory.removeValue(forKey: strippedHref(locator.href.string))

    let locations = locator.locations
    let shouldScroll = canScroll(locations: locations)
    let shouldGo = readiumViewController.currentLocation?.href != locator.href
    let readiumViewController = self.readiumViewController

    if shouldGo {
      print(TAG, "goToLocator: Go to \(locator.href)")
      let goToSuccees = await readiumViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
      if (goToSuccees && shouldScroll) {
        await self.scrollTo(locations: locations, toStart: false)
        self.emitOnPageChanged()
      }
    } else {
      print(TAG, "goToLocator: Already there, Scroll to \(locator.href)")
      if (shouldScroll) {
        await self.scrollTo(locations: locations, toStart: false)
        self.emitOnPageChanged()
      }
    }
  }

  func justGoToLocator(_ locator: Locator, animated: Bool) async -> Bool {
    return await readiumViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
  }

  private func setLocation(locator: Locator, isAudioBookWithText: Bool) async -> Result<Any, Error> {
    let json = locator.jsonString ?? "null"

    return await evaluateJavascript("window.epubPage.setLocation(\(json), \(isAudioBookWithText));")
  }

  private func emitOnPageChanged() {
    guard let locator = readiumViewController.currentLocation else {
      print(TAG, "emitOnPageChanged: currentLocation = nil!")
      return
    }
    print(TAG, "emitOnPageChanged: Calling navigator:locationDidChange.")
    navigator(readiumViewController, locationDidChange: locator)
  }

  func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "go":
      let args = call.arguments as! [Any?]
      print(TAG, "onMethodCall[go] locator = \(args[0] as! String)")
      let locator = try! Locator(jsonString: args[0] as! String, warnings: readiumBugLogger)!
      let animated = args[1] as! Bool
      let isAudioBookWithText = args[2] as? Bool ?? false

      Task { @MainActor in
        await self.goToLocator(locator: locator, animated: animated)
        let _ = await self.setLocation(locator: locator, isAudioBookWithText: isAudioBookWithText)
        result(true)
      }
      break
    case "goLeft":
      let animated = call.arguments as! Bool
      let readiumViewController = self.readiumViewController

      Task { @MainActor in
        let success = await readiumViewController.goLeft(options: NavigatorGoOptions(animated: animated))
        result(success)
      }
      break
    case "goRight":
      let animated = call.arguments as! Bool
      let readiumViewController = self.readiumViewController

      Task { @MainActor in
        let success = await readiumViewController.goRight(options: NavigatorGoOptions(animated: animated))
        result(success)
      }
      break
    case "setLocation":
      let args = call.arguments as! [Any]
      print(TAG, "onMethodCall[setLocation] locator = \(args[0] as! String)")
      let locator = try! Locator(jsonString: args[0] as! String, warnings: readiumBugLogger)!
      let isAudioBookWithText = args[1] as? Bool ?? false
      Task.detached(priority: .high) {
        let _ = await self.setLocation(locator: locator, isAudioBookWithText: isAudioBookWithText)
        return await MainActor.run() {
          result(true)
        }
      }
      break
    case "getLocatorFragments":
      let args = call.arguments as? String ?? "null"
      Task.detached(priority: .high) {
        do {
          let data = try await self.evaluateJavascript("window.epubPage.getLocatorFragments(\(args), true);").get()
          await MainActor.run() {
            return result(data)
          }
        } catch (let err) {
          print(TAG, "getLocatorFragments error \(err)")
          await MainActor.run() {
            return result(false)
          }
        }
      }
      break
    case "getCurrentLocator":
      let args = call.arguments as? String ?? "null"
      print(TAG, "onMethodCall[currentLocator] args = \(args)")
      Task.detached(priority: .high) { [isVerticalScroll] in
        guard let json = await self.readiumViewController.currentLocation?.jsonString else {
          await MainActor.run { result(nil) }
          return
        }
        let data = await self.getLocatorFragments(json, isVerticalScroll)
        await MainActor.run {
          result(data?.jsonString)
        }
      }
      break
    case "isLocatorVisible":
      let args = call.arguments as! String
      print(TAG, "onMethodCall[isLocatorVisible] locator = \(args)")
      let locator = try! Locator(jsonString: args, warnings: readiumBugLogger)!
      if locator.href != self.readiumViewController.currentLocation?.href {
        result(false)
        return
      }
      evaluateJSReturnResult("window.epubPage.isLocatorVisible(\(args));", result: result)
      break
    case "isReaderReady":
      self.evaluateJSReturnResult("""
                (function() {
                    if (typeof window.epubPage !== 'undefined' && typeof window.epubPage.isReaderReady === 'function') {
                        return window.epubPage.isReaderReady();
                    } else {
                        return false;
                    }
                })();
            """, result: result)
      break
    case "setPreferences":
      let args = call.arguments as! [String: String]
      print(TAG, "onMethodCall[setPreferences] args = \(args)")
      let preferences = EPUBPreferences.init(fromMap: args)
      setUserPreferences(preferences: preferences)
      break
    case "setNavigationConfig":
      let args = call.arguments as! [String: Any]
      print(TAG, "onMethodCall[setNavigationConfig] args = \(args)")
      edgeNavigation.apply(FlutterNavigationConfig(fromMap: args))
      configureEdgeTapHandlers(isScrollMode: isVerticalScroll)
      result(nil)
    case "applyDecorations":
      let args = call.arguments as! [Any?]
      let identifier = args[0] as! String
      let decorationsStr = args[1] as! [String]

      guard let decorations = try? decorationsStr.map({ try Decoration(fromJson: $0) }) else {
        return result(FlutterError.init(
          code: "JSON mapping error",
          message: "Could not map decorations from JSON: \(decorationsStr)",
          details: nil))
      }

      print(TAG, "onMethodCall[setPreferences] args = \(args)")
      applyDecorations(decorations, forGroup: identifier)
      break
    case "dispose":
      print(TAG, "Disposing readiumViewController")
      isDisposed = true
      if let token = tapObserverToken { readiumViewController.removeObserver(token) }
      tapObserverToken = nil
      readiumViewController.view.removeFromSuperview()
      readiumViewController.delegate = nil
      FlureadiumPlugin.shared?.sendReaderStatus(ReadiumReaderStatusClosed)
      channel.setMethodCallHandler(nil)
      if currentReaderView === self { currentReaderView = nil }
      result(nil)
      break
    default:
      print(TAG, "Unhandled call \(call.method)")
      result(FlutterMethodNotImplemented)
      break
    }
  }

}

func strippedHref(_ href: String) -> String {
  href.components(separatedBy: "#").first?
      .components(separatedBy: "?").first ?? href
}

func chapterLink(before currentHref: String, in readingOrder: [Link]) -> Link? {
  let clean = strippedHref(currentHref)
  guard let idx = readingOrder.firstIndex(where: { strippedHref($0.href) == clean }),
        idx > 0 else { return nil }
  return readingOrder[idx - 1]
}

func chapterLink(after currentHref: String, in readingOrder: [Link]) -> Link? {
  let clean = strippedHref(currentHref)
  guard let idx = readingOrder.firstIndex(where: { strippedHref($0.href) == clean }),
        idx < readingOrder.count - 1 else { return nil }
  return readingOrder[idx + 1]
}

func isBackwardNavigation(from oldHref: String, to newHref: String, in readingOrder: [Link]) -> Bool {
  let cleanOld = strippedHref(oldHref)
  let cleanNew = strippedHref(newHref)
  guard let oldIdx = readingOrder.firstIndex(where: { strippedHref($0.href) == cleanOld }),
        let newIdx = readingOrder.firstIndex(where: { strippedHref($0.href) == cleanNew }) else {
    return false
  }
  return newIdx < oldIdx
}

private func canScroll(locations: Locator.Locations?) -> Bool {
  guard let locations = locations else { return false }
  return locations.domRange != nil || locations.cssSelector != nil || locations.progression != nil
}
