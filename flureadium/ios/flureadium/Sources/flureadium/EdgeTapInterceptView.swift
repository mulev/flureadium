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
//  touchesEnded here rather than touchesCancelled.
//
//  A recognizer used to answer three questions; the responder path has to ask
//  all three itself, and qualifiesAsEdgeTap is where they live: the touch
//  stayed within slop (not a swipe), it was brief (not a long press, which
//  UITapGestureRecognizer failed on outright), and no second finger was down
//  (numberOfTouchesRequired = 1).
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

/// How long a touch may last and still count as a tap.
///
/// `UITapGestureRecognizer` enforced its own limit; without one, a press held
/// in the edge strip and released turns the page.
let edgeTapMaxDurationSeconds: TimeInterval = 0.7

/// Whether a finished touch was a tap this overlay should act on.
///
/// `touchCount` is the whole event's touch count, not the callback's set: each
/// callback receives only what `hitTest` handed this view, and
/// `isMultipleTouchEnabled` is false, so that set is always a single touch. A
/// finger resting on content hit-tests elsewhere and shows up nowhere but
/// `UIEvent.allTouches`. The removed recognizer sat above the navigator and saw
/// both, which is how it rejected a parked thumb.
func qualifiesAsEdgeTap(
    touchCount: Int, elapsed: TimeInterval, start: CGPoint, end: CGPoint
) -> Bool {
    touchCount == 1
        && elapsed <= edgeTapMaxDurationSeconds
        && isTapWithinSlop(start: start, end: end, slop: edgeTapSlopPoints)
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
    private var trackedStartTime: TimeInterval = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        guard trackedTouch == nil, let touch = touches.first else {
            trackedTouch = nil
            return
        }

        trackedTouch = touch
        trackedStart = touch.location(in: self)
        trackedStartTime = touch.timestamp
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

        // `allTouches` is the only view of a finger resting on content, which
        // hit-tests to the navigator and never reaches this callback's set.
        guard
            qualifiesAsEdgeTap(
                touchCount: event?.allTouches?.count ?? 0,
                elapsed: tracked.timestamp - trackedStartTime,
                start: trackedStart,
                end: tracked.location(in: self))
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
