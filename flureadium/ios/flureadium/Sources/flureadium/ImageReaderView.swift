import Foundation
import Flutter
import ReadiumNavigator
import ReadiumShared
import UIKit

private let TAG = "ImageReaderView"
private let ImageReaderStatusReady = "ready"
private let ImageReaderStatusLoading = "loading"
private let ImageReaderStatusClosed = "closed"
private let ImageReaderStatusError = "error"
private let ImageReaderNavigationReadyTimeoutNanoseconds: UInt64 = 10_000_000_000
private let ImageReaderNavigationReadyPollNanoseconds: UInt64 = 50_000_000

class ImageReaderView: NSObject, FlutterPlatformView, CBZNavigatorDelegate, VisualNavigatorDelegate {
  private let channel: ReadiumReaderChannel
  // reader-status and text-locator are owned by FlureadiumPlugin: this view is
  // shorter-lived than the Dart subscription to them.
  private let viewContainer: UIView
  private let imageViewController: CBZNavigatorViewController
  private var hasSentReady = false
  private var edgeNavigation = ReaderEdgeNavigationState()
  private var visitedIndices = Set<Int>()
  private var prefetchTask: Task<Void, Never>?
  private var tapObserverToken: InputObservableToken?

  func view() -> UIView {
    print(TAG, "::getView")
    return viewContainer
  }

  deinit {
    print(TAG, "::deinit")
    imageViewController.view.removeFromSuperview()
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

    let locatorStr = creationParams["initialLocator"] as? String
    let locator = locatorStr == nil ? nil : try! Locator(jsonString: locatorStr!)

    channel = ReadiumReaderChannel(
      name: "\(readiumReaderViewType):\(viewId)", binaryMessenger: registrar.messenger())
    FlureadiumPlugin.shared?.sendReaderStatus(ImageReaderStatusLoading)

    imageViewController = try! CBZNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      httpServer: sharedReadium.httpServer!
    )

    viewContainer = EdgeTapInterceptView()
    super.init()

    ImageCacheURLProtocol.enable()

    channel.setMethodCallHandler(onMethodCall)
    imageViewController.delegate = self

    imageViewController.loadViewIfNeeded()
    viewContainer.addPinnedSubview(imageViewController.view!)

    currentImageReaderView = self
    configureEdgeTapHandlers()
    tapObserverToken = observeTaps(on: imageViewController, reportingTo: channel)

