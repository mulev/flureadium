import XCTest
@testable import flureadium

final class EdgeTapInterceptViewTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultEdgeThreshold() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        XCTAssertEqual(view.edgeThresholdPoints, 44.0)
    }

    func testDefaultInterceptEdgeTaps() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        XCTAssertFalse(view.interceptEdgeTaps)
    }

    func testDefaultCallbacksAreNil() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        XCTAssertNil(view.onLeftEdgeTap)
        XCTAssertNil(view.onRightEdgeTap)
        XCTAssertNil(view.onSwipeLeft)
        XCTAssertNil(view.onSwipeRight)
    }

    // MARK: - Property behavior

    func testCustomEdgeThreshold() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        view.edgeThresholdPoints = 60.0
        XCTAssertEqual(view.edgeThresholdPoints, 60.0)
    }

    func testEdgeThresholdAcceptsAnyValue() {
        // The view is a dumb component; clamping happens in the reader views, not here.
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        view.edgeThresholdPoints = 20.0
        XCTAssertEqual(view.edgeThresholdPoints, 20.0)
        view.edgeThresholdPoints = 200.0
        XCTAssertEqual(view.edgeThresholdPoints, 200.0)
    }

    func testEdgeCallbacksAreInvocable() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        var left = false
        var right = false
        view.onLeftEdgeTap = { left = true }
        view.onRightEdgeTap = { right = true }
        view.onLeftEdgeTap?()
        view.onRightEdgeTap?()
        XCTAssertTrue(left)
        XCTAssertTrue(right)
    }

    func testCallbacksCanBeCleared() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        view.onLeftEdgeTap = { }
        view.onRightEdgeTap = { }
        view.onLeftEdgeTap = nil
        view.onRightEdgeTap = nil
        XCTAssertNil(view.onLeftEdgeTap)
        XCTAssertNil(view.onRightEdgeTap)
    }

    // MARK: - hitTest with interceptEdgeTaps = true (no subviews)

    func testHitTestLeftEdgeWithInterceptReturnsView() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        view.interceptEdgeTaps = true
        let result = view.hitTest(CGPoint(x: 10, y: 284), with: nil)
        XCTAssertEqual(result, view)
    }

    func testHitTestRightEdgeWithInterceptReturnsView() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        view.interceptEdgeTaps = true
        let result = view.hitTest(CGPoint(x: 300, y: 284), with: nil)
        XCTAssertEqual(result, view)
    }

    func testHitTestCenterWithInterceptReturnsSelf() {
        // Center touches fall through to super.hitTest, which returns self
        // for in-bounds points with no subviews.
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        view.interceptEdgeTaps = true
        let result = view.hitTest(CGPoint(x: 160, y: 284), with: nil)
        XCTAssertEqual(result, view)
    }

    // MARK: - hitTest with interceptEdgeTaps = false (no subviews)

    func testHitTestEdgeWithoutInterceptReturnsSelf() {
        // Without interceptEdgeTaps, super.hitTest still returns self for in-bounds points.
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        view.interceptEdgeTaps = false
        let result = view.hitTest(CGPoint(x: 10, y: 284), with: nil)
        XCTAssertEqual(result, view)
    }

    // MARK: - hitTest with subview proves override behavior

    func testHitTestEdgeWithInterceptBypassesSubview() {
        // With interceptEdgeTaps, the override returns self even when a subview
        // covers the edge zone — proving the override intercepts.
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let subview = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 568))
        view.addSubview(subview)
        view.interceptEdgeTaps = true
        let result = view.hitTest(CGPoint(x: 10, y: 284), with: nil)
        XCTAssertEqual(result, view, "Edge touch with intercept should return self, not the subview")
    }

    func testHitTestEdgeWithoutInterceptReturnsSubview() {
        // Without interceptEdgeTaps, super.hitTest finds the subview in the edge zone.
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let subview = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 568))
        view.addSubview(subview)
        view.interceptEdgeTaps = false
        let result = view.hitTest(CGPoint(x: 10, y: 284), with: nil)
        XCTAssertEqual(result, subview, "Edge touch without intercept should return the subview")
    }

    func testHitTestCenterReturnsSubviewRegardlessOfIntercept() {
        // Center touches are never intercepted — subview is returned if present.
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let subview = UIView(frame: CGRect(x: 100, y: 0, width: 120, height: 568))
        view.addSubview(subview)
        view.interceptEdgeTaps = true
        let result = view.hitTest(CGPoint(x: 160, y: 284), with: nil)
        XCTAssertEqual(result, subview, "Center touch should return the subview even with interceptEdgeTaps")
    }

    // MARK: - Custom threshold

    func testHitTestWithCustomThresholdInterceptsSubview() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let subview = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 568))
        view.addSubview(subview)
        view.interceptEdgeTaps = true
        view.edgeThresholdPoints = 80.0
        // x=50 is within 80pt left edge — override should bypass subview
        let result = view.hitTest(CGPoint(x: 50, y: 284), with: nil)
        XCTAssertEqual(result, view)
    }

    func testHitTestOutsideCustomThresholdReturnsSubview() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let subview = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 568))
        view.addSubview(subview)
        view.interceptEdgeTaps = true
        view.edgeThresholdPoints = 30.0
        // x=35 is outside 30pt edge — super.hitTest returns the subview
        let result = view.hitTest(CGPoint(x: 35, y: 284), with: nil)
        XCTAssertEqual(result, subview, "Touch outside custom threshold should go to subview")
    }

    // MARK: - Edge boundary precision

    func testHitTestExactlyAtLeftEdgeBoundaryReturnsSubview() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let subview = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 568))
        view.addSubview(subview)
        view.interceptEdgeTaps = true
        view.edgeThresholdPoints = 44.0
        // x=44 is exactly at boundary — point.x < edgeSize is false, so NOT intercepted
        let result = view.hitTest(CGPoint(x: 44, y: 284), with: nil)
        XCTAssertEqual(result, subview, "Touch exactly at edge boundary (not <) should go to subview")
    }

    func testHitTestJustInsideLeftEdge() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let subview = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 568))
        view.addSubview(subview)
        view.interceptEdgeTaps = true
        view.edgeThresholdPoints = 44.0
        let result = view.hitTest(CGPoint(x: 43.9, y: 284), with: nil)
        XCTAssertEqual(result, view, "Touch just inside edge should be intercepted")
    }

    func testHitTestExactlyAtRightEdgeBoundaryReturnsSubview() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let subview = UIView(frame: CGRect(x: 200, y: 0, width: 120, height: 568))
        view.addSubview(subview)
        view.interceptEdgeTaps = true
        view.edgeThresholdPoints = 44.0
        // Right boundary: 320 - 44 = 276. point.x > 276 is false for x=276, so NOT intercepted
        let result = view.hitTest(CGPoint(x: 276, y: 284), with: nil)
        XCTAssertEqual(result, subview, "Touch exactly at right edge boundary should go to subview")
    }

    func testHitTestJustInsideRightEdge() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let subview = UIView(frame: CGRect(x: 200, y: 0, width: 120, height: 568))
        view.addSubview(subview)
        view.interceptEdgeTaps = true
        view.edgeThresholdPoints = 44.0
        let result = view.hitTest(CGPoint(x: 276.1, y: 284), with: nil)
        XCTAssertEqual(result, view, "Touch just inside right edge should be intercepted")
    }

    // MARK: - Out of bounds

    func testHitTestOutOfBoundsWithInterceptReturnsSelf() {
        // x=-10 is out of bounds but satisfies point.x < edgeSize,
        // so the override returns self. This bypasses super.hitTest's
        // bounds check — possibly unintended but matches current behavior.
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        view.interceptEdgeTaps = true
        let result = view.hitTest(CGPoint(x: -10, y: 284), with: nil)
        XCTAssertEqual(result, view)
    }

    func testHitTestOutOfBoundsWithoutInterceptReturnsNil() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        view.interceptEdgeTaps = false
        let result = view.hitTest(CGPoint(x: -10, y: 284), with: nil)
        XCTAssertNil(result, "Out-of-bounds touch without intercept should return nil")
    }

    // MARK: - Gesture recognizer count

    func testViewHasThreeGestureRecognizers() {
        let view = EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        // 1 tap + 2 swipes = 3
        XCTAssertEqual(view.gestureRecognizers?.count, 3)
    }
}
