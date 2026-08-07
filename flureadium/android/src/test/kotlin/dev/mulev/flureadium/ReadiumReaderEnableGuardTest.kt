package dev.mulev.flureadium

import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

/**
 * Checks that a rejected publication leaves no is-ready channel behind.
 *
 * Each *Enable used to allocate the channel before deciding whether the
 * publication could host the navigator, which left a live channel registered on
 * the singleton for a reader that never came up. That was invisible while the
 * failure killed the process; now that the process survives it, the leak would
 * outlive the failed attempt and the next open would meet it.
 */
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class ReadiumReaderEnableGuardTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        resetReaderState()
        setReaderField("_currentPublication", audioOnlyPublication())
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        resetReaderState()
    }

    @Test
    fun epubEnableOnANonEpubLeavesNoIsReadyChannel() = runTest {
        assertFailsWith<Exception> {
            ReadiumReader.epubEnable(
                initialLocator = null,
                initialPreferences = EpubPreferences(),
                messenger = mock(BinaryMessenger::class.java),
                fragmentManager = mock(FragmentManager::class.java),
                viewGroup = mock(ViewGroup::class.java),
                readerWidget = mock(ReadiumReaderWidget::class.java),
            )
        }

        assertNoIsReadyChannel()
    }

    @Test
    fun imageEnableOnANonImagePublicationLeavesNoIsReadyChannel() = runTest {
        assertFailsWith<Exception> {
            ReadiumReader.imageEnable(
                initialLocator = null,
                messenger = mock(BinaryMessenger::class.java),
                fragmentManager = mock(FragmentManager::class.java),
                viewGroup = mock(ViewGroup::class.java),
                readerWidget = mock(ReadiumReaderWidget::class.java),
            )
        }

        assertNoIsReadyChannel()
    }

    @Test
    fun pdfEnableOnANonPdfPublicationLeavesNoIsReadyChannel() = runTest {
        assertFailsWith<Exception> {
            ReadiumReader.pdfEnable(
                initialLocator = null,
                initialPreferences = FlutterPdfPreferences(),
                messenger = mock(BinaryMessenger::class.java),
                fragmentManager = mock(FragmentManager::class.java),
                viewGroup = mock(ViewGroup::class.java),
                readerWidget = mock(ReadiumReaderWidget::class.java),
            )
        }

        assertNoIsReadyChannel()
    }

    private fun assertNoIsReadyChannel() {
        assertNull(
            getReaderField("isReadyEventChannel"),
            "a rejected publication must not leave a channel registered for a reader that never came up"
        )
    }

    /**
     * A publication no visual navigator accepts: it conforms to no profile, and
     * its single reading-order link is neither HTML nor a bitmap, so it is not
     * an EPUB, not image-based and not a PDF.
     */
    private fun audioOnlyPublication(): Publication {
        val mediaType = mock(MediaType::class.java)
        val link = mock(Link::class.java)
        `when`(link.mediaType).thenReturn(mediaType)
        val publication = mock(Publication::class.java)
        `when`(publication.readingOrder).thenReturn(listOf(link))
        return publication
    }
}
