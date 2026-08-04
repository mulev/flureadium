package dev.mulev.flureadium

import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * Tests that openPublication() returns the cached publication when called
 * with the same URL that is already open, skipping loadPublication().
 *
 * Uses reflection to set private fields on the ReadiumReader singleton.
 * Without the cache check, loadPublication() would be called and fail
 * because Readium infrastructure is not initialized in unit tests.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class)
internal class ReadiumReaderSamePubCacheTest {

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

    @Test
    fun openPublication_sameUrl_returnsCachedPublication() = runTest {
        val mockPub = mock(Publication::class.java)
        val url = AbsoluteUrl("file:///test/book.cbz")!!

        setReaderField("_currentPublication", mockPub)
        ReadiumReader.currentPublicationUrl = url.toString()

        val result = ReadiumReader.openPublication(url)

        assertTrue(result.isSuccess)
        assertSame(mockPub, result.getOrNull())
    }

    @Test
    fun openPublication_differentUrl_doesNotUseCachedPublication() = runTest {
        val mockPub = mock(Publication::class.java)
        val cachedUrl = AbsoluteUrl("file:///test/book1.cbz")!!
        val newUrl = AbsoluteUrl("file:///test/book2.cbz")!!

        setReaderField("_currentPublication", mockPub)
        ReadiumReader.currentPublicationUrl = cachedUrl.toString()

        // Different URL → cache miss → loadPublication fails (no Readium infra)
        val result = ReadiumReader.openPublication(newUrl)

        assertFalse(result.isSuccess)
    }

    @Test
    fun openPublication_noCurrentPublication_doesNotUseCachedPublication() = runTest {
        val url = AbsoluteUrl("file:///test/book.cbz")!!

        // No current publication set → cache miss → loadPublication fails
        val result = ReadiumReader.openPublication(url)

        assertFalse(result.isSuccess)
    }
}
