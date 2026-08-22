package dev.mulev.flureadium

import android.os.SystemClock
import android.view.MotionEvent
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Before
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper

/**
 * Behavioural tests for EdgeTapInterceptView.dispatchTouchEvent.
 *
 * These tests guard against the original bug where onInterceptTouchEvent + onTouchEvent
 * failed to claim the gesture sequence: onTouchEvent returned gestureDetector.onTouchEvent()
 * which returned onDown() = false, causing dispatchTouchEvent to return false, so the parent
 * FrameLayout never forwarded ACTION_UP and onSingleTapConfirmed never fired.
 *
 * Uses Robolectric to instantiate a real View with layout bounds set.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class EdgeTapInterceptViewDispatchTest {

    private lateinit var view: EdgeTapInterceptView

    // Simulate a typical phone screen width in px (density=1 for simplicity)
    private val viewWidth = 400
    private val viewHeight = 800

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        view = EdgeTapInterceptView(context)
        // Set layout bounds so view.width returns the expected value
        view.layout(0, 0, viewWidth, viewHeight)
    }

    /**
     * Builds an event at mid-height. A fling needs distinct down and event
     * times; [down] and [up] stamp both alike.
     */
    private fun event(action: Int, x: Float, downTime: Long, eventTime: Long): MotionEvent =
        MotionEvent.obtain(downTime, eventTime, action, x, 400f, 0)

    private fun down(x: Float): MotionEvent {
        val now = SystemClock.uptimeMillis()
        return event(MotionEvent.ACTION_DOWN, x, now, now)
    }

    private fun up(x: Float): MotionEvent {
        val now = SystemClock.uptimeMillis()
        return event(MotionEvent.ACTION_UP, x, now, now)
    }

    /** Edge taps off, swipe on — the pairing that used to swallow the touch. */
    private val edgeTapOffSwipeOn = FlutterNavigationConfig(
        enableEdgeTapNavigation = false,
        enableSwipeNavigation = true,
    )

    // ── Gesture claiming ──────────────────────────────────────────────────────

    @Test
    fun dispatchTouchEvent_leftEdge_claimsGesture() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})
        // 20px is well inside the 44dp left edge zone (density=1 in test)
        val ev = down(x = 20f)
        assertTrue(view.dispatchTouchEvent(ev), "Left edge ACTION_DOWN should return true (claimed)")
        ev.recycle()
    }

    @Test
    fun dispatchTouchEvent_rightEdge_claimsGesture() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})
        // 390px > 400-44=356, inside right edge zone
        val ev = down(x = 390f)
        assertTrue(view.dispatchTouchEvent(ev), "Right edge ACTION_DOWN should return true (claimed)")
        ev.recycle()
    }

    @Test
    fun dispatchTouchEvent_center_passesThroughGesture() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})
        // 200px is the center — outside both edge zones
        val ev = down(x = 200f)
        assertFalse(view.dispatchTouchEvent(ev), "Center ACTION_DOWN should return false (pass-through)")
        ev.recycle()
    }

    // ── Gesture sequence continuity ───────────────────────────────────────────

    @Test
    fun dispatchTouchEvent_upAfterClaimedDown_returnsTrueAndClearsState() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})
        val d = down(x = 390f)
        view.dispatchTouchEvent(d)

        val u = up(x = 390f)
        assertTrue(view.dispatchTouchEvent(u), "ACTION_UP after claimed DOWN should return true")
        d.recycle()
        u.recycle()
    }

    @Test
    fun dispatchTouchEvent_upAfterUnclaimedDown_returnsFalse() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})
        val d = down(x = 200f)
        view.dispatchTouchEvent(d)

        val u = up(x = 200f)
        assertFalse(view.dispatchTouchEvent(u), "ACTION_UP after unclaimed DOWN should return false")
        d.recycle()
        u.recycle()
    }

    @Test
    fun dispatchTouchEvent_secondDownAfterUnclaimed_reassessesEdgeZone() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})

        // First tap in center — not claimed
        val d1 = down(x = 200f)
        assertFalse(view.dispatchTouchEvent(d1))
        view.dispatchTouchEvent(up(x = 200f))
        d1.recycle()

        // Second tap on right edge — should be claimed
        val d2 = down(x = 390f)
        assertTrue(view.dispatchTouchEvent(d2), "Edge tap after center tap should still be claimed")
        d2.recycle()
    }

    // ── Scroll mode ───────────────────────────────────────────────────────────

    @Test
    fun dispatchTouchEvent_scrollMode_edgePassesThroughGesture() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})
        view.setScrollMode(true)

        val ev = down(x = 390f)
        assertFalse(view.dispatchTouchEvent(ev), "Edge tap in scroll mode should pass through (return false)")
        ev.recycle()
    }

    @Test
    fun dispatchTouchEvent_exitScrollMode_resumesEdgeClaiming() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})
        view.setScrollMode(true)
        view.setScrollMode(false)

        val ev = down(x = 390f)
        assertTrue(view.dispatchTouchEvent(ev), "Edge tap after exiting scroll mode should be claimed")
        ev.recycle()
    }

    // ── Callbacks ─────────────────────────────────────────────────────────────

    @Test
    fun dispatchTouchEvent_rightEdgeTap_firesOnRightCallback() {
        var rightFired = false
        view.wireCallbacks(
            onLeft = { },
            onRight = { rightFired = true },
            onSwipeLeft = { },
            onSwipeRight = { },
        )

        view.dispatchTouchEvent(down(x = 390f))
        view.dispatchTouchEvent(up(x = 390f))

        // GestureDetector delays onSingleTapConfirmed by DOUBLE_TAP_TIMEOUT (~300 ms)
        ShadowLooper.runUiThreadTasksIncludingDelayedTasks()

        assertTrue(rightFired, "onRight callback should fire after right-edge single tap")
    }

    @Test
    fun dispatchTouchEvent_leftEdgeTap_firesOnLeftCallback() {
        var leftFired = false
        view.wireCallbacks(
            onLeft = { leftFired = true },
            onRight = { },
            onSwipeLeft = { },
            onSwipeRight = { },
        )

        view.dispatchTouchEvent(down(x = 20f))
        view.dispatchTouchEvent(up(x = 20f))

        ShadowLooper.runUiThreadTasksIncludingDelayedTasks()

        assertTrue(leftFired, "onLeft callback should fire after left-edge single tap")
    }

    @Test
    fun dispatchTouchEvent_centerTap_doesNotFireAnyCallback() {
        var anyFired = false
        view.wireCallbacks(
            onLeft = { anyFired = true },
            onRight = { anyFired = true },
            onSwipeLeft = { anyFired = true },
            onSwipeRight = { anyFired = true },
        )

        view.dispatchTouchEvent(down(x = 200f))
        view.dispatchTouchEvent(up(x = 200f))

        ShadowLooper.runUiThreadTasksIncludingDelayedTasks()

        assertFalse(anyFired, "No callback should fire for a center tap")
    }

    @Test
    fun dispatchTouchEvent_noCallbacksWired_centerDoesNotCrash() {
        // wireCallbacks not called — all effective callbacks are null
        val ev = down(x = 200f)
        assertFalse(view.dispatchTouchEvent(ev))
        ev.recycle()
    }

    @Test
    fun dispatchTouchEvent_noCallbacksWired_edgePassesThrough() {
        // Before wireCallbacks, no effective callbacks exist — edge zone not entered
        val ev = down(x = 390f)
        assertFalse(view.dispatchTouchEvent(ev), "Edge with no callbacks should pass through")
        ev.recycle()
    }

    // ── Config gating ─────────────────────────────────────────────────────────

    @Test
    fun dispatchTouchEvent_edgeTapOff_swipeOn_leftEdgePassesThrough() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})
        view.applyConfig(edgeTapOffSwipeOn)

        val ev = down(x = 20f)
        assertFalse(
            view.dispatchTouchEvent(ev),
            "With edge tap off the left strip must pass through so Readium can report the tap",
        )
        ev.recycle()
    }

    @Test
    fun dispatchTouchEvent_edgeTapOff_swipeOn_rightEdgePassesThrough() {
        view.wireCallbacks(onLeft = {}, onRight = {}, onSwipeLeft = {}, onSwipeRight = {})
        view.applyConfig(edgeTapOffSwipeOn)

        val ev = down(x = 390f)
        assertFalse(
            view.dispatchTouchEvent(ev),
            "With edge tap off the right strip must pass through so Readium can report the tap",
        )
        ev.recycle()
    }

    @Test
    fun dispatchTouchEvent_edgeTapOn_flingInsideClaimedStrip_firesSwipe() {
        var swipedLeft = false
        view.wireCallbacks(
            onLeft = {},
            onRight = {},
            onSwipeLeft = { swipedLeft = true },
            onSwipeRight = {},
        )
        view.applyConfig(
            FlutterNavigationConfig(
                enableEdgeTapNavigation = true,
                enableSwipeNavigation = true,
            )
        )

        // DOWN inside the right strip claims the sequence, then a leftward
        // fling: 190 px in 40 ms is ~4750 px/s, far over the 50 px/s floor.
        val t0 = SystemClock.uptimeMillis()
        view.dispatchTouchEvent(event(MotionEvent.ACTION_DOWN, x = 390f, t0, t0))
        view.dispatchTouchEvent(event(MotionEvent.ACTION_MOVE, x = 300f, t0, t0 + 20))
        view.dispatchTouchEvent(event(MotionEvent.ACTION_MOVE, x = 200f, t0, t0 + 40))
        view.dispatchTouchEvent(event(MotionEvent.ACTION_UP, x = 200f, t0, t0 + 50))

        assertTrue(swipedLeft, "A fling inside a claimed strip must still reach onSwipeLeft")
    }

    @Test
    fun dispatchTouchEvent_edgeTapOff_flingInsideStrip_firesNothing() {
        var swipedLeft = false
        view.wireCallbacks(
            onLeft = {},
            onRight = {},
            onSwipeLeft = { swipedLeft = true },
            onSwipeRight = {},
        )
        view.applyConfig(edgeTapOffSwipeOn)

        // The same fling as the case above. With edge tap off nothing is
        // claimed, so the detector never sees the sequence: on Android a fling
        // pages only inside a strip the edge-tap gate already claimed. The
        // documented consequence of releasing the strips, pinned here so a
        // future claim source cannot reappear unnoticed.
        val t0 = SystemClock.uptimeMillis()
        view.dispatchTouchEvent(event(MotionEvent.ACTION_DOWN, x = 390f, t0, t0))
        view.dispatchTouchEvent(event(MotionEvent.ACTION_MOVE, x = 300f, t0, t0 + 20))
        view.dispatchTouchEvent(event(MotionEvent.ACTION_MOVE, x = 200f, t0, t0 + 40))
        view.dispatchTouchEvent(event(MotionEvent.ACTION_UP, x = 200f, t0, t0 + 50))

        assertFalse(swipedLeft, "With edge tap off no strip is claimed, so no fling can page")
    }
}
