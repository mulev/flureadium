//
//  FlutterNavigationConfigTests.swift
//  RunnerTests
//
//  Decoding the navigation config dictionary Dart sends over
//  setNavigationConfig: typed values only, absent keys stay nil.
//

import XCTest
@testable import flureadium

final class FlutterNavigationConfigTests: XCTestCase {

    func testInitFromMapAllFields() {
        let map: [String: Any] = [
            "enableEdgeTapNavigation": true,
            "enableSwipeNavigation": false,
            "edgeTapAreaPoints": 80.0,
            "disableDoubleTapZoom": true,
            "disableTextSelection": true,
            "disableDragGestures": false,
            "disableDoubleTapTextSelection": true,
        ]
        let config = FlutterNavigationConfig(fromMap: map)
        XCTAssertEqual(config.enableEdgeTapNavigation, true)
        XCTAssertEqual(config.enableSwipeNavigation, false)
        XCTAssertEqual(config.edgeTapAreaPoints, 80.0)
        XCTAssertEqual(config.disableDoubleTapZoom, true)
        XCTAssertEqual(config.disableTextSelection, true)
        XCTAssertEqual(config.disableDragGestures, false)
        XCTAssertEqual(config.disableDoubleTapTextSelection, true)
    }

    func testInitFromNilMap() {
        let config = FlutterNavigationConfig(fromMap: nil)
        XCTAssertNil(config.enableEdgeTapNavigation)
        XCTAssertNil(config.enableSwipeNavigation)
        XCTAssertNil(config.edgeTapAreaPoints)
        XCTAssertNil(config.disableDoubleTapZoom)
        XCTAssertNil(config.disableTextSelection)
        XCTAssertNil(config.disableDragGestures)
        XCTAssertNil(config.disableDoubleTapTextSelection)
    }

    func testInitFromEmptyMap() {
        let config = FlutterNavigationConfig(fromMap: [:])
        XCTAssertNil(config.enableEdgeTapNavigation)
        XCTAssertNil(config.edgeTapAreaPoints)
    }

    func testInitFromPartialMap() {
        let map: [String: Any] = ["enableEdgeTapNavigation": true]
        let config = FlutterNavigationConfig(fromMap: map)
        XCTAssertEqual(config.enableEdgeTapNavigation, true)
        XCTAssertNil(config.enableSwipeNavigation)
        XCTAssertNil(config.edgeTapAreaPoints)
    }

    func testBooleansAreTypedNotStrings() {
        // Values arrive from Dart as Bool, not String
        let map: [String: Any] = [
            "enableEdgeTapNavigation": true,
            "disableDoubleTapZoom": false,
        ]
        let config = FlutterNavigationConfig(fromMap: map)
        XCTAssertEqual(config.enableEdgeTapNavigation, true)
        XCTAssertEqual(config.disableDoubleTapZoom, false)
    }

    func testStringValuesNotParsedAsBools() {
        // String "true" must not be coerced to Bool true (as? Bool -> nil)
        let map: [String: Any] = ["enableEdgeTapNavigation": "true"]
        let config = FlutterNavigationConfig(fromMap: map)
        XCTAssertNil(config.enableEdgeTapNavigation)
    }
}
