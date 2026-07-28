import Flutter
import XCTest

@testable import flureadium

/// Replies to method-channel invocations with a caller-supplied value so the
/// channel-backed `CarPlayContentBridge` can be exercised without a Flutter
/// engine. The reply closure is consulted per decoded call and its result is
/// encoded as a success envelope — exactly what a real Dart handler returns.
/// Mirrors the plugin's `MockBinaryMessenger` (EventStreamHandlerTests) but adds
/// the reply path the bridge's request/response methods need.
private final class ReplyingMessenger: NSObject, FlutterBinaryMessenger {
  /// Computes the reply value for a decoded call; the value is encoded back.
  var reply: (FlutterMethodCall) -> Any? = { _ in nil }
  private(set) var calls: [FlutterMethodCall] = []
  private let codec = FlutterStandardMethodCodec.sharedInstance()

  /// Fire-and-forget invoke (e.g. `play`): record it, no reply expected.
  func send(onChannel channel: String, message: Data?) {
    guard let message = message else { return }
    calls.append(codec.decodeMethodCall(message))
  }

  /// Request/response invoke: decode, record, and encode the reply value.
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    guard let message = message else { callback?(nil); return }
    let call = codec.decodeMethodCall(message)
    calls.append(call)
    callback?(codec.encodeSuccessEnvelope(reply(call)))
  }

  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    FlutterBinaryMessengerConnection(0)
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

/// Covers `CarPlayContentBridge`'s channel decode-and-retry: list replies decode
/// to typed values and drop malformed rows, `children` forwards its node id,
/// `strings` decodes a map (nil on a non-map), `select` fires the play call, and
/// a not-yet-ready non-array reply is retried and then recovers — or yields an
/// empty list once the retry budget is spent. The iOS twin of the Android
/// `MethodChannelCarContentSourceTest`.
final class CarPlayContentBridgeTests: XCTestCase {

  private var messenger: ReplyingMessenger!
  private var bridge: CarPlayContentBridge!

  override func setUp() {
    super.setUp()
    messenger = ReplyingMessenger()
    bridge = CarPlayContentBridge(binaryMessenger: messenger)
  }

  override func tearDown() {
    bridge = nil
    messenger = nil
    super.tearDown()
  }

  private func tabMap(_ id: String, _ title: String) -> [String: Any] {
    ["id": id, "title": title]
  }

  private func nodeMap(_ id: String, kind: String = "audiobook") -> [String: Any] {
    ["id": id, "title": "T", "kind": kind, "isPlayable": true]
  }

  func testRootTabsDecodesTabsFromListReply() {
    messenger.reply = { call in
      call.method == "rootTabs" ? [self.tabMap("continue", "Continue"), self.tabMap("library", "Library")] : nil
    }
    let exp = expectation(description: "rootTabs")
    var tabs: [CarTab] = []
    bridge.rootTabs { tabs = $0; exp.fulfill() }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(tabs.map { $0.id }, ["continue", "library"])
  }

  func testChildrenForwardsNodeIdAndDecodesNodes() {
    messenger.reply = { call in
      call.method == "children" ? [self.nodeMap("book:dune")] : nil
    }
    let exp = expectation(description: "children")
    var nodes: [CarBrowseNode] = []
    bridge.children(of: "genre:sci-fi") { nodes = $0; exp.fulfill() }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(nodes.map { $0.id }, ["book:dune"])
    let args = messenger.calls.first?.arguments as? [String: Any]
    XCTAssertEqual(args?["nodeId"] as? String, "genre:sci-fi")
  }

  func testChildrenDropsMalformedRows() {
    messenger.reply = { _ in
      [self.nodeMap("book:ok"), ["title": "no id", "kind": "audiobook"]]
    }
    let exp = expectation(description: "children")
    var nodes: [CarBrowseNode] = []
    bridge.children(of: "x") { nodes = $0; exp.fulfill() }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(nodes.map { $0.id }, ["book:ok"])
  }

  func testSearchForwardsQueryAndDecodesNodes() {
    messenger.reply = { call in
      call.method == "search" ? [self.nodeMap("book:weir")] : nil
    }
    let exp = expectation(description: "search")
    var nodes: [CarBrowseNode] = []
    bridge.search("weir") { nodes = $0; exp.fulfill() }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(nodes.map { $0.id }, ["book:weir"])
    let args = messenger.calls.first?.arguments as? [String: Any]
    XCTAssertEqual(args?["query"] as? String, "weir")
  }

  func testStringsDecodesFromMapReply() {
    messenger.reply = { call in
      call.method == "strings"
        ? [
          "emptyRootTitle": "Nothing to play yet", "emptyRootSubtitle": "Add books to see them here",
          "voiceUnavailable": "No voice", "offline": "Offline",
        ]
        : nil
    }
    let exp = expectation(description: "strings")
    var strings: CarContentStrings?
    bridge.strings { strings = $0; exp.fulfill() }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(strings?.emptyRootTitle, "Nothing to play yet")
  }

  func testStringsIsNilWhenReplyIsNotAMap() {
    messenger.reply = { _ in "not a map" }
    let exp = expectation(description: "strings nil")
    var strings: CarContentStrings? = CarContentStrings(map: [
      "emptyRootTitle": "s", "emptyRootSubtitle": "s", "voiceUnavailable": "s", "offline": "s",
    ])
    XCTAssertNotNil(strings)
    bridge.strings { strings = $0; exp.fulfill() }
    wait(for: [exp], timeout: 2)
    XCTAssertNil(strings)
  }

  func testSelectFiresPlayWithNodeId() {
    bridge.select(nodeId: "book:42")
    XCTAssertEqual(messenger.calls.first?.method, "play")
    let args = messenger.calls.first?.arguments as? [String: Any]
    XCTAssertEqual(args?["nodeId"] as? String, "book:42")
  }

  func testRootTabsRetriesUntilAnArrayArrives() {
    var attempts = 0
    messenger.reply = { call in
      guard call.method == "rootTabs" else { return nil }
      attempts += 1
      // First two replies are non-arrays ("handler not ready"); third recovers.
      return attempts < 3 ? nil : [self.tabMap("continue", "Continue")]
    }
    let exp = expectation(description: "recovers")
    var tabs: [CarTab] = []
    bridge.rootTabs { tabs = $0; exp.fulfill() }
    wait(for: [exp], timeout: 4)
    XCTAssertEqual(tabs.map { $0.id }, ["continue"])
    XCTAssertEqual(attempts, 3)
  }

  func testRootTabsGivesUpWithEmptyAfterExhaustingRetries() {
    messenger.reply = { _ in nil }  // never an array
    let exp = expectation(description: "gives up")
    var count = -1
    bridge.rootTabs { count = $0.count; exp.fulfill() }
    wait(for: [exp], timeout: 8)  // 20 retries * 0.15s ≈ 3s
    XCTAssertEqual(count, 0)
  }
}
