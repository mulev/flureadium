package dev.mulev.flureadium

import org.mockito.Mockito.mock
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Covers the session-reuse decision that stops `play(locator)` from rebuilding a
 * duplicate [PluginMediaService.Session] on a chapter jump or bookmark tap.
 *
 * The decision is reference-identity based: the same navigator instance reuses
 * the live session, a different navigator replaces it, and no open session opens
 * a fresh one.
 */
@OptIn(ExperimentalReadiumApi::class)
internal class PluginMediaServiceReuseTest {

    private fun navigator(): AnyMediaNavigator =
        mock(MediaNavigator::class.java) as AnyMediaNavigator

    @Test
    fun sessionActionFor_noOpenSession_isFresh() {
        assertEquals(SessionAction.FRESH, sessionActionFor(null, navigator()))
    }

    @Test
    fun sessionActionFor_sameNavigator_isReuse() {
        val nav = navigator()

        assertEquals(SessionAction.REUSE, sessionActionFor(nav, nav))
    }

    @Test
    fun sessionActionFor_differentNavigator_isReplace() {
        assertEquals(SessionAction.REPLACE, sessionActionFor(navigator(), navigator()))
    }
}
