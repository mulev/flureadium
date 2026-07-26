import XCTest

@testable import flureadium

/// Guards the Swift decoders against the Dart `toMap` keys. If either side
/// renames a key, these decode assertions fail before the mismatch reaches a
/// head unit as a dropped row.
final class CarContentModelsTests: XCTestCase {

  func testNodeDecodesEveryField() {
    let node = CarBrowseNode(map: [
      "id": "book:42",
      "title": "Project Hail Mary",
      "subtitle": "Andy Weir",
      "artworkPath": "/tmp/cover.jpg",
      "kind": "audiobook",
      "isPlayable": true,
      "progress": 0.62,
      "isNowPlaying": true,
    ])
    XCTAssertEqual(node?.id, "book:42")
    XCTAssertEqual(node?.title, "Project Hail Mary")
    XCTAssertEqual(node?.subtitle, "Andy Weir")
    XCTAssertEqual(node?.artworkPath, "/tmp/cover.jpg")
    XCTAssertEqual(node?.kind, .audiobook)
    XCTAssertEqual(node?.isPlayable, true)
    XCTAssertEqual(node?.progress ?? 0, 0.62, accuracy: 0.0001)
    XCTAssertEqual(node?.isNowPlaying, true)
  }

  func testNodeAppliesDefaultsForAbsentOptionals() {
    let node = CarBrowseNode(map: ["id": "genre:sci-fi", "title": "Sci-Fi", "kind": "container"])
    XCTAssertEqual(node?.kind, .container)
    XCTAssertFalse(node?.isPlayable ?? true)
    XCTAssertNil(node?.progress)
    XCTAssertFalse(node?.isNowPlaying ?? true)
    XCTAssertNil(node?.subtitle)
  }

  func testNodeRejectsMissingRequiredFields() {
    XCTAssertNil(CarBrowseNode(map: ["title": "no id", "kind": "audiobook"]))
    XCTAssertNil(CarBrowseNode(map: ["id": "x", "kind": "audiobook"]))
    XCTAssertNil(CarBrowseNode(map: ["id": "x", "title": "y", "kind": "not-a-kind"]))
    XCTAssertNil(CarBrowseNode(map: ["id": "", "title": "y", "kind": "audiobook"]))
  }

  func testTabDecodesAndRejectsBlank() {
    let tab = CarTab(map: ["id": "library", "title": "Library", "iconName": "books"])
    XCTAssertEqual(tab?.id, "library")
    XCTAssertEqual(tab?.title, "Library")
    XCTAssertEqual(tab?.iconName, "books")
    XCTAssertNil(CarTab(map: ["id": "", "title": "Library"]))
    XCTAssertNil(CarTab(map: ["id": "library"]))
  }

  func testStringsDecodeAndRejectMissingOrBlank() {
    let strings = CarContentStrings(map: [
      "emptyRootTitle": "Nothing to play yet",
      "emptyRootSubtitle": "Add books to see them here",
      "voiceUnavailable": "Voice not installed",
      "offline": "Needs a connection",
    ])
    XCTAssertEqual(strings?.emptyRootTitle, "Nothing to play yet")
    XCTAssertEqual(strings?.offline, "Needs a connection")

    XCTAssertNil(
      CarContentStrings(map: [
        "emptyRootTitle": "",
        "emptyRootSubtitle": "b",
        "voiceUnavailable": "c",
        "offline": "d",
      ]))
    XCTAssertNil(
      CarContentStrings(map: [
        "emptyRootTitle": "a",
        "emptyRootSubtitle": "b",
        "voiceUnavailable": "c",
      ]))
  }
}
