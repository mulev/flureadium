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
  private var disableDoubleTapZoom: Bool
  private var disableTextSelection: Bool
  private var disableDragGestures: Bool
  private var disableDoubleTapTextSelection: Bool
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

    // Navigation config uses defaults; updated via setNavigationConfig channel call
    disableDoubleTapZoom = false
    disableTextSelection = false
    disableDragGestures = false
    disableDoubleTapTextSelection = false

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
    if disableDoubleTapTextSelection {
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
    print(TAG, "setupPDFView called - disableDoubleTapZoom: \(disableDoubleTapZoom), disableTextSelection: \(disableTextSelection), disableDragGestures: \(disableDragGestures), disableDoubleTapTextSelection: \(disableDoubleTapTextSelection)")

    if disableDoubleTapZoom {
      print(TAG, "Calling disableDoubleTapZoomGesture...")
      disableDoubleTapZoomGesture(in: view)
    }

    if disableTextSelection {
      print(TAG, "Calling disableTextSelectionGesture...")
      disableTextSelectionGesture(in: view)
    }

    if disableDoubleTapTextSelection {
      print(TAG, "Calling removeEditMenuInteractions...")
      removeEditMenuInteractions(in: view)
      scheduleDisableDoubleTapWordSelection()
    }

    if disableDragGestures {
      print(TAG, "Calling disableDragGesturesRecognizer...")
      disableDragGesturesRecognizer(in: view)
    }

    print(TAG, "setupPDFView completed")
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

  private func disableDoubleTapZoomGesture(in view: UIView) {
    // Disable double-tap gesture recognizers on this view
    for gestureRecognizer in view.gestureRecognizers ?? [] {
      if let tapGesture = gestureRecognizer as? UITapGestureRecognizer,
         tapGesture.numberOfTapsRequired == 2 {
        tapGesture.isEnabled = false
      }
    }
    // Recursively disable on all subviews
    for subview in view.subviews {
      disableDoubleTapZoomGesture(in: subview)
    }
  }

  private func disableTextSelectionGesture(in view: UIView) {
    print(TAG, "disableTextSelectionGesture: Found \(view.gestureRecognizers?.count ?? 0) gesture(s) on \(type(of: view))")

    var disabledCount = 0

    if let gestureRecognizers = view.gestureRecognizers {
      for recognizer in gestureRecognizers {
        // UILongPressGestureRecognizer - for text selection
        if recognizer is UILongPressGestureRecognizer {
          recognizer.isEnabled = false
          disabledCount += 1
        }

        // UITapGestureRecognizer (single tap) - for showing text selection menu
        if let tapRecognizer = recognizer as? UITapGestureRecognizer {
          if tapRecognizer.numberOfTapsRequired == 1 {
            tapRecognizer.isEnabled = false
            disabledCount += 1
          }
        }
      }
    }

    if disabledCount > 0 {
      print(TAG, "disableTextSelectionGesture: Disabled \(disabledCount) gesture(s) on \(type(of: view))")
    }

    // Recursively disable on all subviews
    for subview in view.subviews {
      disableTextSelectionGesture(in: subview)
    }
  }

  private func disableDragGesturesRecognizer(in view: UIView) {
    // Disable drag gesture recognizers that can trigger text selection/drag-and-drop
    var disabledCount = 0
    for gestureRecognizer in view.gestureRecognizers ?? [] {
      let gestureTypeName = String(describing: type(of: gestureRecognizer))

      // Disable drag gesture recognizers (for text selection/drag-and-drop)
      if gestureTypeName.contains("Drag") {
        print(TAG, "  → Disabling drag gesture: \(gestureTypeName)")
        gestureRecognizer.isEnabled = false
        disabledCount += 1
      }
    }

    if disabledCount > 0 {
      print(TAG, "disableDragGesturesRecognizer: Disabled \(disabledCount) gesture(s) on \(type(of: view))")
    }

    // Recursively disable on all subviews
    for subview in view.subviews {
      disableDragGesturesRecognizer(in: subview)
    }
  }

  private func removeEditMenuInteractions(in view: UIView) {
    print(TAG, "removeEditMenuInteractions: Checking interactions on \(type(of: view))")

    // Remove text selection and editing menu interactions (iOS 13+)
    if #available(iOS 13.0, *) {
      var removedCount = 0
      for interaction in view.interactions {
        let interactionTypeName = String(describing: type(of: interaction))
        let isEditMenuInteraction = interactionTypeName.contains("EditMenu") ||
                                     interactionTypeName.contains("ContextMenu")
        let isTextInteraction = interactionTypeName.contains("TextInteraction")
        if isEditMenuInteraction || isTextInteraction {
          print(TAG, "  → Removing \(interactionTypeName)")
          view.removeInteraction(interaction)
          removedCount += 1
        }
      }
      if removedCount > 0 {
        print(TAG, "  Removed \(removedCount) edit menu interaction(s) from \(type(of: view))")
      }
    }

    // Recursively disable on all subviews
    for subview in view.subviews {
      removeEditMenuInteractions(in: subview)
    }
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

  /// Schedules repeated attempts to find PDFTextInputView and remove UITextNonEditableInteraction.
  /// PDFTextInputView is added asynchronously after page rendering, so a single deferred attempt
  /// is not sufficient — we retry at 0.1s, 0.5s, and 1.0s after the call.
  private func scheduleDisableDoubleTapWordSelection() {
    for delay in [0.1, 0.5, 1.0] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self = self else { return }
        self.disableDoubleTapWordSelection(in: self.pdfViewController.view)
      }
    }
  }

  /// Recursively searches the view tree for PDFTextInputView and removes
  /// UITextNonEditableInteraction — the interaction responsible for double-tap
  /// word selection. Long-press selection lives in UITextRefinementInteraction
  /// and is unaffected.
  private func disableDoubleTapWordSelection(in view: UIView) {
    let className = String(describing: type(of: view))
    if className == "PDFTextInputView" {
      var removed = 0
      for interaction in view.interactions {
        if String(describing: type(of: interaction)) == "UITextNonEditableInteraction" {
          view.removeInteraction(interaction)
          removed += 1
        }
      }
      if removed > 0 {
        print(TAG, "disableDoubleTapWordSelection: removed \(removed) UITextNonEditableInteraction(s) from PDFTextInputView")
      }
      return
    }
    for subview in view.subviews {
      disableDoubleTapWordSelection(in: subview)
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
      if let v = navConfig.disableDoubleTapZoom {
        disableDoubleTapZoom = v
        // setupPDFView has already run — apply immediately to the live view
        if v { disableDoubleTapZoomGesture(in: pdfViewController.view) }
      }
      if let v = navConfig.disableTextSelection {
        disableTextSelection = v
        if v { disableTextSelectionGesture(in: pdfViewController.view) }
      }
      if let v = navConfig.disableDragGestures {
        disableDragGestures = v
        if v { disableDragGesturesRecognizer(in: pdfViewController.view) }
      }
      if let v = navConfig.disableDoubleTapTextSelection {
        disableDoubleTapTextSelection = v
        if v {
          removeEditMenuInteractions(in: pdfViewController.view)
          scheduleDisableDoubleTapWordSelection()
        }
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
