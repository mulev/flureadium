//
//  EpubReaderCommandTests.swift
//  RunnerTests
//
//  Decoding the EPUB reader's method-channel calls. Argument order, the optional
//  trailing flags and the nil-to-"null" default are the parts of the channel a
//  refactor breaks silently, so every command is decoded from a real
//  `FlutterMethodCall` and asserted field by field.
//

import Flutter
import ReadiumNavigator
import ReadiumShared
import XCTest

@testable import flureadium

final class EpubReaderCommandTests: XCTestCase {

  // MARK: - Fixtures

  /// A locator JSON string Readium accepts, built by round-tripping a `Locator`.
  private func locatorJson(_ href: String = "ch1.html", progression: Double? = nil) -> String {
    Locator(href: URL(string: href)!, mediaType: .html, locations: .init(progression: progression))
      .jsonString!
  }

  /// A decoration JSON string in the shape `Decoration(fromJson:)` expects.
  private func decorationJson(id: String = "d1", href: String = "ch1.html") -> String {
    let map = ["id": id, "locator": locatorJson(href), "style": "highlight", "tint": "#FF9800"]
    return String(data: try! JSONSerialization.data(withJSONObject: map), encoding: .utf8)!
  }

  private func decode(_ method: String, _ arguments: Any? = nil) -> EpubReaderCommand? {
    EpubReaderCommand(FlutterMethodCall(methodName: method, arguments: arguments))
  }

  // MARK: - go

  func testGoDecodesLocatorAnimatedAndAudiobookFlag() {
    let json = locatorJson("ch2.html", progression: 0.25)

    guard case let .go(locator, animated, isAudioBookWithText) = decode("go", [json, true, true])
    else { return XCTFail("go did not decode") }

    XCTAssertEqual(locator.href.string, "ch2.html")
    XCTAssertEqual(locator.locations.progression, 0.25)
    XCTAssertTrue(animated)
    XCTAssertTrue(isAudioBookWithText)
  }

  func testGoDefaultsAudiobookFlagToFalseWhenAbsent() {
    // The three-element array Dart sends can arrive with a nil third element;
    // the decoder must read it as false rather than crash or flip the flag.
    guard case let .go(_, animated, isAudioBookWithText) = decode("go", [locatorJson(), false, nil])
    else { return XCTFail("go did not decode") }

    XCTAssertFalse(animated)
    XCTAssertFalse(isAudioBookWithText)
  }

  func testGoLeftAndGoRightDecodeTheAnimatedFlag() {
    guard case let .goLeft(animatedLeft) = decode("goLeft", true),
      case let .goRight(animatedRight) = decode("goRight", false)
    else { return XCTFail("goLeft/goRight did not decode") }

    XCTAssertTrue(animatedLeft)
    XCTAssertFalse(animatedRight)
  }

  // MARK: - setLocation

  func testSetLocationDecodesLocatorAndFlag() {
    let json = locatorJson("ch3.html", progression: 0.5)

    guard case let .setLocation(locator, isAudioBookWithText) = decode("setLocation", [json, true])
    else { return XCTFail("setLocation did not decode") }

    XCTAssertEqual(locator.href.string, "ch3.html")
    XCTAssertEqual(locator.locations.progression, 0.5)
    XCTAssertTrue(isAudioBookWithText)
  }

  func testSetLocationDefaultsFlagToFalse() {
    // NSNull is what a Dart `null` in the argument list becomes.
    guard case let .setLocation(_, isAudioBookWithText) = decode(
      "setLocation", [locatorJson(), NSNull()])
    else { return XCTFail("setLocation did not decode") }

    XCTAssertFalse(isAudioBookWithText)
  }

  // MARK: - getLocatorFragments

  func testLocatorFragmentsDefaultsToNullStringWhenArgumentIsNil() {
    guard case let .locatorFragments(json) = decode("getLocatorFragments", nil)
    else { return XCTFail("getLocatorFragments did not decode") }

    XCTAssertEqual(json, "null")
  }

