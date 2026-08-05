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
  private var readerStatusStreamHandler: EventStreamHandler?
  private var textLocatorStreamHandler: EventStreamHandler?
  private let viewContainer: UIView
  private let imageViewController: CBZNavigatorViewController
  private var hasSentReady = false
  private var navigationState = ImageReaderNavigationState()
  private var visitedIndices = Set<Int>()
  private var prefetchTask: Task<Void, Never>?

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
    textLocatorStreamHandler = EventStreamHandler(withName: "text-locator", messenger: registrar.messenger())
    readerStatusStreamHandler = ReaderStatusEventStream(withName: "reader-status", messenger: registrar.messenger())

    readerStatusStreamHandler?.sendEvent(ImageReaderStatusLoading)

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
    let child: UIView = imageViewController.view!
    let parent = viewContainer
    parent.addSubview(child)

    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
      child.topAnchor.constraint(equalTo: parent.topAnchor),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])

    currentImageReaderView = self
    configureEdgeTapHandlers()

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
    readerStatusStreamHandler?.sendEvent(ImageReaderStatusError)
    // Route through the plugin, which owns the single "error" channel.
    FlureadiumPlugin.shared?.sendError(
      message: error.localizedDescription, code: "DidFailToLoadResource", data: href.string)
  }

  func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    print(TAG, "onPageChanged: \(locator)")
    if !hasSentReady {
      readerStatusStreamHandler?.sendEvent(ImageReaderStatusReady)
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
    navigationState.configure(
      edgeTapView: edgeTapView,
      onLeftEdgeTap: { [weak self] in
        guard let self else { return }
        Task { @MainActor in
          let _ = await self.imageViewController.goLeft(options: NavigatorGoOptions(animated: false))
        }
      },
      onRightEdgeTap: { [weak self] in
        guard let self else { return }
        Task { @MainActor in
          let _ = await self.imageViewController.goRight(options: NavigatorGoOptions(animated: false))
        }
      },
      onSwipeLeft: { [weak self] in
        guard let self else { return }
        Task { @MainActor in
          let _ = await self.imageViewController.goRight(options: NavigatorGoOptions(animated: false))
        }
      },
      onSwipeRight: { [weak self] in
        guard let self else { return }
        Task { @MainActor in
          let _ = await self.imageViewController.goLeft(options: NavigatorGoOptions(animated: false))
        }
      }
    )
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
      self.textLocatorStreamHandler?.sendEvent(locator.jsonString)
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
      let args = call.arguments as! [String: Any]
      let navConfig = FlutterNavigationConfig(fromMap: args)
      navigationState.apply(navConfig)
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
      readerStatusStreamHandler?.sendEvent(ImageReaderStatusClosed)
      textLocatorStreamHandler?.dispose()
      textLocatorStreamHandler = nil
      readerStatusStreamHandler?.dispose()
      readerStatusStreamHandler = nil
      channel.setMethodCallHandler(nil)
      if currentImageReaderView === self { currentImageReaderView = nil }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
