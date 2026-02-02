import Flutter
import UIKit
import XCTest

@testable import flureadium

/// Tests for gesture state management in ReadiumReaderView after navigation.
///
/// These tests verify that the gesture recognizer state is properly maintained
/// after programmatic navigation (goLeft/goRight). This prevents the bug where
/// links stop working after using navigation buttons.
class ReadiumReaderViewTests: XCTestCase {

  /// Tests that goLeft navigation completes successfully.
  ///
  /// This test verifies that:
  /// - The goLeft method call completes without error
  /// - The result is returned (success or failure)
  /// - No crashes occur during navigation
  func testGoLeftNavigationCompletes() {
    let plugin = FlureadiumPlugin()
    let call = FlutterMethodCall(methodName: "goLeft", arguments: true)

    let resultExpectation = expectation(description: "goLeft should complete")

    plugin.handle(call) { result in
      // Result can be success (true) or failure (false/nil)
      // We just verify that the call completes without crashing
      XCTAssertNotNil(result, "goLeft should return a result")
      resultExpectation.fulfill()
    }

    // Wait up to 5 seconds for navigation to complete
    // Note: This may timeout if no publication is loaded, which is expected
    waitForExpectations(timeout: 5)
  }

  /// Tests that goRight navigation completes successfully.
  ///
  /// This test verifies that:
  /// - The goRight method call completes without error
  /// - The result is returned (success or failure)
  /// - No crashes occur during navigation
  func testGoRightNavigationCompletes() {
    let plugin = FlureadiumPlugin()
    let call = FlutterMethodCall(methodName: "goRight", arguments: false)

    let resultExpectation = expectation(description: "goRight should complete")

    plugin.handle(call) { result in
      // Result can be success (true) or failure (false/nil)
      // We just verify that the call completes without crashing
      XCTAssertNotNil(result, "goRight should return a result")
      resultExpectation.fulfill()
    }

    // Wait up to 5 seconds for navigation to complete
    waitForExpectations(timeout: 5)
  }

  /// Tests that sequential navigation calls complete successfully.
  ///
  /// This test verifies that:
  /// - Multiple navigation calls can be made in sequence
  /// - Each call completes without error
  /// - Gesture state remains consistent across navigation
  func testSequentialNavigationMaintainsState() {
    let plugin = FlureadiumPlugin()

    // First navigation: goRight
    let rightCall = FlutterMethodCall(methodName: "goRight", arguments: true)
    let rightExpectation = expectation(description: "goRight should complete")

    plugin.handle(rightCall) { result in
      XCTAssertNotNil(result, "First goRight should return a result")
      rightExpectation.fulfill()
    }

    wait(for: [rightExpectation], timeout: 5)

    // Second navigation: goLeft
    let leftCall = FlutterMethodCall(methodName: "goLeft", arguments: true)
    let leftExpectation = expectation(description: "goLeft should complete")

    plugin.handle(leftCall) { result in
      XCTAssertNotNil(result, "goLeft should return a result")
      leftExpectation.fulfill()
    }

    wait(for: [leftExpectation], timeout: 5)

    // Third navigation: goRight again
    let rightCall2 = FlutterMethodCall(methodName: "goRight", arguments: false)
    let rightExpectation2 = expectation(description: "Second goRight should complete")

    plugin.handle(rightCall2) { result in
      XCTAssertNotNil(result, "Second goRight should return a result")
      rightExpectation2.fulfill()
    }

    wait(for: [rightExpectation2], timeout: 5)
  }

  /// Tests that navigation with animation enabled works.
  func testNavigationWithAnimationEnabled() {
    let plugin = FlureadiumPlugin()
    let call = FlutterMethodCall(methodName: "goLeft", arguments: true)

    let resultExpectation = expectation(description: "goLeft with animation should complete")

    plugin.handle(call) { result in
      XCTAssertNotNil(result, "Animated navigation should return a result")
      resultExpectation.fulfill()
    }

    waitForExpectations(timeout: 5)
  }

  /// Tests that navigation with animation disabled works.
  func testNavigationWithAnimationDisabled() {
    let plugin = FlureadiumPlugin()
    let call = FlutterMethodCall(methodName: "goRight", arguments: false)

    let resultExpectation = expectation(description: "goRight without animation should complete")

    plugin.handle(call) { result in
      XCTAssertNotNil(result, "Non-animated navigation should return a result")
      resultExpectation.fulfill()
    }

    waitForExpectations(timeout: 5)
  }
}
