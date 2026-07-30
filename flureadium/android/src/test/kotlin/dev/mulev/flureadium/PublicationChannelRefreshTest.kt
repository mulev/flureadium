package dev.mulev.flureadium

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Guards the `/main` `refreshCarContent` route: it reaches the injected
 * browse-refresh seam (defaulting to [PluginMediaService.instance]) and always
 * replies success, including when no media service is running.
 */
@ExperimentalCoroutinesApi
@RunWith(RobolectricTestRunner::class)
internal class PublicationChannelRefreshTest {

    @Test
    fun refreshCarContent_invokesRefreshSeam_andRepliesSuccessNull() = runTest {
        var fired = 0
        val handler = PublicationMethodCallHandler(refreshCarContent = { fired++ })

        val result = handler.handleMethodCallsQueue("refreshCarContent", null)

        assertEquals(1, fired)
        assertTrue(result.isSuccess)
        assertNull(result.getOrNull())
    }

    @Test
    fun refreshCarContent_defaultSeam_isNullSafe_whenNoServiceRunning() = runTest {
        PluginMediaService.instance = null
        val handler = PublicationMethodCallHandler()

        val result = handler.handleMethodCallsQueue("refreshCarContent", null)

        assertTrue(result.isSuccess)
    }
}
