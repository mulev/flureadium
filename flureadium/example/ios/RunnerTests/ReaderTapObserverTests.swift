//
//  ReaderTapObserverTests.swift
//  RunnerTests
//
//  The two halves of the tap path that do not need a live navigator: what the
//  channel puts on the wire, and that registering an observer hands back the
//  token teardown needs.
//

import XCTest
import Flutter
import ReadiumNavigator
@testable import flureadium

/// Records channel traffic instead of sending it, so the message shape can be
/// asserted without a running Flutter engine.
private final class SpyReaderChannel: ReadiumReaderChannel {
  var invocations: [(method: String, arguments: Any?)] = []

  override func invokeMethod(_ method: String, arguments: Any?) {
    invocations.append((method, arguments))
  }
}

/// Minimal FlutterBinaryMessenger so a real channel can be built without an engine.
private final class StubBinaryMessenger: NSObject, FlutterBinaryMessenger {

  func send(onChannel channel: String, message: Data?) {}

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    callback?(nil)
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    FlutterBinaryMessengerConnection(0)
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

/// Stands in for a navigator. Registering on a real one needs a publication, so
/// the fake covers the part `observeTaps` owns: one observer, and the token the
/// caller must keep to unregister.
@MainActor
private final class FakeInputObservable: InputObservable {
  private(set) var observers: [InputObserving] = []
  private(set) var issuedTokens: [InputObservableToken] = []

  func addObserver(_ observer: InputObserving) -> InputObservableToken {
    observers.append(observer)
    let token = InputObservableToken()
    issuedTokens.append(token)
    return token
  }

  func removeObserver(_ token: InputObservableToken) {}
}

final class ReaderTapObserverTests: XCTestCase {

  private func makeChannel() -> SpyReaderChannel {
    SpyReaderChannel(name: "test-channel", binaryMessenger: StubBinaryMessenger())
  }

  func testOnTapSendsThePositionAsAnXYDictionary() {
    let channel = makeChannel()

    channel.onTap(position: CGPoint(x: 12.5, y: 34))

    XCTAssertEqual(channel.invocations.count, 1)
    XCTAssertEqual(channel.invocations.first?.method, "onTap")
    // Dart decodes args['x'] / args['y'] as num — see reader_channel.dart.
    let arguments = channel.invocations.first?.arguments as? [String: Double]
    XCTAssertEqual(arguments?["x"], 12.5)
    XCTAssertEqual(arguments?["y"], 34)
  }

  @MainActor
  func testObserveTapsRegistersOneObserverAndReturnsItsToken() {
    let navigator = FakeInputObservable()
    let channel = makeChannel()

    let token = observeTaps(on: navigator, reportingTo: channel)

    XCTAssertEqual(
      navigator.observers.count, 1,
      "a second registration would report every tap twice")
    XCTAssertEqual(
      token, navigator.issuedTokens.last,
      "the caller needs the navigator's own token to unregister on dispose")
    XCTAssertTrue(channel.invocations.isEmpty, "registering alone reports no tap")
  }
}
