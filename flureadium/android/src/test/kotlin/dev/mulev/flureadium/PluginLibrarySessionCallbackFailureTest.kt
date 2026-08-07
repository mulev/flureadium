package dev.mulev.flureadium

import android.os.Build
import android.os.Bundle
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import dev.mulev.flureadium.navigators.AudiobookNavigator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.readium.r2.shared.ExperimentalReadiumApi
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The car and notification rewind/forward buttons run their work in a coroutine
 * of their own.
 *
 * They used to launch it with `async` into a throwaway scope whose Deferred
 * nobody read, so a failed rewind was neither reported nor logged. The buttons
 * answer the session immediately either way; what changes here is that the
 * failure now reaches the host app.
 */
@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class PluginLibrarySessionCallbackFailureTest {

    private val testDispatcher = UnconfinedTestDispatcher()
    private val uncaught = mutableListOf<Throwable>()
    private var previousHandler: Thread.UncaughtExceptionHandler? = null

    private val session = mock(MediaLibrarySession::class.java)
    private val browser = mock(MediaSession.ControllerInfo::class.java)

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        resetReaderState()
        previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { _, throwable -> uncaught.add(throwable) }
    }

    @AfterTest
    fun tearDown() {
        Thread.setDefaultUncaughtExceptionHandler(previousHandler)
        Dispatchers.resetMain()
        resetReaderState()
    }

    @Test
    fun aFailedRewindReportsInsteadOfVanishing() {
        val errors = subscribeToErrorEvents()
        seedFailingAudiobookNavigator()

        val result = rewind()

        val errorEvent = errors.single()
        assertEquals("no audio session", errorEvent["message"])
        assertEquals("ReaderFailure", errorEvent["code"])
        assertTrue(uncaught.isEmpty(), "the failure must be reported, not thrown at the process")
        assertEquals(SessionResult.RESULT_SUCCESS, result, "the button still answers the session")
    }

    private fun rewind(): Int =
        PluginLibrarySessionCallback(
            sourceProvider = { null },
            publicationProvider = { null },
        ).onCustomCommand(
            session,
            browser,
            SessionCommand(NotificationPlayerCustomCommandButton.REWIND.customAction, Bundle()),
            Bundle(),
        ).get().resultCode

    /** Seeds a navigator whose `goBack()` fails, which is what a rewind calls. */
    private fun seedFailingAudiobookNavigator() {
        val navigator = mock(AudiobookNavigator::class.java)
        `when`(runBlocking { navigator.goBack() })
            .thenThrow(IllegalStateException("no audio session"))
        setReaderField("audiobookNavigator", navigator)
    }
}
