//
//  ReaderStatusEventStreamTests.swift
//  RunnerTests
//
//  Unit tests for the reader-status replay buffer: a status sent while nobody
//  is listening must still reach the first subscriber that arrives.
//

import XCTest
import Flutter
@testable import flureadium

/// Minimal mock of FlutterBinaryMessenger so the stream can be constructed
/// without a running Flutter engine.
private class MockBinaryMessenger: NSObject, FlutterBinaryMessenger {

    func send(onChannel channel: String, message: Data?) {}

    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        callback?(nil)
    }

    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
        return FlutterBinaryMessengerConnection(0)
    }

    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

final class ReaderStatusEventStreamTests: XCTestCase {

    private var messenger: MockBinaryMessenger!

    override func setUp() {
        super.setUp()
        messenger = MockBinaryMessenger()
    }

    override func tearDown() {
        messenger = nil
        super.tearDown()
    }

    private func makeStream() -> ReaderStatusEventStream {
        return ReaderStatusEventStream(withName: "reader-status", messenger: messenger)
    }

    // MARK: - Replay

    func testStatusSentBeforeSubscriberIsReplayedOnListen() {
        let stream = makeStream()
        var received: [Any?] = []

        // A reader view reports its status from init, before Flutter has
        // replied to Dart and before any host app can subscribe.
        stream.sendEvent("ready")

        let error = stream.onListen(withArguments: nil) { received.append($0) }

        XCTAssertNil(error, "onListen should not return an error")
        XCTAssertEqual(received.count, 1, "the status sent before the subscriber should be replayed")
        XCTAssertEqual(received.first as? String, "ready")
    }

    func testOnlyTheLatestPendingStatusIsReplayed() {
        let stream = makeStream()
        var received: [Any?] = []

        stream.sendEvent("loading")
        stream.sendEvent("ready")

        _ = stream.onListen(withArguments: nil) { received.append($0) }

        XCTAssertEqual(received.count, 1, "status is a state, not a log — nothing may accumulate")
        XCTAssertEqual(received.first as? String, "ready", "the latest status wins")
    }

    // MARK: - Direct delivery

    func testStatusSentAfterSubscriberIsDeliveredImmediately() {
        let stream = makeStream()
        var received: [Any?] = []

        _ = stream.onListen(withArguments: nil) { received.append($0) }
        stream.sendEvent("ready")

        XCTAssertEqual(received.count, 1, "with a live sink the status should not be buffered")
        XCTAssertEqual(received.first as? String, "ready")
    }

    func testReplayedStatusIsDeliveredOnce() {
        let stream = makeStream()
        var firstSink: [Any?] = []
        var secondSink: [Any?] = []

        stream.sendEvent("ready")
        _ = stream.onListen(withArguments: nil) { firstSink.append($0) }
        _ = stream.onCancel(withArguments: nil)
        _ = stream.onListen(withArguments: nil) { secondSink.append($0) }

        XCTAssertEqual(firstSink.count, 1, "the first subscriber receives the replay")
        XCTAssertTrue(secondSink.isEmpty, "a delivered status must not be replayed to the next subscriber")
    }

    func testStatusSentBetweenSubscriptionsIsBufferedAgain() {
        let stream = makeStream()
        var firstSink: [Any?] = []
        var secondSink: [Any?] = []

        _ = stream.onListen(withArguments: nil) { firstSink.append($0) }
        _ = stream.onCancel(withArguments: nil)

        // A publication swap: the host cancels, a new view reports its status,
        // then the host re-subscribes from onReady.
        stream.sendEvent("ready")
        _ = stream.onListen(withArguments: nil) { secondSink.append($0) }

        XCTAssertTrue(firstSink.isEmpty, "the cancelled subscriber must receive nothing")
        XCTAssertEqual(secondSink.count, 1, "buffering resumes once the sink is cleared")
        XCTAssertEqual(secondSink.first as? String, "ready")
    }

    // MARK: - Dispose

    func testDisposeDropsThePendingStatus() {
        let stream = makeStream()
        var received: [Any?] = []

        stream.sendEvent("ready")
        stream.dispose()

        _ = stream.onListen(withArguments: nil) { received.append($0) }

        XCTAssertTrue(received.isEmpty, "a status buffered for a subscriber that never arrived is stale")
    }
}
