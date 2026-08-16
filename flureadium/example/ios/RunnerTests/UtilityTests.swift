import XCTest
import UIKit
@testable import flureadium

final class UtilityTests: XCTestCase {

    // MARK: - clamp

    func testClampBelowMinimum() {
        XCTAssertEqual(clamp(1, minValue: 5, maxValue: 10), 5)
    }

    func testClampAboveMaximum() {
        XCTAssertEqual(clamp(15, minValue: 5, maxValue: 10), 10)
    }

    func testClampWithinRange() {
        XCTAssertEqual(clamp(7, minValue: 5, maxValue: 10), 7)
    }

    func testClampAtMinBoundary() {
        XCTAssertEqual(clamp(5, minValue: 5, maxValue: 10), 5)
    }

    func testClampAtMaxBoundary() {
        XCTAssertEqual(clamp(10, minValue: 5, maxValue: 10), 10)
    }

    func testClampWithDoubles() {
        XCTAssertEqual(clamp(0.3, minValue: 0.5, maxValue: 2.0), 0.5)
        XCTAssertEqual(clamp(3.0, minValue: 0.5, maxValue: 2.0), 2.0)
        XCTAssertEqual(clamp(1.0, minValue: 0.5, maxValue: 2.0), 1.0)
    }

    // MARK: - Collection.firstMap

    func testFirstMapReturnsFirstMatch() {
        let result = [1, 2, 3].firstMap { $0 > 1 ? "\($0)" : nil }
        XCTAssertEqual(result, "2")
    }

    func testFirstMapReturnsNilForNoMatch() {
        let result = [1, 2, 3].firstMap { _ in nil as String? }
        XCTAssertNil(result)
    }

    func testFirstMapOnEmptyCollection() {
        let result = [Int]().firstMap { "\($0)" }
        XCTAssertNil(result)
    }

    func testFirstMapReturnsFirstNotAll() {
        var callCount = 0
        let result = [10, 20, 30].firstMap { val -> Int? in
            callCount += 1
            return val >= 20 ? val : nil
        }
        XCTAssertEqual(result, 20)
        XCTAssertEqual(callCount, 2, "Should stop after first match")
    }

    // MARK: - Sequence.asyncCompactMap

    func testAsyncCompactMapFiltersNils() async {
        let input = [1, 2, 3, 4, 5]
        let result = await input.asyncCompactMap { val -> String? in
            val.isMultiple(of: 2) ? "\(val)" : nil
        }
        XCTAssertEqual(result, ["2", "4"])
    }

    func testAsyncCompactMapEmptySequence() async {
        let result = await [Int]().asyncCompactMap { "\($0)" }
        XCTAssertEqual(result, [])
    }

    func testAsyncCompactMapAllNil() async {
        let result = await [1, 2, 3].asyncCompactMap { _ -> String? in nil }
        XCTAssertEqual(result, [])
    }

    func testAsyncCompactMapAllNonNil() async {
        let result = await [1, 2, 3].asyncCompactMap { "\($0)" }
        XCTAssertEqual(result, ["1", "2", "3"])
    }

    // MARK: - UIView.addPinnedSubview

    func testAddPinnedSubviewActivatesFourEdgeConstraints() {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let child = UIView()

        parent.addPinnedSubview(child)

        XCTAssertIdentical(child.superview, parent)
        XCTAssertFalse(child.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(parent.constraints.filter(\.isActive).count, 4)

        // Counting constraints passes even when an anchor is paired to the wrong
        // edge, so resolve the layout and check the geometry it produced.
        parent.layoutIfNeeded()
        XCTAssertEqual(child.frame, parent.bounds)
    }
}
