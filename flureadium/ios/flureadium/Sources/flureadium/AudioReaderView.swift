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
/// live but empty view that owns the per-view method channel and nothing else;
/// the reader-status and text-locator channels belong to `FlureadiumPlugin`.
///
/// It reports "ready" from `init` because nothing else will: readiness is
/// otherwise emitted from `navigator(_:locationDidChange:)`, which needs a
/// navigator. Reusing the existing status string is deliberate —
/// `method_channel_flureadium.dart:80` maps statuses with `firstWhere` and no
/// `orElse`, so an unknown string would throw `StateError` in every host app.
/// Mirrors `ReadiumReaderWidget.kt:188-196`.
final class AudioReaderView: NSObject, FlutterPlatformView {

  private let channel: ReadiumReaderChannel
  private let _view = UIView()

  init(viewIdentifier viewId: Int64, messenger: FlutterBinaryMessenger) {
    print(TAG, "::init")
    channel = ReadiumReaderChannel(
      name: "\(readiumReaderViewType):\(viewId)", binaryMessenger: messenger)
    super.init()

    channel.setMethodCallHandler(onMethodCall)
    // The status a host waits for. It is sent before any subscriber exists, so
    // the plugin's ReaderStatusEventStream holds it until Dart subscribes.
    FlureadiumPlugin.shared?.sendReaderStatus(AudioReaderStatusLoading)
    FlureadiumPlugin.shared?.sendReaderStatus(AudioReaderStatusReady)
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
      FlureadiumPlugin.shared?.sendReaderStatus(AudioReaderStatusClosed)
      channel.setMethodCallHandler(nil)
      result(nil)
    default:
      print(TAG, "Unhandled call \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }
}
