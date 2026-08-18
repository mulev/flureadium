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

  /// A locator in the shape Dart sends inside a decoration — `Locator.toJson()`
  /// as the method channel delivers it.
  private func locatorMap(_ href: String = "ch1.html") -> [String: Any] {
    Locator(href: URL(string: href)!, mediaType: .html).json
  }

  /// A decoration in the canonical wire shape `Decoration(fromDartMap:)` expects.
  private func decorationMap(id: String = "d1", href: String = "ch1.html") -> [String: Any] {
    ["id": id, "locator": locatorMap(href), "style": ["style": "highlight", "tint": "#FF9800"]]
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

  /// Decodes a one-decoration `applyDecorations` call and asserts the decoder
  /// reported the failure as nil decorations while keeping the raw map, which the
  /// view needs for the `FlutterError` it answers with.
  private func assertDecorationRejected(
    _ map: [String: Any], file: StaticString = #filePath, line: UInt = #line
  ) {
    guard case let .applyDecorations(_, decorations, raw) = decode(
      "applyDecorations", ["user-highlight", [map]])
    else { return XCTFail("applyDecorations did not decode", file: file, line: line) }

    XCTAssertNil(decorations, file: file, line: line)
    XCTAssertEqual(raw.count, 1, file: file, line: line)
  }

  func testApplyDecorationsDecodesGroupAndDecorations() {
    let payload = [decorationMap(id: "first"), decorationMap(id: "second", href: "ch2.html")]

    guard case let .applyDecorations(group, decorations, raw) = decode(
      "applyDecorations", ["user-highlight", payload])
    else { return XCTFail("applyDecorations did not decode") }

    XCTAssertEqual(group, "user-highlight")
    XCTAssertEqual(decorations?.map(\.id), ["first", "second"])
    XCTAssertEqual(decorations?.map(\.locator.href.string), ["ch1.html", "ch2.html"])
    XCTAssertEqual(decorations?.first?.style.id, Decoration.Style.Id(rawValue: "highlight"))
    XCTAssertEqual(raw.map { $0["id"] as? String }, ["first", "second"])
  }

  func testApplyDecorationsReturnsNilDecorationsForMissingLocator() {
    var map = decorationMap()
    map["locator"] = nil

    assertDecorationRejected(map)
  }

  func testApplyDecorationsReturnsNilDecorationsForMissingId() {
    var map = decorationMap()
    map["id"] = nil

    assertDecorationRejected(map)
  }

  func testApplyDecorationsReturnsNilDecorationsForMissingStyle() {
    var map = decorationMap()
    map["style"] = nil

    assertDecorationRejected(map)
  }

  func testApplyDecorationsReturnsNilDecorationsForMissingTint() {
    // The tint lives one level down, inside `style` — reading it off the top
    // level is the mistake the old flat payload shape encoded.
    var map = decorationMap()
    map["style"] = ["style": "highlight"]

    assertDecorationRejected(map)
  }

  func testApplyDecorationsReturnsNilDecorationsForUnparseableLocator() {
    var map = decorationMap()
    map["locator"] = ["nope": true]

    assertDecorationRejected(map)
  }

  func testApplyDecorationsReturnsNilDecorationsForNonHexTint() {
    var map = decorationMap()
    map["style"] = ["style": "highlight", "tint": "rebeccapurple"]

    assertDecorationRejected(map)
  }

  func testApplyDecorationsReturnsNilDecorationsForLocatorSentAsString() {
    // The pre-Phase-2 wire format put the locator in as a JSON string. Readium's
    // `Locator(json:)` rejects a non-dictionary, so the decode must report nil —
    // not trap, and not silently build a decoration at the wrong position.
    var map = decorationMap()
    map["locator"] = locatorJson()

    assertDecorationRejected(map)
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
