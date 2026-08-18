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

  /// Polls rather than sleeping a fixed amount, so a loaded machine costs time
  /// instead of a failure — docs/05-testing/ios-unit-tests.md, "Async tests".
  @MainActor
  private func poll(until condition: () -> Bool) async {
    for _ in 0..<200 {
      if condition() { return }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
  }

  /// A stream on a stub messenger; `named` reaches the debug log, which is how
  /// two live streams in one test are told apart.
  @MainActor
  private func makeStream(named name: String, reporting json: String?) -> TextLocatorEventStream {
    return TextLocatorEventStream(
      withName: name, messenger: StubBinaryMessenger(), currentLocatorJson: { json })
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

  @MainActor
  func testTextLocatorStreamAnswersANewSubscriberWithTheCurrentPosition() async {
    let json = #"{"href":"page1.jpg","type":"image/jpeg"}"#
    let stream = makeStream(named: "text-locator-test", reporting: json)
    let sink = CapturingEventStreamSink()

    _ = stream.onListen(withArguments: nil, eventSink: { sink.sendEvent($0) })

    // The provider reads a main-actor navigator, so onListen must hand it to a
    // hop and return. Reading it inline is what failed to compile.
    XCTAssertTrue(sink.events.isEmpty, "the provider must not be read inside onListen")

    // An image publication emits its only locator for the page before Dart can
    // subscribe, so without this a CBZ reader looks position-less.
    await poll { sink.events.count == 1 }
    XCTAssertEqual(sink.events.map { $0 as? String }, [json])
  }

  @MainActor
  func testTextLocatorStreamSendsNothingWhenNoReaderHasAPosition() async {
    let silentSink = CapturingEventStreamSink()
    let silent = makeStream(named: "text-locator-test", reporting: nil)
    _ = silent.onListen(withArguments: nil, eventSink: { silentSink.sendEvent($0) })

    // Control: an identical stream with a position must deliver
    // (docs/05-testing/ios-unit-tests.md, "Negative assertions need a positive control").
    let controlSink = CapturingEventStreamSink()
    let control = makeStream(named: "text-locator-control", reporting: #"{"href":"page1.jpg"}"#)
    _ = control.onListen(withArguments: nil, eventSink: { controlSink.sendEvent($0) })

    await poll { !controlSink.events.isEmpty }
    XCTAssertFalse(controlSink.events.isEmpty, "control never delivered — the assertion below proves nothing")
    XCTAssertTrue(silentSink.events.isEmpty, "no reader open means nothing to report")
  }

  /// The hop turns delivery into a later turn, so a cancel can now land in
  /// between. `onCancel` clears the sink, so the hop must find nothing to send.
  @MainActor
  func testTextLocatorStreamSendsNothingWhenTheSubscriberLeftBeforeTheHopLanded() async {
    let sink = CapturingEventStreamSink()
    let stream = makeStream(named: "text-locator-test", reporting: #"{"href":"page1.jpg"}"#)

    _ = stream.onListen(withArguments: nil, eventSink: { sink.sendEvent($0) })
    _ = stream.onCancel(withArguments: nil)

    // Control: a live subscriber on the same class must deliver, so this case
    // cannot pass on a stream that stopped answering altogether.
    let liveSink = CapturingEventStreamSink()
    let live = makeStream(named: "text-locator-control", reporting: #"{"href":"page1.jpg"}"#)
    _ = live.onListen(withArguments: nil, eventSink: { liveSink.sendEvent($0) })

    await poll { !liveSink.events.isEmpty }
    XCTAssertFalse(liveSink.events.isEmpty, "control never delivered — the assertion below proves nothing")
    XCTAssertTrue(sink.events.isEmpty, "a cancelled subscriber must not be sent to")
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
