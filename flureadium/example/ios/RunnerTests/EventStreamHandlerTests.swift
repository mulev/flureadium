//
//  EventStreamHandlerTests.swift
//  RunnerTests
//
//  Unit tests for EventStreamHandler lifecycle behavior.
//

import XCTest
import Flutter
@testable import flureadium

/// Minimal mock of FlutterBinaryMessenger for testing EventStreamHandler
/// without a running Flutter engine.
private class MockBinaryMessenger: NSObject, FlutterBinaryMessenger {

    var sentMessages: [(channel: String, message: Data?)] = []

    func send(onChannel channel: String, message: Data?) {
        sentMessages.append((channel: channel, message: message))
    }

    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        sentMessages.append((channel: channel, message: message))
        callback?(nil)
    }

    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
        return FlutterBinaryMessengerConnection(0)
    }

    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

final class EventStreamHandlerTests: XCTestCase {

    private var messenger: MockBinaryMessenger!

    override func setUp() {
        super.setUp()
        messenger = MockBinaryMessenger()
    }

    override func tearDown() {
        messenger = nil
        super.tearDown()
    }

    // MARK: - Dispose Tests

    func testDisposeDoesNotCrash() {
        let handler = EventStreamHandler(withName: "test-stream", messenger: messenger)
        // Should not crash even without an active listener
        handler.dispose()
    }

    func testDisposeCalledTwiceDoesNotCrash() {
        let handler = EventStreamHandler(withName: "test-stream", messenger: messenger)
        handler.dispose()
        handler.dispose()
    }

    func testSendEventAfterDisposeIsNoOp() {
        let handler = EventStreamHandler(withName: "test-stream", messenger: messenger)
        handler.dispose()
        // Should not crash — eventSink is nil after dispose
        handler.sendEvent("some event")
    }

    // MARK: - Listener Lifecycle Tests

    func testSendEventWithoutListenerIsNoOp() {
        let handler = EventStreamHandler(withName: "test-stream", messenger: messenger)
        // No listener registered, should not crash
        handler.sendEvent("some event")
    }

    func testOnListenSetsEventSink() {
        let handler = EventStreamHandler(withName: "test-stream", messenger: messenger)
        var receivedEvents: [Any?] = []

        let error = handler.onListen(withArguments: nil) { event in
            receivedEvents.append(event)
        }

        XCTAssertNil(error, "onListen should not return an error")

        handler.sendEvent("test-event")
        XCTAssertEqual(receivedEvents.count, 1, "Event should be received after onListen")
        XCTAssertEqual(receivedEvents.first as? String, "test-event")
    }

    func testOnCancelClearsEventSink() {
        let handler = EventStreamHandler(withName: "test-stream", messenger: messenger)
        var receivedEvents: [Any?] = []

        _ = handler.onListen(withArguments: nil) { event in
            receivedEvents.append(event)
        }

        let error = handler.onCancel(withArguments: nil)
        XCTAssertNil(error, "onCancel should not return an error")

        handler.sendEvent("after-cancel")
        XCTAssertEqual(receivedEvents.count, 0, "No events should be received after onCancel")
    }

    func testDisposeSendsEndOfStreamBeforeClearing() {
        let handler = EventStreamHandler(withName: "test-stream", messenger: messenger)
        var receivedEvents: [Any?] = []

        _ = handler.onListen(withArguments: nil) { event in
            receivedEvents.append(event)
        }

        handler.dispose()

        // FlutterEndOfEventStream should have been sent
        XCTAssertEqual(receivedEvents.count, 1, "dispose should send FlutterEndOfEventStream")
        XCTAssertTrue(receivedEvents.first is NSObject, "End-of-stream sentinel should be sent")

        // After dispose, sending should be a no-op
        handler.sendEvent("after-dispose")
        XCTAssertEqual(receivedEvents.count, 1, "No events should be received after dispose")
    }
}
