package dev.mulev.flureadium

import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Tests that a failed enable is reported instead of killing the process.
 *
 * The widget dispatches its enable from init, which runs inside the platform
 * view's create call. Before this phase the throw had one destination: the
 * thread's uncaught handler, which on Android kills the app. The recorder
 * installed here stands in for that handler, so a failure that still reaches it
 * fails the test instead of taking the JVM down.
 *
 * The failure cases seed no publication, so readerKind falls back to EPUB and
 * epubEnable throws "Publication not opened cannot enable epub" — the failure a
 * host app hits by mounting the reader after the publication closed. The
 * dispose case seeds an audiobook instead, so the mount succeeds and only
 * cancellation reaches the handler.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
internal class ReadiumReaderWidgetEnableFailureTest {

    private val testDispatcher = UnconfinedTestDispatcher()
    private val uncaught = mutableListOf<Throwable>()
    private var previousHandler: Thread.UncaughtExceptionHandler? = null

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
    fun enableFailureDoesNotReachTheDefaultUncaughtHandler() {
        buildReaderWidget()

        assertEquals(
            emptyList(),
            uncaught,
            "reaching the default handler is what killed the app process"
        )
    }

    @Test
    fun enableFailureReportsAnErrorStatus() {
        val statuses = subscribeToReaderStatus()

        buildReaderWidget()

        assertEquals(listOf("loading", "error"), statuses)
    }

    @Test
    fun enableFailureReportsAnErrorEvent() {
        val errors = subscribeToErrorEvents()

        buildReaderWidget()

        assertEquals(1, errors.size)
        val errorEvent = errors.single()
        assertEquals("Publication not opened cannot enable epub", errorEvent["message"])
        assertEquals("ReaderFailure", errorEvent["code"])
    }

    @Test
    fun disposeAfterASuccessfulMountReportsNothing() {
        setReaderField("_currentPublication", publicationConformingTo(Publication.Profile.AUDIOBOOK))
        val statuses = subscribeToReaderStatus()
        val errors = subscribeToErrorEvents()
        val widget = buildReaderWidget()

        widget.dispose()

        assertEquals(listOf("loading", "ready", "closed"), statuses)
        assertTrue(errors.isEmpty(), "cancelling a scope is not a failure")
    }
}
