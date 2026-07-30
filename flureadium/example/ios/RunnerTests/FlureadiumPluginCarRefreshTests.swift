import Flutter
import XCTest

@testable import flureadium

/// Verifies the plugin translates the `refreshCarContent` channel call into the
/// process-wide notification the CarPlay scene observes, and completes the call.
final class FlureadiumPluginCarRefreshTests: XCTestCase {

  func testRefreshCarContentPostsRefreshNotificationOnceAndReturnsNil() {
    let plugin = FlureadiumPlugin()
    let call = FlutterMethodCall(methodName: "refreshCarContent", arguments: nil)

    let posted = expectation(forNotification: .flureadiumCarContentShouldRefresh, object: nil)
    posted.expectedFulfillmentCount = 1
    posted.assertForOverFulfill = true

    var resultCalls: [Any?] = []
    plugin.handle(call) { resultCalls.append($0) }

    wait(for: [posted], timeout: 1.0)
    XCTAssertEqual(resultCalls.count, 1, "the channel call completes exactly once")
    XCTAssertNil(resultCalls.first ?? "non-nil", "refreshCarContent completes the call with nil")
  }
}
