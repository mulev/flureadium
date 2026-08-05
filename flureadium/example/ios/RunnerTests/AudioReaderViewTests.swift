//
//  AudioReaderViewTests.swift
//  RunnerTests
//
//  Unit tests for the audio-only reader host: a platform view that builds no
//  navigator, reports readiness from init, and answers the reader channel with
//  the non-EPUB contract.
//

import XCTest
import Flutter
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

/// Minimal mock of FlutterBinaryMessenger so a real ReadiumReaderChannel can be
/// built without a running Flutter engine.
private final class MockBinaryMessenger: NSObject, FlutterBinaryMessenger {

  /// Channel names the subject registered a handler on.
  var registeredChannels: [String] = []

  func send(onChannel channel: String, message: Data?) {}

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    callback?(nil)
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    if handler != nil { registeredChannels.append(channel) }
    return FlutterBinaryMessengerConnection(0)
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

final class AudioReaderViewTests: XCTestCase {

  private var messenger: MockBinaryMessenger!
  private var readerStatus: CapturingEventStreamSink!
  private var textLocator: CapturingEventStreamSink!

  override func setUp() {
    super.setUp()
    messenger = MockBinaryMessenger()
    readerStatus = CapturingEventStreamSink()
    textLocator = CapturingEventStreamSink()
    currentReaderView = nil
  }

  override func tearDown() {
    currentReaderView = nil
    messenger = nil
    readerStatus = nil
    textLocator = nil
    super.tearDown()
  }

  private func makeView() -> AudioReaderView {
    return AudioReaderView(
      channel: ReadiumReaderChannel(name: "audio-test", binaryMessenger: messenger),
      readerStatusStream: readerStatus,
      textLocatorStream: textLocator
    )
  }

  /// Drives a method call synchronously and returns whatever the handler passed
  /// to its result callback. `called` distinguishes "returned nil" from
  /// "never answered", which would hang the Dart side.
  @discardableResult
  private func call(
    _ view: AudioReaderView, _ method: String, _ arguments: Any? = nil,
    file: StaticString = #filePath, line: UInt = #line
  ) -> Any? {
    var answer: Any?
    var called = false
    view.onMethodCall(call: FlutterMethodCall(methodName: method, arguments: arguments)) {
      answer = $0
      called = true
    }
    XCTAssertTrue(called, "\(method) must answer the channel", file: file, line: line)
    return answer
  }

  // MARK: - Init

  func testInitReportsLoadingThenReady() {
    _ = makeView()

    XCTAssertEqual(
      readerStatus.events.map { $0 as? String }, ["loading", "ready"],
      "an audio host has no navigator to report readiness later, so init is the only chance")
  }

  func testInitSendsNothingOnTextLocator() {
    _ = makeView()

    XCTAssertTrue(
      textLocator.events.isEmpty,
      "the text-locator stream is registered so hosts can subscribe, never sent on")
  }

  func testViewHasNoSubviews() {
    let view = makeView()

    XCTAssertTrue(view.view().subviews.isEmpty, "no navigator means nothing to mount")
  }

  func testInitDoesNotRegisterAsCurrentReaderView() {
    _ = makeView()

    XCTAssertNil(
      currentReaderView,
      "plugin paths that drive the visual reader must stay no-ops for a pure audiobook")
  }

  // MARK: - Query methods

  func testGetLocatorFragmentsEchoesItsArgument() {
    let view = makeView()
    let locator = #"{"href":"track1.mp3","type":"audio/mpeg"}"#

    XCTAssertEqual(call(view, "getLocatorFragments", locator) as? String, locator)
  }

  func testGetLocatorFragmentsEchoesNil() {
    let view = makeView()

    XCTAssertNil(call(view, "getLocatorFragments", nil))
  }

  func testIsReaderReadyIsTrue() {
    let view = makeView()

    XCTAssertEqual(call(view, "isReaderReady") as? Bool, true)
  }

  func testIsLocatorVisibleIsFalse() {
    let view = makeView()

    XCTAssertEqual(
      call(view, "isLocatorVisible", "{}") as? Bool, false,
      "nothing is on screen, so no locator is visible")
  }

  func testGetCurrentLocatorIsNil() {
    let view = makeView()

    XCTAssertNil(call(view, "getCurrentLocator"))
  }

  // MARK: - No-op methods

  func testNavigationAndStylingMethodsAreSilentNoOps() {
    let view = makeView()
    let statusCountAfterInit = readerStatus.events.count

    for method in [
      "go", "goLeft", "goRight", "setLocation",
      "setPreferences", "setNavigationConfig", "applyDecorations",
    ] {
      XCTAssertNil(call(view, method, nil), "\(method) is typed Future<void> in Dart")
    }

    XCTAssertEqual(
      readerStatus.events.count, statusCountAfterInit,
      "a no-op must not look like a state change")
  }

  // MARK: - Dispose

  func testDisposeReportsClosedAndReleasesBothStreams() {
    let view = makeView()

    XCTAssertNil(call(view, "dispose"))

    XCTAssertEqual(readerStatus.events.last as? String, "closed")
    XCTAssertTrue(readerStatus.disposed, "the reader-status stream must be end-streamed")
    XCTAssertTrue(textLocator.disposed, "the text-locator stream must be end-streamed")
  }

  func testDisposeTwiceReportsClosedOnce() {
    let view = makeView()

    call(view, "dispose")
    call(view, "dispose")

    XCTAssertEqual(
      readerStatus.events.filter { $0 as? String == "closed" }.count, 1,
      "the streams are released on the first dispose")
  }

  // MARK: - Unknown methods

  func testUnknownMethodIsNotImplemented() {
    let view = makeView()

    XCTAssertTrue(
      (call(view, "somethingElse") as AnyObject) === (FlutterMethodNotImplemented as AnyObject),
      "an unknown method must reach Dart's MissingPluginException path")
  }

  // MARK: - Convenience init

  func testConvenienceInitRegistersEveryChannelAHostNeeds() {
    _ = AudioReaderView(viewIdentifier: 7, messenger: messenger)

    XCTAssertTrue(
      messenger.registeredChannels.contains("dev.mulev.flureadium/ReadiumReaderWidget:7"),
      "the per-view method channel must carry the same name every reader view uses")
    XCTAssertTrue(
      messenger.registeredChannels.contains("dev.mulev.flureadium/reader-status"),
      "hosts subscribe to reader-status from onReady")
    XCTAssertTrue(
      messenger.registeredChannels.contains("dev.mulev.flureadium/text-locator"),
      "an unregistered text-locator raises MissingPluginException in every host app")
  }
}
