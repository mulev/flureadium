package dev.mulev.flureadium

import android.os.Build
import androidx.media3.session.MediaSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertSame

/**
 * Guards the browse-capable session: with no playback open, the service must
 * still hand a connecting Android Auto controller a non-null
 * [androidx.media3.session.MediaLibraryService.MediaLibrarySession] so the host
 * library is browsable before anything plays. One persistent session backs every
 * connection, so it is never rebuilt per request.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@OptIn(ExperimentalCoroutinesApi::class)
internal class PluginMediaServiceLibraryTest {

    private lateinit var controller: ServiceController<PluginMediaService>

    private fun service(): PluginMediaService {
        controller = Robolectric.buildService(PluginMediaService::class.java).create()
        return controller.get()
    }

    private fun controllerInfo() = mock(MediaSession.ControllerInfo::class.java)

    @AfterTest
    fun tearDown() {
        // Release the persistent session so its id is free for the next test;
        // in production a single service owns the single session for its lifetime.
        if (::controller.isInitialized) controller.destroy()
    }

    @Test
    fun onGetSession_returnsBrowseSession_whenNoSessionOpen() {
        val service = service()

        val result = service.onGetSession(controllerInfo())

        assertNotNull(result)
    }

    @Test
    fun onGetSession_returnsSamePersistentSession_acrossConnections() {
        val service = service()

        val first = service.onGetSession(controllerInfo())
        val second = service.onGetSession(controllerInfo())

        assertNotNull(first)
        assertSame(first, second)
    }
}
