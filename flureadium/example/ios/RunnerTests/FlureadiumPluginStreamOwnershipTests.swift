//
//  FlureadiumPluginStreamOwnershipTests.swift
//  RunnerTests
//
//  The plugin owns every shared event channel. A reader view is shorter-lived
//  than the Dart subscription to those channels, so only the plugin may
//  end-stream them.
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

final class FlureadiumPluginStreamOwnershipTests: XCTestCase {

  private var plugin: FlureadiumPlugin!
  private var readerStatus: CapturingEventStreamSink!
  private var textLocator: CapturingEventStreamSink!

  override func setUp() {
    super.setUp()
    plugin = FlureadiumPlugin()
    readerStatus = CapturingEventStreamSink()
    textLocator = CapturingEventStreamSink()
    plugin.readerStatusStreamHandler = readerStatus
    plugin.textLocatorStreamHandler = textLocator
  }

  override func tearDown() {
    plugin = nil
    readerStatus = nil
    textLocator = nil
    super.tearDown()
  }

  // MARK: - Send paths

  func testSendReaderStatusRoutesToTheOwnedStream() {
    plugin.sendReaderStatus("ready")

    XCTAssertEqual(readerStatus.events.map { $0 as? String }, ["ready"])
    XCTAssertTrue(textLocator.events.isEmpty, "a status must not leak onto the locator channel")
  }

  func testSendTextLocatorRoutesToTheOwnedStream() {
    let locator = #"{"href":"chapter1.xhtml","type":"application/xhtml+xml"}"#

    plugin.sendTextLocator(locator)

    XCTAssertEqual(textLocator.events.map { $0 as? String }, [locator])
    XCTAssertTrue(readerStatus.events.isEmpty, "a locator must not leak onto the status channel")
  }

  func testSendersAreSafeBeforeRegisterHasRun() {
    let bare = FlureadiumPlugin()

    // No handlers yet: register(with:) creates them. Sending must not trap —
    // a reader view can be built before the plugin finishes registering.
    bare.sendReaderStatus("loading")
    bare.sendTextLocator(nil)
  }

  // MARK: - Subscribe-time answer

  func testTextLocatorStreamAnswersANewSubscriberWithTheCurrentPosition() {
    let json = #"{"href":"page1.jpg","type":"image/jpeg"}"#
    let stream = TextLocatorEventStream(
      withName: "text-locator-test", messenger: StubBinaryMessenger(),
      currentLocatorJson: { json })
    let sink = CapturingEventStreamSink()

    _ = stream.onListen(withArguments: nil, eventSink: { sink.sendEvent($0) })

    // An image publication emits its only locator for the page before Dart can
    // subscribe, so without this a CBZ reader looks position-less.
    XCTAssertEqual(sink.events.map { $0 as? String }, [json])
  }

  func testTextLocatorStreamSendsNothingWhenNoReaderHasAPosition() {
    let stream = TextLocatorEventStream(
      withName: "text-locator-test", messenger: StubBinaryMessenger(),
      currentLocatorJson: { nil })
    let sink = CapturingEventStreamSink()

    _ = stream.onListen(withArguments: nil, eventSink: { sink.sendEvent($0) })

    XCTAssertTrue(sink.events.isEmpty, "no reader open means nothing to report")
  }

  // MARK: - Ownership

  func testPluginDisposeEndStreamsBothChannels() {
    let disposed = expectation(description: "plugin dispose answered")

    plugin.handle(FlutterMethodCall(methodName: "dispose", arguments: nil)) { _ in
      disposed.fulfill()
    }
    wait(for: [disposed], timeout: 5)

    XCTAssertTrue(readerStatus.disposed, "only the plugin may end-stream the shared channels")
    XCTAssertTrue(textLocator.disposed)
    XCTAssertNil(plugin.readerStatusStreamHandler, "the released handler must not be reachable")
    XCTAssertNil(plugin.textLocatorStreamHandler)
  }

  func testAReaderViewDisposeLeavesTheChannelsOpen() {
    FlureadiumPlugin.shared = plugin
    defer { FlureadiumPlugin.shared = nil }
    let messenger = StubBinaryMessenger()
    let view = AudioReaderView(viewIdentifier: 3, messenger: messenger)

    let answered = expectation(description: "view dispose answered")
    view.onMethodCall(call: FlutterMethodCall(methodName: "dispose", arguments: nil)) { _ in
      answered.fulfill()
    }
    wait(for: [answered], timeout: 5)

    XCTAssertEqual(
      readerStatus.events.last as? String, "closed",
      "the view still reports its own closure")
    XCTAssertFalse(
      readerStatus.disposed,
      "end-streaming here would close the host's subscription for the rest of the session")
    XCTAssertFalse(textLocator.disposed)
  }
}

/// Minimal FlutterBinaryMessenger so a reader view can be built without an engine.
private final class StubBinaryMessenger: NSObject, FlutterBinaryMessenger {

  func send(onChannel channel: String, message: Data?) {}

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    callback?(nil)
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    return FlutterBinaryMessengerConnection(0)
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
