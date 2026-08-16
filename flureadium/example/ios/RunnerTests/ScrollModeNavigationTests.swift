//
//  ScrollModeNavigationTests.swift
//  RunnerTests
//
//  Unit tests for the scroll-mode position memory declared in
//  SpineItemPositionMemory.swift: the SpineItemPositionMemory value type and
//  its free helpers strippedHref(_:) and isBackwardNavigation(from:to:in:).
//  These are internal, exposed via @testable import.
//

import XCTest
import ReadiumShared
@testable import flureadium

final class ScrollModeNavigationTests: XCTestCase {

    // MARK: - Fixtures

    private func makeLink(_ href: String) -> Link {
        Link(href: href)
    }

    private var threeLinks: [Link] {
        [makeLink("ch1.html"), makeLink("ch2.html"), makeLink("ch3.html")]
    }

    // MARK: - strippedHref

    func testStrippedHref_noFragment_unchanged() {
        XCTAssertEqual(strippedHref("ch1.html"), "ch1.html")
    }

    func testStrippedHref_removesFragment() {
        XCTAssertEqual(strippedHref("ch1.html#section-2"), "ch1.html")
    }

    func testStrippedHref_removesQuery() {
        XCTAssertEqual(strippedHref("ch1.html?page=3"), "ch1.html")
    }

    func testStrippedHref_removesFragmentAndQuery() {
        // Fragment wins: components(separatedBy: "#") splits first
        XCTAssertEqual(strippedHref("ch1.html#anchor?query=1"), "ch1.html")
    }

    func testStrippedHref_emptyString() {
        XCTAssertEqual(strippedHref(""), "")
    }

    // MARK: - isBackwardNavigation(from:to:in:)

    func testIsBackwardNavigation_emptyReadingOrder_returnsFalse() {
        XCTAssertFalse(isBackwardNavigation(from: "ch2.html", to: "ch1.html", in: []))
    }

    func testIsBackwardNavigation_oldHrefNotFound_returnsFalse() {
        XCTAssertFalse(isBackwardNavigation(from: "unknown.html", to: "ch1.html", in: threeLinks))
    }

    func testIsBackwardNavigation_newHrefNotFound_returnsFalse() {
        XCTAssertFalse(isBackwardNavigation(from: "ch2.html", to: "unknown.html", in: threeLinks))
    }

    func testIsBackwardNavigation_backwardNav_returnsTrue() {
        // ch3 → ch2: newIdx(1) < oldIdx(2) → true
        XCTAssertTrue(isBackwardNavigation(from: "ch3.html", to: "ch2.html", in: threeLinks))
    }

    func testIsBackwardNavigation_forwardNav_returnsFalse() {
        // ch1 → ch2: newIdx(1) > oldIdx(0) → false
        XCTAssertFalse(isBackwardNavigation(from: "ch1.html", to: "ch2.html", in: threeLinks))
    }

    func testIsBackwardNavigation_sameItem_returnsFalse() {
        XCTAssertFalse(isBackwardNavigation(from: "ch2.html", to: "ch2.html", in: threeLinks))
    }

    func testIsBackwardNavigation_fragmentsStrippedBeforeComparison() {
        // ch3.html#end → ch1.html#intro: both stripped, newIdx(0) < oldIdx(2) → true
        XCTAssertTrue(isBackwardNavigation(from: "ch3.html#end", to: "ch1.html#intro", in: threeLinks))
    }
}

/// The scroll-mode restore decision: which stored position, if any, the reader
/// should navigate back to when the spine item changes.
final class SpineItemPositionMemoryTests: XCTestCase {

    // MARK: - Fixtures

    private var threeLinks: [Link] {
        [Link(href: "ch1.html"), Link(href: "ch2.html"), Link(href: "ch3.html")]
    }

    private func locator(_ href: String, _ progression: Double? = nil) -> Locator {
        Locator(
            href: URL(string: href)!,
            mediaType: .html,
            locations: .init(progression: progression))
    }

    /// `record` in scroll mode against the three-chapter reading order.
    @discardableResult
    private func moveTo(
        _ memory: inout SpineItemPositionMemory,
        _ href: String,
        _ progression: Double? = nil,
        isScrollMode: Bool = true
    ) -> Locator? {
        memory.record(
            locator(href, progression), in: threeLinks, isScrollMode: isScrollMode)
    }

