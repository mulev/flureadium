package dev.mulev.flureadium

import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Try
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * Verifies that openPublication(AbsoluteUrl) serializes concurrent opens behind a
 * single mutex. While the mutex is held, even a fast-path (already-cached) open
 * suspends instead of running the load/release/reassign body, and it completes
 * once the mutex is released. This proves different-URL opens cannot interleave
 * the singleton state transition either, since they all wait on the same lock.
 *
 * Uses reflection to read the private openMutex and set private fields on the
 * ReadiumReader singleton (a Kotlin object).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class)
internal class ReadiumReaderOpenConcurrencyTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        setReaderField("_currentPublication", null)
        ReadiumReader.currentPublicationUrl = null
    }

    private fun setReaderField(name: String, value: Any?) {
        val field = ReadiumReader::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(ReadiumReader, value)
    }

    private fun readerMutex(): Mutex {
        val field = ReadiumReader::class.java.getDeclaredField("openMutex")
        field.isAccessible = true
        return field.get(ReadiumReader) as Mutex
    }

    @Test
    fun openPublication_serializesBehindMutex_evenOnFastPath() = runTest {
        val mockPub = mock(Publication::class.java)
        val url = AbsoluteUrl("file:///test/book.cbz")!!
        val mutex = readerMutex()

        // Prime the fast path: the same URL is already open, so the open below
        // would return immediately were it not gated by the mutex.
        setReaderField("_currentPublication", mockPub)
        ReadiumReader.currentPublicationUrl = url.toString()

        // Hold the mutex so any open must wait. Guarded in try/finally so a failed
        // assertion never leaves the singleton's mutex locked for the rest of the run.
        mutex.lock()
        var result: Try<Publication, PublicationError>? = null
        try {
            val job = launch { result = ReadiumReader.openPublication(url) }

            // Let the launched open run up to its suspension point on the mutex.
            runCurrent()
            assertFalse(
                job.isCompleted,
                "a fast-path open must suspend while the mutex is held",
            )

            // Release the mutex and let the launched open finish.
            mutex.unlock()
            advanceUntilIdle()
            assertTrue(job.isCompleted, "the open must complete once the mutex is free")
        } finally {
            if (mutex.isLocked) mutex.unlock()
        }

        assertTrue(result!!.isSuccess)
        assertSame(mockPub, result!!.getOrNull())
    }
}
