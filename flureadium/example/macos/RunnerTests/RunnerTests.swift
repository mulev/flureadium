import Cocoa
import FlutterMacOS
import XCTest


@testable import flureadium

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

/// The ceiling every positive wait in this target uses — a hang guard, not a
/// sleep. Full reasoning: `example/ios/RunnerTests/RunnerTests.swift`.
let asyncTimeout: TimeInterval = 60

class RunnerTests: XCTestCase {

  func testGetPlatformVersion() {
    let plugin = FlureadiumPlugin()

    let call = FlutterMethodCall(methodName: "getPlatformVersion", arguments: [])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertEqual(result as! String,
                     "macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: asyncTimeout)
  }

}
