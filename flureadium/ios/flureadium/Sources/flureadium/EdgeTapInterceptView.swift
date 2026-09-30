//
//  EdgeTapInterceptView.swift
//  flureadium
//
//  Edge tap detection overlay for reader navigation.
//  Used by all three visual readers — EPUB, PDF and CBZ — to enable page
//  navigation by tapping on the left/right edges of the screen.
//
//  This view owns no tap recognizer, deliberately. Readium's PDF tap
//  recognizer declares, through its delegate, a failure requirement against
//  any single-touch UITapGestureRecognizer competing for the same touch
//  (PDFTapGestureController.shouldRequireFailureOf). One attached anywhere in
//  this overlay's hierarchy never fails, so Readium's never fires and no PDF
//  content tap reaches the host for the whole session.
//
//  Edge taps come from the responder callbacks instead. UIKit delivers those
//  only for touches hitTest already claimed, and hitTest claims exactly when
//  interceptEdgeTaps is on and the point is in an edge zone — so the callback
//  fires precisely when this overlay has a page turn to run. Filtering the old
//  recognizer with gestureRecognizer(_:shouldReceive:) was rejected: declining
//  a touch does not move a recognizer to .failed, and require(toFail:) resolves
//  on .failed, not on "did not receive".
//
//  The swipe recognizers stay. A UISwipeGestureRecognizer does not match
//  Readium's cast, so it can never form that failure requirement. They also
//  carry cancelsTouchesInView = false, so a recognized swipe still delivers
//  touchesEnded here rather than touchesCancelled — the movement-slop check is
//  the only thing keeping an edge swipe from also reporting as an edge tap.
//

import Foundation
import UIKit

/// Which edge zone a horizontal coordinate falls in, or `nil` for the middle.
enum EdgeTapSide {
    case left
    case right
}

/// Strict comparisons on both sides: a point exactly at `threshold`, or exactly
/// at `width - threshold`, is middle. `EdgeTapInterceptViewTests` pins both
/// boundaries, and `hitTest` has always behaved this way.
func edgeTapSide(x: CGFloat, width: CGFloat, threshold: CGFloat) -> EdgeTapSide? {
    if x < threshold { return .left }
    if x > width - threshold { return .right }
    return nil
}

/// How far a touch may drift and still count as a tap rather than a swipe.
let edgeTapSlopPoints: CGFloat = 10.0

/// Whether a touch that started at `start` and ended at `end` stayed still
/// enough to be a tap.
func isTapWithinSlop(start: CGPoint, end: CGPoint, slop: CGFloat) -> Bool {
    abs(end.x - start.x) <= slop && abs(end.y - start.y) <= slop
}

/// View that intercepts edge taps for page navigation when Readium's
/// gesture recognizers fail to receive touches through Flutter's platform view.
class EdgeTapInterceptView: UIView {
    /// Callback for left edge tap
    var onLeftEdgeTap: (() -> Void)?
    /// Callback for right edge tap
    var onRightEdgeTap: (() -> Void)?
    /// Callback for swipe left gesture (in edge zones)
    var onSwipeLeft: (() -> Void)?
    /// Callback for swipe right gesture (in edge zones)
    var onSwipeRight: (() -> Void)?
    /// Edge threshold in absolute points (default 44pt, iOS HIG minimum tap target)
    var edgeThresholdPoints: CGFloat = 44.0
    /// When true, hitTest returns self for any touch in an edge zone, so the
    /// touch never reaches the WKWebView behind the overlay — neither as a page
    /// turn for Readium nor as a content tap for the tap observer.
    ///
    /// Set only when the overlay has a page turn to run on that touch:
    /// `shouldInterceptEdgeTaps` is `!isScrollMode && edgeTapEnabled`. Claiming
    /// while edge tap is off would swallow a content tap for nothing, now that
    /// `DirectionalNavigationAdapter` is built with an empty pointer policy and
    /// no longer competes for those touches.
    var interceptEdgeTaps: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestureRecognizer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestureRecognizer()
    }

    private func setupGestureRecognizer() {
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        swipeLeft.cancelsTouchesInView = false
        swipeLeft.delaysTouchesBegan = false
        swipeLeft.delaysTouchesEnded = false
        addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        swipeRight.cancelsTouchesInView = false
        swipeRight.delaysTouchesBegan = false
        swipeRight.delaysTouchesEnded = false
        addGestureRecognizer(swipeRight)
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .left:
            onSwipeLeft?()
        case .right:
            onSwipeRight?()
        default:
            break
        }
    }

    /// The single touch currently eligible to become an edge tap.
    ///
    /// Only touches `hitTest` claimed reach these callbacks, and `hitTest`
    /// claims exactly when `interceptEdgeTaps` is on and the point is in an
    /// edge zone — so a tracked touch always has a page turn waiting for it.
    private var trackedTouch: UITouch?
    private var trackedStart: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        // A second finger means this is not a single tap. Drop the candidate
        // rather than guessing which touch the user meant.
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first else {
            trackedTouch = nil
            return
        }

        trackedTouch = touch
        trackedStart = touch.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        guard let tracked = trackedTouch, touches.contains(tracked) else { return }
        if !isTapWithinSlop(
            start: trackedStart, end: tracked.location(in: self), slop: edgeTapSlopPoints)
        {
            trackedTouch = nil
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        guard let tracked = trackedTouch, touches.contains(tracked) else { return }
        trackedTouch = nil

        guard
            isTapWithinSlop(
                start: trackedStart, end: tracked.location(in: self), slop: edgeTapSlopPoints)
        else { return }

        // The side comes from the start point: `hitTest` claimed this touch on
        // its start location, so that is the coordinate the claim was about.
        switch edgeTapSide(x: trackedStart.x, width: bounds.width, threshold: edgeThresholdPoints) {
        case .left: onLeftEdgeTap?()
        case .right: onRightEdgeTap?()
        case nil: break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        trackedTouch = nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)

        if interceptEdgeTaps,
            edgeTapSide(x: point.x, width: bounds.width, threshold: edgeThresholdPoints) != nil
        {
            return self
        }

        return result
    }
}