  func testLocatorFragmentsPassesLocatorJsonThrough() {
    let json = locatorJson("ch4.html")

    guard case let .locatorFragments(passed) = decode("getLocatorFragments", json)
    else { return XCTFail("getLocatorFragments did not decode") }

    XCTAssertEqual(passed, json)
  }

  // MARK: - isLocatorVisible

  func testIsLocatorVisibleCarriesBothParsedLocatorAndRawJson() {
    // The view compares the parsed href, then hands the raw string to
    // JavaScript, so the string must survive byte-identical.
    let json = locatorJson("ch5.html", progression: 0.75)

    guard case let .isLocatorVisible(locator, raw) = decode("isLocatorVisible", json)
    else { return XCTFail("isLocatorVisible did not decode") }

    XCTAssertEqual(locator.href.string, "ch5.html")
    XCTAssertEqual(raw, json)
  }

  // MARK: - setPreferences / setNavigationConfig

  func testSetPreferencesDecodesEpubPreferences() {
    guard case let .setPreferences(preferences) = decode(
      "setPreferences", ["verticalScroll": "true", "fontSize": "1.5"])
    else { return XCTFail("setPreferences did not decode") }

    XCTAssertEqual(preferences.scroll, true)
    XCTAssertEqual(preferences.fontSize, 1.5)
  }

  func testSetNavigationConfigDecodesEveryField() {
    let map: [String: Any] = [
      "enableEdgeTapNavigation": true,
      "enableSwipeNavigation": false,
      "edgeTapAreaPoints": 72.0,
      "disableDoubleTapZoom": true,
      "disableTextSelection": false,
      "disableDragGestures": true,
      "disableDoubleTapTextSelection": false,
    ]

    guard case let .setNavigationConfig(config) = decode("setNavigationConfig", map)
    else { return XCTFail("setNavigationConfig did not decode") }

    XCTAssertEqual(config.enableEdgeTapNavigation, true)
    XCTAssertEqual(config.enableSwipeNavigation, false)
    XCTAssertEqual(config.edgeTapAreaPoints, 72.0)
    XCTAssertEqual(config.disableDoubleTapZoom, true)
    XCTAssertEqual(config.disableTextSelection, false)
    XCTAssertEqual(config.disableDragGestures, true)
    XCTAssertEqual(config.disableDoubleTapTextSelection, false)
  }

  // MARK: - applyDecorations

  func testApplyDecorationsDecodesGroupAndDecorations() {
    let json = [decorationJson(id: "first"), decorationJson(id: "second", href: "ch2.html")]

    guard case let .applyDecorations(group, decorations, raw) = decode(
      "applyDecorations", ["user-highlight", json])
    else { return XCTFail("applyDecorations did not decode") }

    XCTAssertEqual(group, "user-highlight")
    XCTAssertEqual(decorations?.map(\.id), ["first", "second"])
    XCTAssertEqual(decorations?.map(\.locator.href.string), ["ch1.html", "ch2.html"])
    XCTAssertEqual(raw, json)
  }

  func testApplyDecorationsReturnsNilDecorationsForMalformedJson() {
    // The view answers a FlutterError for this case, so the decoder reports the
    // failure as nil decorations while keeping the raw strings for the message.
    let json = ["{\"id\":\"no-locator\"}"]

    guard case let .applyDecorations(group, decorations, raw) = decode(
      "applyDecorations", ["user-highlight", json])
    else { return XCTFail("applyDecorations did not decode") }

    XCTAssertEqual(group, "user-highlight")
    XCTAssertNil(decorations)
    XCTAssertEqual(raw, json)
  }

  // MARK: - Argument-free commands

  func testCurrentLocatorIsReaderReadyAndDisposeDecodeWithoutArguments() {
    // Dart sends an empty list for getCurrentLocator and nothing for the others.
    guard case .currentLocator = decode("getCurrentLocator", []),
      case .isReaderReady = decode("isReaderReady", nil),
      case .dispose = decode("dispose", nil)
    else { return XCTFail("argument-free commands did not decode") }
  }

  // MARK: - Unknown method

  func testUnknownMethodDecodesToNil() {
    XCTAssertNil(decode("thisIsNotAReaderCommand", nil))
    XCTAssertNil(decode("play", true))
  }
}
