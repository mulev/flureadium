//
//  PdfReaderView.swift
//  flureadium
//
//  PDF reader view using Readium's PDFNavigatorViewController.
//  Follows the same pattern as ReadiumReaderView.swift for EPUB.
//

import Foundation
import ReadiumNavigator
import ReadiumShared
import Flutter
import UIKit

private let TAG = "PdfReaderView"
private let PdfReaderStatusReady = "ready"
private let PdfReaderStatusLoading = "loading"
private let PdfReaderStatusClosed = "closed"
private let PdfReaderStatusError = "error"

let pdfReaderViewType = "dev.mulev.flureadium/PdfReaderWidget"

class PdfReaderView: NSObject, FlutterPlatformView, PDFNavigatorDelegate, VisualNavigatorDelegate {

  private let channel: ReadiumReaderChannel
  private var errorStreamHandler: EventStreamHandler?
  private var readerStatusStreamHandler: EventStreamHandler?
  private var textLocatorStreamHandler: EventStreamHandler?
  private let _view: UIView
  private let pdfViewController: PDFNavigatorViewController
  private var hasSentReady = false
  private var gestureSuppression = PdfGestureSuppression()
  private var edgeNavigation = ReaderEdgeNavigationState()
  private var tapObserverToken: InputObservableToken?

  var publicationIdentifier: String?

  func view() -> UIView {
    print(TAG, "::getView")
    return _view
  }

  deinit {
    print(TAG, "::deinit")
    pdfViewController.view.removeFromSuperview()
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

    let preferencesMap = creationParams["preferences"] as? [String: Any]
    let pdfPreferences = preferencesMap != nil ? PDFPreferences(fromMap: preferencesMap!) : PDFPreferences()

    let locatorStr = creationParams["initialLocator"] as? String
    let locator = locatorStr == nil ? nil : try! Locator.init(jsonString: locatorStr!)
    print(TAG, "publication = \(publication)")

    channel = ReadiumReaderChannel(
      name: "\(readiumReaderViewType):\(viewId)", binaryMessenger: registrar.messenger())
    textLocatorStreamHandler = EventStreamHandler(withName: "pdf-text-locator", messenger: registrar.messenger())
    readerStatusStreamHandler = EventStreamHandler(withName: "pdf-reader-status", messenger: registrar.messenger())
    errorStreamHandler = EventStreamHandler(withName: "pdf-error", messenger: registrar.messenger())

    readerStatusStreamHandler?.sendEvent(PdfReaderStatusLoading)

    print(TAG, "Publication: (identifier=\(String(describing: publication.metadata.identifier)),title=\(String(describing: publication.metadata.title)))")

    // Configure PDF navigator
    var config = PDFNavigatorViewController.Configuration()
    config.preferences = pdfPreferences

    pdfViewController = try! PDFNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      config: config,
      httpServer: sharedReadium.httpServer!
    )

    _view = EdgeTapInterceptView()
    super.init()

    channel.setMethodCallHandler(onMethodCall)
    pdfViewController.delegate = self

    _view.addPinnedSubview(pdfViewController.view)

    currentPdfReaderView = self
    publicationIdentifier = publication.metadata.identifier

    configureEdgeTapHandlers()

    // A tap on a PDF link annotation reports here and follows the link:
    // Readium's interactive-element filter is WebView-only.
    tapObserverToken = observeTaps(on: pdfViewController, reportingTo: channel)

