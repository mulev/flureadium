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

  // Test A: sendError forwards the {message, code, data} payload to the
  // plugin-owned error sink unchanged.
  func testSendErrorForwardsPayloadToSink() {
    let plugin = FlureadiumPlugin()
    let sink = CapturingEventStreamSink()
    plugin.errorStreamHandler = sink

    plugin.sendError(message: "boom", code: "DidFailToLoadResource", data: "chapter1.xhtml")

    XCTAssertEqual(sink.events.count, 1)
    let error = sink.events.first as? FlureadiumError
    XCTAssertNotNil(error, "sendError should forward a FlureadiumError")
    XCTAssertEqual(error?.message, "boom")
    XCTAssertEqual(error?.code, "DidFailToLoadResource")
    XCTAssertEqual(error?.data as? String, "chapter1.xhtml")
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
    XCTAssertEqual((sink.events[0] as? FlureadiumError)?.message, "before")
    XCTAssertEqual((sink.events[1] as? FlureadiumError)?.message, "after")
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
    let error = sink.events.first as? FlureadiumError
    XCTAssertEqual(error?.message, "stream stalled")
    XCTAssertEqual(error?.code, "TimebasedError")
    XCTAssertEqual(error?.data as? String, "AVPlayerItemFailedToPlayToEndTime")
  }
}
