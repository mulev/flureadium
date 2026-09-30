import XCTest
import Flutter
import ReadiumShared
@testable import flureadium

final class FlureadiumPluginGoToLocatorTests: XCTestCase {

  override func setUp() {
    super.setUp()
    currentPublication = nil
    currentReaderView = nil
    currentImageReaderView = nil
    currentPdfReaderView = nil
  }

  override func tearDown() {
    currentPublication = nil
    currentReaderView = nil
    currentImageReaderView = nil
    currentPdfReaderView = nil
    super.tearDown()
  }

  func testGoToLocatorReturnsErrorWhenArgsNil() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "goToLocator", arguments: nil)
    plugin.handle(call) { response in
      XCTAssertNotNil(response as? FlutterError,
                      "goToLocator with nil args should return FlutterError")
      let error = response as! FlutterError
      XCTAssertEqual(error.code, "InvalidArgument")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  func testGoToLocatorReturnsErrorWhenLocatorJsonInvalid() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let badArgs: [Any?] = [["this": "is not a valid locator"]]
    let call = FlutterMethodCall(methodName: "goToLocator", arguments: badArgs)
    plugin.handle(call) { response in
      XCTAssertNotNil(response as? FlutterError,
                      "goToLocator with malformed locator JSON should return FlutterError")
      let error = response as! FlutterError
      XCTAssertEqual(error.code, "InvalidArgument")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  func testGoToLocatorReturnsFalseWhenNoNavigatorOrViewRegistered() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let locatorJson: [String: Any] = [
      "href": "page1.jpg",
      "type": "image/jpeg",
    ]
    let call = FlutterMethodCall(methodName: "goToLocator", arguments: [locatorJson])
    plugin.handle(call) { response in
      XCTAssertEqual(response as? Bool, false,
                     "goToLocator should return false when nothing is registered")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }
}
