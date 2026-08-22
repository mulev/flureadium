package dev.mulev.flureadium.fragments

import android.view.MotionEvent
import dev.mulev.flureadium.EdgeTapInterceptView
import dev.mulev.flureadium.FlutterNavigationConfig
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Pins what a rebuilt edge-tap overlay is configured with.
 *
 * The reader fragments drop their overlay on pause and build a new one on
 * resume, and a new overlay starts with gestures on and scroll mode off. Any
 * state the host set earlier has to be re-applied there, and forgetting one is
 * silent: an overlay claiming both edge strips over a scrolling WebView eats the
 * touch and stops `onTap` from firing, with nothing logged.
 *
 * The claim is read through `dispatchTouchEvent` rather than a getter, because
 * claiming the touch is the whole observable behaviour.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class OverlayConfigurationTest {

    private val overlay = EdgeTapInterceptView(RuntimeEnvironment.getApplication())
    private val pages = mutableListOf<String>()

    private val edgeTapsOn = FlutterNavigationConfig(
        enableEdgeTapNavigation = true,
        enableSwipeNavigation = true,
        edgeTapAreaPoints = 44.0,
    )

    @Test
    fun `a rebuilt overlay in scroll mode claims no edge strip`() {
        wire()

        configureOverlay(overlay, edgeTapsOn, isScrollMode = true)

        assertFalse(overlay.dispatchTouchEvent(downAt(x = 10f)))
        assertFalse(overlay.dispatchTouchEvent(downAt(x = 390f)))
    }

    @Test
    fun `a rebuilt overlay outside scroll mode claims the strips again`() {
        wire()

        configureOverlay(overlay, edgeTapsOn, isScrollMode = false)

        assertTrue(overlay.dispatchTouchEvent(downAt(x = 10f)))
    }

    @Test
    fun `a rebuilt overlay with no stored config still gets its scroll state`() {
        wire()

        // The host set nothing, so the overlay keeps its own default of edge taps
        // enabled, and scroll mode still has to switch them off.
        configureOverlay(overlay, config = null, isScrollMode = true)

        assertFalse(overlay.dispatchTouchEvent(downAt(x = 10f)))
    }

    @Test
    fun `a later toggle from the host beats the preference the reader opened with`() {
        // The order that made the first version of this fix wrong: opened
        // paginated, switched to scroll mode later, then resumed. model.preferences
        // is only assigned when a navigator is built, so on that resume it can
        // still read false while the host is in scroll mode.
        assertEquals(true, seedScrollMode(hostScroll = true, preferenceScroll = false))
        assertEquals(false, seedScrollMode(hostScroll = false, preferenceScroll = true))
    }

    @Test
    fun `the navigator preference seeds it until the host says otherwise`() {
        // A reader opened straight into scroll mode never gets a setPreferences
        // round trip, so the preference is the only thing that knows.
        assertEquals(true, seedScrollMode(hostScroll = null, preferenceScroll = true))
        assertEquals(false, seedScrollMode(hostScroll = null, preferenceScroll = false))
        assertEquals(false, seedScrollMode(hostScroll = null, preferenceScroll = null))
    }

    private fun wire() {
        overlay.layout(0, 0, 400, 800)
        overlay.wireCallbacks(
            onLeft = { pages.add("left") },
            onRight = { pages.add("right") },
            onSwipeLeft = { pages.add("swipeLeft") },
            onSwipeRight = { pages.add("swipeRight") },
        )
    }

    private fun downAt(x: Float): MotionEvent =
        MotionEvent.obtain(0L, 0L, MotionEvent.ACTION_DOWN, x, 400f, 0)
}
