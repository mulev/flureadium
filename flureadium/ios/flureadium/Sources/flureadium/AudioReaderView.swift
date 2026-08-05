import Flutter
import Foundation
import UIKit

private let TAG = "AudioReaderView"
private let AudioReaderStatusLoading = "loading"
private let AudioReaderStatusReady = "ready"
private let AudioReaderStatusClosed = "closed"

/// Platform-view host for an audio-only publication.
///
/// An audio-only publication has nothing to render, so this host builds no
/// navigator: no `EPUBNavigatorViewController`, no pagination view, no preload
/// WKWebViews, no `httpServer.serve` routes, no ReadiumCSS transformer. It is a
/// live but empty view that owns the per-view method channel and the two event
/// streams a host app subscribes to from `ReadiumReaderWidget.onReady`.
///
/// It reports "ready" from `init` because nothing else will: readiness is
/// otherwise emitted from `navigator(_:locationDidChange:)`, which needs a
/// navigator. Reusing the existing status string is deliberate —
/// `method_channel_flureadium.dart:80` maps statuses with `firstWhere` and no
/// `orElse`, so an unknown string would throw `StateError` in every host app.
/// Mirrors `ReadiumReaderWidget.kt:188-196`.
final class AudioReaderView: NSObject, FlutterPlatformView {

  private let channel: ReadiumReaderChannel
  private var readerStatusStream: EventStreamSink?
  private var textLocatorStream: EventStreamSink?
  private let _view = UIView()

  convenience init(viewIdentifier viewId: Int64, messenger: FlutterBinaryMessenger) {
    self.init(
      channel: ReadiumReaderChannel(
        name: "\(readiumReaderViewType):\(viewId)", binaryMessenger: messenger),
      readerStatusStream: ReaderStatusEventStream(
        withName: "reader-status", messenger: messenger),
      // Registered but never sent on: iOS registers the text-locator handler
      // lazily, per reader view, and a host subscribes to it from onReady. A
      // pure-audio first mount that skipped it would raise
      // MissingPluginException in every host app.
      textLocatorStream: EventStreamHandler(withName: "text-locator", messenger: messenger)
    )
  }

  init(
    channel: ReadiumReaderChannel,
    readerStatusStream: EventStreamSink,
    textLocatorStream: EventStreamSink
  ) {
    print(TAG, "::init")
    self.channel = channel
    self.readerStatusStream = readerStatusStream
    self.textLocatorStream = textLocatorStream
    super.init()

    channel.setMethodCallHandler(onMethodCall)
    readerStatusStream.sendEvent(AudioReaderStatusLoading)
    readerStatusStream.sendEvent(AudioReaderStatusReady)
  }

  func view() -> UIView {
    _view
  }

  /// Answers the reader channel with Android's non-EPUB contract
  /// (`ReadiumReaderWidget.kt:759-806, 820-837`).
  func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "go", "goLeft", "goRight", "setLocation",
      "setPreferences", "setNavigationConfig", "applyDecorations":
      // Nothing to navigate, style or decorate. Dart types all of these as
      // Future<void> (lib/reader_channel.dart), so nil is the whole contract.
      result(nil)
    case "getLocatorFragments":
      // No DOM to resolve a fragment against; echo the locator back unchanged
      // (ReadiumReaderWidget.kt:791-795). Dart json-decodes the return value.
      result(call.arguments)
    case "getCurrentLocator":
      result(nil)
    case "isLocatorVisible":
      result(false)
    case "isReaderReady":
      result(true)
    case "dispose":
      print(TAG, "::dispose")
      readerStatusStream?.sendEvent(AudioReaderStatusClosed)
      textLocatorStream?.dispose()
      textLocatorStream = nil
      readerStatusStream?.dispose()
      readerStatusStream = nil
      channel.setMethodCallHandler(nil)
      result(nil)
    default:
      print(TAG, "Unhandled call \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }
}
