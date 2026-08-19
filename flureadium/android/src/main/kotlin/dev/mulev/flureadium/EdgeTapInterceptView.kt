package dev.mulev.flureadium

import android.content.Context
import android.util.AttributeSet
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.FrameLayout
import kotlin.math.abs

private const val TAG = "EdgeTapInterceptView"

/**
 * Transparent FrameLayout overlay placed on top of the Readium navigator view.
 * Intercepts touch events in left/right edge zones to provide configurable
 * edge-tap and swipe gesture navigation — matching the iOS EdgeTapInterceptView.
 *
 * Center touches always pass through to child views (Readium WebView / PDF view).
 */
class EdgeTapInterceptView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {

    // ── Base callbacks wired by the fragment (never cleared externally) ────────

    private var baseOnLeftEdgeTap: (() -> Unit)? = null
    private var baseOnRightEdgeTap: (() -> Unit)? = null
    private var baseOnSwipeLeft: (() -> Unit)? = null
    private var baseOnSwipeRight: (() -> Unit)? = null

    // ── Computed effective callbacks (may be null'd by config / scroll mode) ──

    private var onLeftEdgeTap: (() -> Unit)? = null
    private var onRightEdgeTap: (() -> Unit)? = null
    private var onSwipeLeft: (() -> Unit)? = null
    private var onSwipeRight: (() -> Unit)? = null

    // ── State ─────────────────────────────────────────────────────────────────

    private var storedConfig: FlutterNavigationConfig? = null
    private var isInScrollMode: Boolean = false
    private var edgeTapThresholdDp: Float = 44f

    private val minFlingVelocityPx: Float by lazy {
        ViewConfiguration.get(context).scaledMinimumFlingVelocity.toFloat()
    }

    // ── Gesture detector ──────────────────────────────────────────────────────

    private val gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {

        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            val thresholdPx = dpToPx(edgeTapThresholdDp, resources.displayMetrics.density)
            val x = e.x
            return when {
                x < thresholdPx -> {
                    Log.d(TAG, "onSingleTapConfirmed: left edge tap")
                    onLeftEdgeTap?.invoke()
                    true
                }
                x > width - thresholdPx -> {
                    Log.d(TAG, "onSingleTapConfirmed: right edge tap")
                    onRightEdgeTap?.invoke()
                    true
                }
                else -> false
            }
        }

        override fun onFling(
            e1: MotionEvent?,
            e2: MotionEvent,
            velocityX: Float,
            velocityY: Float,
        ): Boolean {
            val absVX = abs(velocityX)
            val absVY = abs(velocityY)
            if (absVX < minFlingVelocityPx || absVY > absVX) return false

            return if (velocityX < 0) {
                Log.d(TAG, "onFling: swipe left → next")
                onSwipeLeft?.invoke()
                true
            } else {
                Log.d(TAG, "onFling: swipe right → prev")
                onSwipeRight?.invoke()
                true
            }
        }
    })

    // ── Touch dispatch ────────────────────────────────────────────────────────

    /**
     * Tracks whether the current touch sequence was claimed by this overlay.
     * Set on ACTION_DOWN; cleared on ACTION_UP / ACTION_CANCEL.
     */
    private var isClaimed = false

    /**
     * Intercepts edge-zone touches by claiming the gesture in dispatchTouchEvent.
     *
     * Why not onInterceptTouchEvent + onTouchEvent?
     * onInterceptTouchEvent returning true causes ViewGroup to call onTouchEvent.
     * onTouchEvent returns gestureDetector.onTouchEvent() which returns onDown() = false
     * (SimpleOnGestureListener default). The false return propagates out of
     * dispatchTouchEvent, so the parent FrameLayout never registers this view as the
     * touch target — subsequent ACTION_MOVE and ACTION_UP events never arrive, and
     * onSingleTapConfirmed never fires.
     *
     * Overriding dispatchTouchEvent directly lets us return true unconditionally for
     * claimed gestures, keeping the gesture sequence alive until ACTION_UP / CANCEL.
     * Center touches return false immediately, passing through to the Readium WebView.
     */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val thresholdPx = dpToPx(edgeTapThresholdDp, resources.displayMetrics.density)
                val x = ev.x
                val hasLeft = onLeftEdgeTap != null || onSwipeRight != null
                val hasRight = onRightEdgeTap != null || onSwipeLeft != null
                isClaimed = (hasLeft && isInLeftEdge(x, thresholdPx)) ||
                    (hasRight && isInRightEdge(x, width, thresholdPx))
                Log.d(TAG, "dispatchTouchEvent ACTION_DOWN x=$x width=$width threshold=$thresholdPx claimed=$isClaimed")
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val wasClaimed = isClaimed
                isClaimed = false
                if (wasClaimed) {
                    gestureDetector.onTouchEvent(ev)
                }
                return wasClaimed
            }
        }

        if (!isClaimed) return false
        gestureDetector.onTouchEvent(ev)
        return true
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Wire the navigation callbacks once after the navigator is attached.
     * Call this from the reader fragment's attachNavigator().
     */
    fun wireCallbacks(
        onLeft: () -> Unit,
        onRight: () -> Unit,
        onSwipeLeft: () -> Unit,
        onSwipeRight: () -> Unit,
    ) {
        baseOnLeftEdgeTap = onLeft
        baseOnRightEdgeTap = onRight
        baseOnSwipeLeft = onSwipeLeft
        baseOnSwipeRight = onSwipeRight
        recompute()
    }

    /**
     * Apply a navigation config received from Flutter via setNavigationConfig.
     * Stores the config and recomputes effective callbacks.
     */
    fun applyConfig(config: FlutterNavigationConfig) {
        storedConfig = config
        recompute()
    }

    /**
     * Enable or disable all gestures for scroll mode.
     * In scroll mode, Readium's WebView handles native scrolling so the overlay
     * must not intercept touches.
     */
    fun setScrollMode(isScrollMode: Boolean) {
        isInScrollMode = isScrollMode
        recompute()
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun recompute() {
        val config = storedConfig
        edgeTapThresholdDp = effectiveThresholdDp(config)

        if (isInScrollMode) {
            onLeftEdgeTap = null
            onRightEdgeTap = null
            onSwipeLeft = null
            onSwipeRight = null
            return
        }

        onLeftEdgeTap = if (effectiveEdgeTapEnabled(config, false)) baseOnLeftEdgeTap else null
        onRightEdgeTap = if (effectiveEdgeTapEnabled(config, false)) baseOnRightEdgeTap else null
        onSwipeLeft = if (effectiveSwipeEnabled(config, false)) baseOnSwipeLeft else null
        onSwipeRight = if (effectiveSwipeEnabled(config, false)) baseOnSwipeRight else null
    }

    companion object {
        internal fun isInLeftEdge(x: Float, thresholdPx: Float): Boolean = x < thresholdPx

        internal fun isInRightEdge(x: Float, viewWidth: Int, thresholdPx: Float): Boolean =
            x > viewWidth - thresholdPx

        internal fun dpToPx(dp: Float, density: Float): Float = dp * density

        internal fun effectiveEdgeTapEnabled(
            config: FlutterNavigationConfig?,
            isScrollMode: Boolean,
        ): Boolean = !isScrollMode && config?.enableEdgeTapNavigation != false

        internal fun effectiveSwipeEnabled(
            config: FlutterNavigationConfig?,
            isScrollMode: Boolean,
        ): Boolean = !isScrollMode && config?.enableSwipeNavigation != false

        internal fun effectiveThresholdDp(config: FlutterNavigationConfig?): Float =
            config?.edgeTapAreaPoints?.toFloat() ?: 44f
    }
}
