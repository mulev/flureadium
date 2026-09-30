import XCTest
import Flutter
import ReadiumShared
@testable import flureadium

/// Captures events routed to a sink without needing a real Flutter event
/// channel (which would require a binary messenger).
private final class CapturingEventStreamSink: EventStreamSink {
  var events: [Any?] = []
  var disposed = false

  func sendEvent(_ event: Any?) {
    events.append(event)
  }

  func dispose() {
    disposed = true
  }
}

final class FlureadiumPluginErrorChannelTests: XCTestCase {

  override func setUp() {
    super.setUp()
    currentPublication = nil
    currentReaderView = nil
    currentImageReaderView = nil
    currentPdfReaderView = nil
  }

  override func tearDown() {
    currentPublication = nil
    currentReaderView = nil
    currentImageReaderView = nil
    currentPdfReaderView = nil
    super.tearDown()
  }

  /// Asserts the error payload is a codec-encodable map — not a raw
  /// `FlureadiumError`, which crashes the Flutter standard codec the `"error"`
  /// `EventChannel` uses — and returns it for field assertions.
  private func encodableErrorMap(
    _ event: Any?, file: StaticString = #filePath, line: UInt = #line
  ) -> [String: Any] {
    XCTAssertFalse(
      event is FlureadiumError,
      "error payload must be a codec-encodable map, not a raw FlureadiumError",
      file: file, line: line
    )
    // Reproduces the crash condition: the codec aborts on a non-encodable value.
    XCTAssertFalse(
      FlutterStandardMethodCodec.sharedInstance().encodeSuccessEnvelope(event).isEmpty,
      "error payload must be encodable by the Flutter standard codec",
      file: file, line: line
    )
    guard let map = event as? [String: Any] else {
      XCTFail("error payload must be a [String: Any] map", file: file, line: line)
      return [:]
    }
    return map
  }

  // Test A: sendError forwards the {message, code, data} payload to the
  // plugin-owned error sink as a codec-encodable map.
  func testSendErrorForwardsPayloadToSink() {
    let plugin = FlureadiumPlugin()
    let sink = CapturingEventStreamSink()
    plugin.errorStreamHandler = sink

    plugin.sendError(message: "boom", code: "DidFailToLoadResource", data: "chapter1.xhtml")

    XCTAssertEqual(sink.events.count, 1)
    let map = encodableErrorMap(sink.events[0])
    XCTAssertEqual(map["message"] as? String, "boom")
    XCTAssertEqual(map["code"] as? String, "DidFailToLoadResource")
    XCTAssertEqual(map["data"] as? String, "chapter1.xhtml")
  }

  // Test B (regression for the latent last-writer-wins / end-of-stream bug):
  // the plugin owns a single durable error sink. A reader-view open→dispose
  // cycle tears down that view's own stream handlers, but the plugin's error
  // sink is a separate object and must keep forwarding — no clobber, and no
  // FlutterEndOfEventStream leaked onto it.
  func testSendErrorSurvivesReaderViewLifecycle() {
    let plugin = FlureadiumPlugin()
    let sink = CapturingEventStreamSink()
    plugin.errorStreamHandler = sink

    plugin.sendError(message: "before", code: nil, data: nil)

    // Simulate a reader view's own handlers being created and disposed. These
    // are the non-error channels a reader view owns; disposing them must not
    // touch the plugin's error sink.
    let readerStatus = CapturingEventStreamSink()
    let textLocator = CapturingEventStreamSink()
    readerStatus.dispose()
    textLocator.dispose()

    plugin.sendError(message: "after", code: nil, data: nil)

    XCTAssertEqual(sink.events.count, 2, "both errors reach the durable plugin sink")
    XCTAssertFalse(sink.disposed, "reader-view lifecycle must not dispose the plugin error sink")
    XCTAssertEqual(encodableErrorMap(sink.events[0])["message"] as? String, "before")
    XCTAssertEqual(encodableErrorMap(sink.events[1])["message"] as? String, "after")
    // With nil code/data, toJson omits those keys entirely — the codec-safety
    // property that keeps the payload free of optional dictionary values.
    let firstMap = encodableErrorMap(sink.events[0])
    XCTAssertNil(firstMap["code"], "nil code must be omitted, not sent as a null value")
    XCTAssertNil(firstMap["data"], "nil data must be omitted, not sent as a null value")
  }

  // Test: the plugin's timebased `encounteredError` delegate forwards the audio
  // error onto the error sink as {message, code, data}. This is the audio path's
  // entry point — FlutterAudioNavigator routes both Readium's
  // didFailToLoadResourceAt and the AVFoundation notifications through it.
  @MainActor
  func testEncounteredErrorForwardsToSink() {
    let plugin = FlureadiumPlugin()
    let sink = CapturingEventStreamSink()
    plugin.errorStreamHandler = sink

    let underlying = NSError(
      domain: "avf", code: 9,
      userInfo: [NSLocalizedDescriptionKey: "stream stalled"]
    )
    plugin.timebasedNavigator(
      FlutterAudioNavigator(
        publication: Publication(manifest: Manifest(metadata: Metadata(title: "Audio"))),
        preferences: FlutterAudioPreferences(),
        initialLocator: nil
      ),
      encounteredError: underlying,
      withDescription: "AVPlayerItemFailedToPlayToEndTime"
    )

    XCTAssertEqual(sink.events.count, 1)
    let map = encodableErrorMap(sink.events[0])
    XCTAssertEqual(map["message"] as? String, "stream stalled")
    XCTAssertEqual(map["code"] as? String, "TimebasedError")
    XCTAssertEqual(map["data"] as? String, "AVPlayerItemFailedToPlayToEndTime")
  }

  // Test (regression, flureadium-64fs): no reader view registers an
  // EventChannel of its own. `PdfReaderView` did — `pdf-reader-status`,
  // `pdf-text-locator` and `pdf-error` — and nothing on the Dart side
  // subscribes to those names (`method_channel_flureadium.dart:20,36`), so an
  // iOS PDF reported no status, pushed no text locator and swallowed every
  // resource-load error, for as long as nothing exercised it.
  //
  // The invariant is structural, so the assertion is too: a view builds its
  // channels inside `init` from a live registrar and a publication, neither of
  // which a unit test can produce, so the source is the only place to ask
  // whether a view registers one at all. One case covers all four views, which
  // is the point — the defect was one view drifting from the other three.
  func testNoReaderViewRegistersItsOwnEventChannel() throws {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // RunnerTests
      .deletingLastPathComponent()  // ios
      .deletingLastPathComponent()  // example
      .deletingLastPathComponent()  // flureadium (package root)
      .appendingPathComponent("ios/flureadium/Sources/flureadium")

    let views = try FileManager.default
      .contentsOfDirectory(atPath: sources.path)
      .filter { $0.hasSuffix("ReaderView.swift") }
      .sorted()
    XCTAssertEqual(
      views,
      ["AudioReaderView.swift", "ImageReaderView.swift", "PdfReaderView.swift", "ReadiumReaderView.swift"],
      "reader views moved or were added at \(sources.path) — extend this guard, do not drop it"
    )

    for view in views {
      let source = try String(contentsOf: sources.appendingPathComponent(view), encoding: .utf8)
      XCTAssertFalse(
        source.contains("EventStreamHandler(withName:"),
        "\(view) registers an EventChannel of its own. reader-status, text-locator and error belong to FlureadiumPlugin — send through FlureadiumPlugin.shared, or Dart never hears it"
      )
    }
  }
}