    print(TAG, "::init success")
  }

  func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
    .init(top: 0, left: 0, bottom: 0, right: 0)
  }

  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    print(TAG, "presentError: \(error)")
  }

  func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    print(TAG, "didFailToLoadResourceAt: \(href). err: \(error)")
    FlureadiumPlugin.shared?.sendReaderStatus(ImageReaderStatusError)
    // Route through the plugin, which owns the single "error" channel.
    FlureadiumPlugin.shared?.sendError(
      message: error.localizedDescription, code: "DidFailToLoadResource", data: href.string)
  }

  func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    print(TAG, "onPageChanged: \(locator)")
    if !hasSentReady {
      FlureadiumPlugin.shared?.sendReaderStatus(ImageReaderStatusReady)
      hasSentReady = true
    }
    emitOnPageChanged(locator: locator)

    let readingOrder = imageViewController.publication.readingOrder
    if let currentIndex = readingOrder.firstIndexWithHREF(locator.href) {
      visitedIndices.insert(currentIndex)
      prefetchAdjacentPages(around: currentIndex)
    }
  }

  func getCurrentLocation() -> Locator? {
    imageViewController.currentLocation
  }

  @MainActor
  func goToLocator(locator: Locator, animated: Bool) async -> Bool {
    guard await waitUntilReadyForProgrammaticNavigation() else {
      print(TAG, "goToLocator: reader not ready for \(locator.href)")
      return false
    }

    return await imageViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
  }

  @MainActor
  private func waitUntilReadyForProgrammaticNavigation() async -> Bool {
    if isReadyForProgrammaticNavigation {
      return true
    }

    let deadline = DispatchTime.now().uptimeNanoseconds + ImageReaderNavigationReadyTimeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if Task.isCancelled {
        return false
      }

      try? await Task.sleep(nanoseconds: ImageReaderNavigationReadyPollNanoseconds)

      if isReadyForProgrammaticNavigation {
        return true
      }
    }

    return isReadyForProgrammaticNavigation
  }

  @MainActor
  private var isReadyForProgrammaticNavigation: Bool {
    hasSentReady || imageViewController.currentLocation != nil
  }

  private func configureEdgeTapHandlers() {
    guard let edgeTapView = viewContainer as? EdgeTapInterceptView else { return }
    edgeNavigation.configure(
      edgeTapView: edgeTapView, navigator: imageViewController, animated: false)
  }

  private func prefetchAdjacentPages(around currentIndex: Int) {
    prefetchTask?.cancel()
    let publication = imageViewController.publication
    let readingOrder = publication.readingOrder
    let adjacentIndices = [currentIndex - 1, currentIndex + 1, currentIndex + 2]
    let visited = visitedIndices

    prefetchTask = Task {
      for index in adjacentIndices {
        guard !Task.isCancelled else { return }
        guard readingOrder.indices.contains(index) else { continue }
        guard !visited.contains(index) else { continue }

        let link = readingOrder[index]
        guard !ImageCacheURLProtocol.hasPrefetch(href: link.href) else { continue }
        guard let resource = publication.get(link) else { continue }

        let result = await resource.read()
        if let data = try? result.get() {
          ImageCacheURLProtocol.seedPrefetch(
            href: link.href,
            data: data,
            mimeType: link.mediaType?.string
          )
        }
      }
    }
  }

  private func emitOnPageChanged(locator: Locator) {
    print(TAG, "emitOnPageChanged: locator=\(locator)")
    Task { @MainActor in
      self.channel.onPageChanged(locator: locator)
      FlureadiumPlugin.shared?.sendTextLocator(locator.jsonString)
    }
  }

  func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "go":
      let args = call.arguments as! [Any?]
      let locator = try! Locator(jsonString: args[0] as! String)!
      let animated = args[1] as! Bool

      Task { @MainActor in
        let success = await self.goToLocator(locator: locator, animated: animated)
        result(success)
      }
    case "goLeft":
      let animated = call.arguments as! Bool
      Task { @MainActor in
        let success = await self.imageViewController.goLeft(options: NavigatorGoOptions(animated: animated))
        result(success)
      }
    case "goRight":
      let animated = call.arguments as! Bool
      Task { @MainActor in
        let success = await self.imageViewController.goRight(options: NavigatorGoOptions(animated: animated))
        result(success)
      }
    case "getCurrentLocator":
      Task { @MainActor in
        result(self.imageViewController.currentLocation?.jsonString)
      }
    case "setPreferences":
      result(nil)
    case "setNavigationConfig":
      let navConfig = FlutterNavigationConfig(fromMap: call.arguments as? [String: Any])
      edgeNavigation.apply(navConfig)
      configureEdgeTapHandlers()
      result(nil)
    case "applyDecorations":
      result(nil)
    case "isReaderReady":
      result(hasSentReady)
    case "dispose":
      prefetchTask?.cancel()
      prefetchTask = nil
      visitedIndices.removeAll()
      ImageCacheURLProtocol.disable()
      imageViewController.view.removeFromSuperview()
      imageViewController.delegate = nil
      if let token = tapObserverToken { imageViewController.removeObserver(token) }
      tapObserverToken = nil
      FlureadiumPlugin.shared?.sendReaderStatus(ImageReaderStatusClosed)
      channel.setMethodCallHandler(nil)
      if currentImageReaderView === self { currentImageReaderView = nil }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
