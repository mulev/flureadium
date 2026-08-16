import ReadiumNavigator
import UIKit
import XCTest

@testable import flureadium

final class EpubNavigatorConfigurationTests: XCTestCase {

    func testEpubEditingActionsContainsCopy() {
        XCTAssertTrue(
            makeEpubNavigatorConfiguration(preferences: nil).editingActions.contains(.copy),
            "editingActions must include .copy so users can copy selected text"
        )
    }

    func testEpubEditingActionsContainsLookup() {
        XCTAssertTrue(
            makeEpubNavigatorConfiguration(preferences: nil).editingActions.contains(.lookup),
            "editingActions must retain .lookup (regression)"
        )
    }

    func testEpubEditingActionsContainsTranslate() {
        XCTAssertTrue(
            makeEpubNavigatorConfiguration(preferences: nil).editingActions.contains(.translate),
            "editingActions must retain .translate (regression)"
        )
    }

    func testEpubEditingActionsCountIsThree() {
        XCTAssertEqual(
            makeEpubNavigatorConfiguration(preferences: nil).editingActions.count,
            3,
            "editingActions must have exactly 3 items: copy, lookup, translate"
        )
    }

    func testContentInsetIsZeroForBothSizeClasses() {
        let contentInset = makeEpubNavigatorConfiguration(preferences: nil).contentInset

        XCTAssertEqual(contentInset[.compact]?.top, 0, "Readium's undocumented top padding must stay off")
        XCTAssertEqual(contentInset[.compact]?.bottom, 0)
        XCTAssertEqual(contentInset[.regular]?.top, 0)
        XCTAssertEqual(contentInset[.regular]?.bottom, 0, "margins are the Flutter side's job")
    }

    func testPreloadCountsArePreviousTwoNextFour() {
        let config = makeEpubNavigatorConfiguration(preferences: nil)

        XCTAssertEqual(config.preloadPreviousPositionCount, 2)
        XCTAssertEqual(config.preloadNextPositionCount, 4)
    }

    func testDecorationTemplatesAreInstalled() {
        XCTAssertFalse(
            makeEpubNavigatorConfiguration(preferences: nil).decorationTemplates.isEmpty,
            "applyDecorations needs a template to render highlights with"
        )
    }

    func testPreferencesArePassedThrough() {
        var preferences = EPUBPreferences()
        preferences.scroll = true

        XCTAssertEqual(
            makeEpubNavigatorConfiguration(preferences: preferences).preferences.scroll,
            true,
            "the host's initial preferences must reach Readium"
        )
    }

    func testNilPreferencesLeavesReadiumDefaults() {
        XCTAssertEqual(
            makeEpubNavigatorConfiguration(preferences: nil).preferences,
            EPUBNavigatorViewController.Configuration().preferences,
            "no host preferences means Readium keeps its own defaults"
        )
    }
}
