package dev.mulev.flureadium

import android.os.Build
import androidx.media3.session.MediaSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertNull

/**
 * Guards the MediaSessionService -> MediaLibraryService migration: with no open
 * session, the service must reject connections by returning a null session.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@OptIn(ExperimentalCoroutinesApi::class)
internal class PluginMediaServiceLibraryTest {

    @Test
    fun onGetSession_returnsNull_whenNoSessionOpen() {
        val service = Robolectric.buildService(PluginMediaService::class.java).create().get()

        val result = service.onGetSession(mock(MediaSession.ControllerInfo::class.java))

        assertNull(result)
    }
}