    print(TAG, "::init success")
  }

  // MARK: - VisualNavigatorDelegate

  func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
    // All margin & safe-area is handled on the Flutter side.
    return .init(top: 0, left: 0, bottom: 0, right: 0)
  }

  // MARK: - NavigatorDelegate

  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    print(TAG, "presentError: \(error)")
  }

  func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    print(TAG, "didFailToLoadResourceAt: \(href). err: \(error)")

    self.readerStatusStreamHandler?.sendEvent(PdfReaderStatusError)

    let flureadiumError = FlureadiumError(message: error.localizedDescription, code: "DidFailToLoadResource", data: href.string)
    self.errorStreamHandler?.sendEvent(flureadiumError)
  }

  func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    print(TAG, "onPageChanged: \(locator)")
    if (!hasSentReady) {
      self.readerStatusStreamHandler?.sendEvent(PdfReaderStatusReady)
      hasSentReady = true
    }
    if gestureSuppression.disableDoubleTapTextSelection {
      scheduleDisableDoubleTapWordSelection()
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

  // MARK: - PDFNavigatorDelegate

  func navigator(_ navigator: PDFNavigatorViewController, setupPDFView view: PDFDocumentView) {
    print(TAG, "setupPDFView: \(gestureSuppression)")
    gestureSuppression.apply(to: view)
    if gestureSuppression.disableDoubleTapTextSelection {
      scheduleDisableDoubleTapWordSelection()
    }
  }

  // MARK: - Public Methods

  func getCurrentLocation() -> Locator? {
    return self.pdfViewController.currentLocation
  }

  func goToLocator(locator: Locator, animated: Bool) async -> Void {
    let _ = await pdfViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
  }

  // MARK: - Private Methods

  private func setUserPreferences(preferences: PDFPreferences) {
    self.pdfViewController.submitPreferences(preferences)
    configureEdgeTapHandlers()
  }

  /// PDF has no scroll mode on this view path, so the paginated gate always holds.
  private func configureEdgeTapHandlers() {
    guard let edgeTapView = _view as? EdgeTapInterceptView else { return }
    edgeNavigation.configure(
      edgeTapView: edgeTapView, navigator: pdfViewController, animated: true)
  }

  private func emitOnPageChanged(locator: Locator) -> Void {
    print(TAG, "emitOnPageChanged:locator=\(String(describing: locator))")

    Task.detached(priority: .high) {
      await MainActor.run() {
        self.channel.onPageChanged(locator: locator)
        guard let textLocatorStreamHandler = self.textLocatorStreamHandler else {
          print(TAG, "emitOnPageChanged: textLocatorStreamHandler is nil!")
          return
        }
        textLocatorStreamHandler.sendEvent(locator.jsonString)
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

  // MARK: - Double-Tap Word Selection

  /// Schedules repeated attempts to find PDFTextInputView and remove
  /// UITextNonEditableInteraction on the navigator's live view.
  private func scheduleDisableDoubleTapWordSelection() {
    for delay in PdfGestureSuppression.doubleTapRetryDelays {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self = self else { return }
        PdfGestureSuppression.removeDoubleTapWordSelection(in: self.pdfViewController.view)
      }
    }
  }

  // MARK: - Method Channel Handler

  func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "go":
      let args = call.arguments as! [Any?]
      print(TAG, "onMethodCall[go] locator = \(args[0] as! String)")
      let locator = try! Locator(jsonString: args[0] as! String)!
      let animated = args[1] as! Bool

      Task { @MainActor in
        await self.goToLocator(locator: locator, animated: animated)
        result(true)
      }
    case "goLeft":
      let animated = call.arguments as! Bool
      let pdfViewController = self.pdfViewController

      Task { @MainActor in
        let success = await pdfViewController.goLeft(options: NavigatorGoOptions(animated: animated))
        result(success)
      }
    case "goRight":
      let animated = call.arguments as! Bool
      let pdfViewController = self.pdfViewController

      Task { @MainActor in
        let success = await pdfViewController.goRight(options: NavigatorGoOptions(animated: animated))
        result(success)
      }
    case "getCurrentLocator":
      print(TAG, "onMethodCall[getCurrentLocator]")
      Task.detached(priority: .high) {
        let locator = await self.pdfViewController.currentLocation
        await MainActor.run {
          result(locator?.jsonString)
        }
      }
    case "setPreferences":
      let args = call.arguments as! [String: Any]
      print(TAG, "onMethodCall[setPreferences] args = \(args)")
      let preferences = PDFPreferences(fromMap: args)
      setUserPreferences(preferences: preferences)
      result(nil)
    case "setNavigationConfig":
      let args = call.arguments as! [String: Any]
      print(TAG, "onMethodCall[setNavigationConfig] args = \(args)")
      let navConfig = FlutterNavigationConfig(fromMap: args)
      gestureSuppression.apply(navConfig)
      // setupPDFView has already run — apply to the live view.
      gestureSuppression.apply(to: pdfViewController.view)
      if gestureSuppression.disableDoubleTapTextSelection {
        scheduleDisableDoubleTapWordSelection()
      }
      edgeNavigation.apply(navConfig)
      configureEdgeTapHandlers()
      result(nil)
    case "dispose":
      print(TAG, "Disposing pdfViewController")
      if let token = tapObserverToken { pdfViewController.removeObserver(token) }
      tapObserverToken = nil
      pdfViewController.view.removeFromSuperview()
      pdfViewController.delegate = nil
      self.readerStatusStreamHandler?.sendEvent(PdfReaderStatusClosed)
      textLocatorStreamHandler?.dispose()
      textLocatorStreamHandler = nil
      readerStatusStreamHandler?.dispose()
      readerStatusStreamHandler = nil
      errorStreamHandler?.dispose()
      errorStreamHandler = nil
      channel.setMethodCallHandler(nil)
      if currentPdfReaderView === self { currentPdfReaderView = nil }
      result(nil)
    default:
      print(TAG, "Unhandled call \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }
}
