package dev.mulev.flureadium.navigators

import android.graphics.PointF
import android.view.View
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.readium.r2.navigator.VisualNavigator
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.shared.ExperimentalReadiumApi
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Pins the three parts of the tap contract that are invisible when broken.
 *
 * A tap reported twice and a tap never reported look identical in a host that
 * toggles chrome on it, and a listener that consumed the event would silently
 * starve every listener Readium registered behind it. None of those show up as a
 * crash, so they are pinned here rather than left to a device run.
 *
 * Coordinates are asserted at xxhdpi (density 3.0) because a conversion that is
 * missing entirely still passes at the default mdpi, where density is 1.
 */
@OptIn(ExperimentalReadiumApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE, qualifiers = "xxhdpi")
internal class NavigatorTapForwarderTest {

    private val taps = mutableListOf<Pair<Double, Double>>()
    private val forwarder = NavigatorTapForwarder { x, y -> taps.add(x to y) }

    @Test
    fun `forwards a tap in logical pixels`() {
        forwarder.bindTo(navigator())

        forwarder.onTap(TapEvent(PointF(60f, 90f)))

        assertEquals(listOf(20.0 to 30.0), taps)
    }

    @Test
    fun `does not consume the tap`() {
        forwarder.bindTo(navigator())

        assertFalse(forwarder.onTap(TapEvent(PointF(60f, 90f))))
    }

    @Test
    fun `ignores a tap that lands after the navigator view is gone`() {
        val navigator = mock(VisualNavigator::class.java)
        // publicationView is requireView(): it throws once the fragment's view is
        // destroyed, which a tap queued from the WebView bridge can outlive.
        `when`(navigator.publicationView).thenThrow(IllegalStateException("view destroyed"))
        forwarder.bindTo(navigator)

        assertFalse(forwarder.onTap(TapEvent(PointF(60f, 90f))))
        assertTrue(taps.isEmpty())
    }

    @Test
    fun `registers once for the same navigator`() {
        val navigator = navigator()

        forwarder.bindTo(navigator)
        forwarder.bindTo(navigator)

        verify(navigator, times(1)).addInputListener(forwarder)
    }

    @Test
    fun `moves the registration to a recreated navigator`() {
        val paused = navigator()
        val resumed = navigator()

        forwarder.bindTo(paused)
        forwarder.bindTo(resumed)

        verify(paused).removeInputListener(forwarder)
        verify(resumed).addInputListener(forwarder)
    }

    @Test
    fun `keeps the current registration when there is no navigator to bind`() {
        val navigator = navigator()
        forwarder.bindTo(navigator)

        forwarder.bindTo(null)

        verify(navigator, never()).removeInputListener(forwarder)
        forwarder.onTap(TapEvent(PointF(60f, 90f)))
        assertEquals(listOf(20.0 to 30.0), taps)
    }

    @Test
    fun `unbind removes the registration and stops forwarding`() {
        val navigator = navigator()
        forwarder.bindTo(navigator)

        forwarder.unbind()

        verify(navigator).removeInputListener(forwarder)
        assertFalse(forwarder.onTap(TapEvent(PointF(60f, 90f))))
        assertTrue(taps.isEmpty())
    }

    @Test
    fun `binds again after unbind`() {
        val navigator = navigator()
        forwarder.bindTo(navigator)
        forwarder.unbind()

        forwarder.bindTo(navigator)

        verify(navigator, times(2)).addInputListener(forwarder)
    }

    /** A navigator whose view carries the density this test converts against. */
    private fun navigator(): VisualNavigator {
        val navigator = mock(VisualNavigator::class.java)
        `when`(navigator.publicationView).thenReturn(View(RuntimeEnvironment.getApplication()))
        return navigator
    }
}