    // MARK: - record

    func testFirstLocationRestoresNothing() {
        var memory = SpineItemPositionMemory()
        XCTAssertNil(moveTo(&memory, "ch1.html", 0.5))
    }

    func testForwardChapterChangeRestoresNothing() {
        var memory = SpineItemPositionMemory()
        // Visit ch2 first so it has a stored position, then approach it forwards.
        moveTo(&memory, "ch2.html", 0.7)
        moveTo(&memory, "ch1.html", 0.1)
        XCTAssertNil(moveTo(&memory, "ch2.html", 0.0))
    }

    func testBackwardChapterChangeRestoresStoredPosition() {
        var memory = SpineItemPositionMemory()
        moveTo(&memory, "ch1.html", 0.6)
        moveTo(&memory, "ch2.html", 0.0)

        let restored = moveTo(&memory, "ch1.html", 1.0)

        XCTAssertEqual(restored?.href.string, "ch1.html")
        XCTAssertEqual(restored?.locations.progression, 0.6)
    }

    func testBackwardChapterChangeWithNothingStoredRestoresNothing() {
        var memory = SpineItemPositionMemory()
        // A TOC jump straight into ch3, then back to a chapter never visited.
        moveTo(&memory, "ch3.html", 0.2)
        XCTAssertNil(moveTo(&memory, "ch2.html", 0.9))
    }

    func testPaginatedModeNeverRestores() {
        var memory = SpineItemPositionMemory()
        XCTAssertNil(moveTo(&memory, "ch1.html", 0.6, isScrollMode: false))
        XCTAssertNil(moveTo(&memory, "ch2.html", 0.0, isScrollMode: false))
        XCTAssertNil(moveTo(&memory, "ch1.html", 1.0, isScrollMode: false))

        // Paginated mode also stored nothing: the same backward move in scroll
        // mode still has no ch2 position to restore.
        moveTo(&memory, "ch3.html", 0.4)
        XCTAssertNil(moveTo(&memory, "ch2.html", 0.8))
    }

    func testSameSpineItemIsNotAChapterChange() {
        var memory = SpineItemPositionMemory()
        moveTo(&memory, "ch1.html#top", 0.2)
        XCTAssertNil(moveTo(&memory, "ch1.html#middle", 0.8))

        // The second position replaced the first as ch1's remembered one.
        moveTo(&memory, "ch2.html", 0.0)
        XCTAssertEqual(moveTo(&memory, "ch1.html", 1.0)?.locations.progression, 0.8)
    }

    func testFragmentAndQueryAreStrippedWhenMatching() {
        var memory = SpineItemPositionMemory()
        moveTo(&memory, "ch1.html#sec2", 0.4)
        moveTo(&memory, "ch2.html", 0.0)

        let restored = moveTo(&memory, "ch1.html?p=1", 1.0)

        XCTAssertEqual(restored?.locations.progression, 0.4)
    }

    func testForgetDropsTheStoredPosition() {
        var memory = SpineItemPositionMemory()
        moveTo(&memory, "ch1.html", 0.6)
        moveTo(&memory, "ch2.html", 0.0)

        memory.forget(href: "ch1.html#anything")

        XCTAssertNil(moveTo(&memory, "ch1.html", 1.0))
    }

    func testUnknownHrefIsNotBackward() {
        var memory = SpineItemPositionMemory()
        moveTo(&memory, "ch2.html", 0.5)
        // Leaving ch2 stores its position, but the reading order knows nothing
        // about where we went, so the move back cannot be called backward.
        moveTo(&memory, "outside.html", 0.0)

        XCTAssertNil(moveTo(&memory, "ch2.html", 1.0))
    }

    func testStoredPositionIsTheOutgoingLocatorNotTheIncomingOne() {
        var memory = SpineItemPositionMemory()
        moveTo(&memory, "ch1.html", 0.3)
        moveTo(&memory, "ch1.html", 0.7)
        moveTo(&memory, "ch2.html", 0.9)

        let restored = moveTo(&memory, "ch1.html", 0.0)

        XCTAssertEqual(restored?.href.string, "ch1.html")
        XCTAssertEqual(restored?.locations.progression, 0.7)
    }
}
