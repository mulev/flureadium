package dev.mulev.flureadium.navigators

import dev.mulev.flureadium.FlutterPdfPreferences
import dev.mulev.flureadium.fragments.EpubReaderFragment
import dev.mulev.flureadium.fragments.PdfReaderFragment
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.readium.r2.navigator.VisualNavigator
import org.readium.r2.navigator.image.ImageNavigatorFragment
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Pins where each visual navigator registers its tap listener.
 *
 * Registration cannot wait for a locator: ImageNavigator.setupNavigatorListeners
 * returns early when the CBZ has none yet, and a book opened before its first
 * locator arrives would then report no taps at all. EPUB and PDF have the
 * opposite hazard — their reader fragment drops the Readium navigator in
 * onPause() and builds a new one in onResume(), while hasNotifiedIsReady keeps
 * setupNavigatorListeners from running a second time, so the registration has to
 * follow the page-load callback that every new navigator emits.
 *
 * The expected listener is read out of the navigator's own field rather than
 * matched with any(), so each assertion pins the identity that makes removal on
 * dispose work.
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class NavigatorTapRegistrationTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // MARK: - EPUB

    @Test
    fun `epub registers when the first page loads`() {
        val readium = mock(VisualNavigator::class.java)
        val navigator = epubNavigator(epubFragment(readium))

        navigator.onPageLoaded()

        verify(readium).addInputListener(navigator.tapForwarder())
    }

    @Test
    fun `epub registers once when a second page loads`() {
        val readium = mock(VisualNavigator::class.java)
        val navigator = epubNavigator(epubFragment(readium))

        navigator.onPageLoaded()
        navigator.onPageLoaded()

        verify(readium, times(1)).addInputListener(navigator.tapForwarder())
    }

    @Test
    fun `epub moves the registration to the navigator recreated on resume`() {
        val paused = mock(VisualNavigator::class.java)
        val resumed = mock(VisualNavigator::class.java)
        val fragment = epubFragment(paused)
        val navigator = epubNavigator(fragment)
        navigator.onPageLoaded()

        `when`(fragment.visualNavigator).thenReturn(resumed)
        navigator.onPageLoaded()

        verify(paused).removeInputListener(navigator.tapForwarder())
        verify(resumed).addInputListener(navigator.tapForwarder())
    }

    @Test
    fun `epub drops the registration on dispose`() {
        val readium = mock(VisualNavigator::class.java)
        val navigator = epubNavigator(epubFragment(readium))
        navigator.onPageLoaded()

        navigator.dispose()

        verify(readium).removeInputListener(navigator.tapForwarder())
    }

    @Test
    fun `epub drops the registration on release`() = runTest {
        val readium = mock(VisualNavigator::class.java)
        val navigator = epubNavigator(epubFragment(readium))
        navigator.onPageLoaded()
        // release() is the teardown a publication swap takes, and it does not run
        // the dispose() override. Its fragment removal needs a real
        // FragmentManager, so the fragment is cleared and only the registration
        // is asserted.
        navigator.setFragmentForTest("epubNavigator", null)

        navigator.release()

        verify(readium).removeInputListener(navigator.tapForwarder())
    }

    // MARK: - PDF

    @Test
    fun `pdf registers when the first page loads`() {
        val readium = mock(VisualNavigator::class.java)
        val navigator = pdfNavigator(pdfFragment(readium))

        navigator.onPageLoaded()

        verify(readium).addInputListener(navigator.tapForwarder())
    }

    @Test
    fun `pdf moves the registration to the navigator recreated on resume`() {
        val paused = mock(VisualNavigator::class.java)
        val resumed = mock(VisualNavigator::class.java)
        val fragment = pdfFragment(paused)
        val navigator = pdfNavigator(fragment)
        navigator.onPageLoaded()

        `when`(fragment.visualNavigator).thenReturn(resumed)
        navigator.onPageLoaded()

        verify(paused).removeInputListener(navigator.tapForwarder())
        verify(resumed).addInputListener(navigator.tapForwarder())
    }

    @Test
    fun `pdf drops the registration on dispose`() {
        val readium = mock(VisualNavigator::class.java)
        val navigator = pdfNavigator(pdfFragment(readium))
        navigator.onPageLoaded()

        navigator.dispose()

        verify(readium).removeInputListener(navigator.tapForwarder())
    }

    @Test
    fun `pdf drops the registration on release`() = runTest {
        val readium = mock(VisualNavigator::class.java)
        val navigator = pdfNavigator(pdfFragment(readium))
        navigator.onPageLoaded()
        navigator.setFragmentForTest("pdfNavigator", null)

        navigator.release()

        verify(readium).removeInputListener(navigator.tapForwarder())
    }

    // MARK: - CBZ / DIVINA

    @Test
    fun `image registers even before a locator exists`() {
        val readium = mock(ImageNavigatorFragment::class.java)
        val navigator = imageNavigator(readium)

        navigator.notifyIsReadyForTest()

        verify(readium).addInputListener(navigator.tapForwarder())
    }

    @Test
    fun `image drops the registration on dispose`() {
        val readium = mock(ImageNavigatorFragment::class.java)
        val navigator = imageNavigator(readium)
        navigator.notifyIsReadyForTest()

        navigator.dispose()

        verify(readium).removeInputListener(navigator.tapForwarder())
    }

    @Test
    fun `image drops the registration on release`() = runTest {
        val readium = mock(ImageNavigatorFragment::class.java)
        val navigator = imageNavigator(readium)
        navigator.notifyIsReadyForTest()
        navigator.setFragmentForTest("imageNavigator", null)

        navigator.release()

        verify(readium).removeInputListener(navigator.tapForwarder())
    }

    // MARK: - Harness

    private fun epubFragment(readium: VisualNavigator): EpubReaderFragment {
        val fragment = mock(EpubReaderFragment::class.java)
        `when`(fragment.visualNavigator).thenReturn(readium)
        return fragment
    }

    private fun pdfFragment(readium: VisualNavigator): PdfReaderFragment {
        val fragment = mock(PdfReaderFragment::class.java)
        `when`(fragment.visualNavigator).thenReturn(readium)
        return fragment
    }

    private fun epubNavigator(fragment: EpubReaderFragment): EpubNavigator {
        val navigator = EpubNavigator(
            publication = mock(Publication::class.java),
            initialLocator = null,
            visualListener = mock(EpubNavigator.VisualListener::class.java),
        )
        navigator.setFragmentForTest("epubNavigator", fragment)
        return navigator
    }

    private fun pdfNavigator(fragment: PdfReaderFragment): PdfNavigator {
        val navigator = PdfNavigator(
            publication = mock(Publication::class.java),
            initialLocator = null,
            visualListener = mock(PdfNavigator.VisualListener::class.java),
            initialPreferences = FlutterPdfPreferences(),
        )
        navigator.setFragmentForTest("pdfNavigator", fragment)
        return navigator
    }

    private fun imageNavigator(fragment: ImageNavigatorFragment): ImageNavigator {
        val navigator = ImageNavigator(
            publication = mock(Publication::class.java),
            initialLocator = null,
            visualListener = mock(ImageNavigator.VisualListener::class.java),
        )
        navigator.setFragmentForTest("imageNavigator", fragment)
        return navigator
    }

    /** Seeds the fragment a navigator only gets from a real attach. */
    private fun BaseNavigator.setFragmentForTest(name: String, fragment: Any?) {
        javaClass.getDeclaredField(name).apply { isAccessible = true }.set(this, fragment)
    }

    /** The listener this navigator registers, so assertions can name it exactly. */
    private fun BaseNavigator.tapForwarder(): InputListener =
        javaClass.getDeclaredField("tapForwarder")
            .apply { isAccessible = true }
            .get(this) as InputListener

    /** Drives the readiness callback that ImageNavigator only reaches from attach. */
    private fun ImageNavigator.notifyIsReadyForTest() {
        ImageNavigator::class.java.getDeclaredMethod("notifyIsReady")
            .apply { isAccessible = true }
            .invoke(this)
    }
}
