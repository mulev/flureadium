package dev.mulev.flureadium

import android.content.ContextWrapper
import android.os.Build
import androidx.fragment.app.FragmentActivity
import dev.mulev.flureadium.events.EpubIsReadyEventChannel
import dev.mulev.flureadium.events.ReaderStatusEventChannel
import dev.mulev.flureadium.navigators.EpubNavigator
import dev.mulev.flureadium.navigators.ImageNavigator
import dev.mulev.flureadium.navigators.PdfNavigator
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame

/**
 * Tests that clearing the reader-widget registration is the disposing widget's
 * own identity-guarded decision, never a side effect of publication teardown.
 *
 * Flutter creates a replacement platform view before it disposes the one it
 * replaces, so a stale widget's dispose() routinely arrives after a newer
 * widget has already registered itself in ReadiumReader.currentReaderWidget. A
 * stale dispose must therefore release nothing that is shared.
 *
 * The "active" cases are the other half of the same rule and pass both before
 * and after the fix: they pin the single-widget lifecycle so a future guard
 * cannot buy stale-safety by skipping teardown altogether.
 *
 * No real navigator is ever constructed. Every *Enable short-circuits on
 * `navigator?.let { attach…; return@withScope }`, so pre-seeding the field by
 * reflection is enough, and the whole suite runs on the JVM with no device.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
internal class ReadiumReaderTeardownOwnershipTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        resetReaderState()
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        resetReaderState()
    }

    // A publication-scoped close releases the navigator it owns and leaves the
    // widget registration to whoever owns that.

    @Test
    fun epubCloseLeavesWidgetRegistrationAlone() {
        val navigator = mock(EpubNavigator::class.java)

        closeLeavesRegistrationAlone("epubNavigator", navigator) { ReadiumReader.epubClose() }

        verify(navigator).dispose()
    }

    @Test
    fun imageCloseLeavesWidgetRegistrationAlone() {
        val navigator = mock(ImageNavigator::class.java)

        closeLeavesRegistrationAlone("imageNavigator", navigator) { ReadiumReader.imageClose() }

        verify(navigator).dispose()
    }

    @Test
    fun pdfCloseLeavesWidgetRegistrationAlone() {
        val navigator = mock(PdfNavigator::class.java)

        closeLeavesRegistrationAlone("pdfNavigator", navigator) { ReadiumReader.pdfClose() }

        verify(navigator).dispose()
    }

    // A widget that no longer owns the registration releases nothing shared.

    @Test
    fun staleEpubWidgetDisposeKeepsNewerRegistration() {
        val navigator = mock(EpubNavigator::class.java)

        staleDisposeKeepsNewerRegistration(Publication.Profile.EPUB, "epubNavigator", navigator)

        verify(navigator, never()).dispose()
    }

    @Test
    fun staleImageWidgetDisposeKeepsNewerRegistration() {
        val navigator = mock(ImageNavigator::class.java)

        staleDisposeKeepsNewerRegistration(Publication.Profile.DIVINA, "imageNavigator", navigator)

        verify(navigator, never()).dispose()
    }

    @Test
    fun stalePdfWidgetDisposeKeepsNewerRegistration() {
        val navigator = mock(PdfNavigator::class.java)

        staleDisposeKeepsNewerRegistration(Publication.Profile.PDF, "pdfNavigator", navigator)

        verify(navigator, never()).dispose()
    }

    // The widget that still owns the registration performs the full teardown.

    @Test
    fun activeEpubWidgetDisposeReleasesEverything() {
        val navigator = mock(EpubNavigator::class.java)

        val statuses = activeDisposeReleasesEverything(Publication.Profile.EPUB, "epubNavigator", navigator)

        verify(navigator).dispose()
        assertEquals(listOf("loading", "closed"), statuses)
    }

    @Test
    fun activeImageWidgetDisposeReleasesEverything() {
        val navigator = mock(ImageNavigator::class.java)

        val statuses = activeDisposeReleasesEverything(Publication.Profile.DIVINA, "imageNavigator", navigator)

        verify(navigator).dispose()
        assertEquals(listOf("loading", "closed"), statuses)
    }

    @Test
    fun activePdfWidgetDisposeReleasesEverything() {
        val navigator = mock(PdfNavigator::class.java)

        val statuses = activeDisposeReleasesEverything(Publication.Profile.PDF, "pdfNavigator", navigator)

        verify(navigator).dispose()
        assertEquals(listOf("loading", "closed"), statuses)
    }

    @Test
    fun detachDisposesIsReadyEventChannel() {
        setReaderField("isReadyEventChannel", EpubIsReadyEventChannel(mock(BinaryMessenger::class.java)))

        ReadiumReader.detach()

        assertNull(getReaderField("isReadyEventChannel"))
    }

    // detach() clears the widget registration itself, so the mounted widget's
    // identity-guarded dispose() can no longer release anything shared, and the
    // closePublication() detach() launches suspends inside each navigator's
    // release() and is cancelled by the cancelChildren() at the end of detach().
    // Engine teardown therefore has to release the navigators itself, on the
    // synchronous path: dispose(), not release().

    @Test
    fun detachDisposesEpubNavigatorSynchronously() {
        val navigator = mock(EpubNavigator::class.java)

        detachDisposesNavigator("epubNavigator", navigator)

        verify(navigator).dispose()
    }

    @Test
    fun detachDisposesImageNavigatorSynchronously() {
        val navigator = mock(ImageNavigator::class.java)

        detachDisposesNavigator("imageNavigator", navigator)

        verify(navigator).dispose()
    }

    @Test
    fun detachDisposesPdfNavigatorSynchronously() {
        val navigator = mock(PdfNavigator::class.java)

        detachDisposesNavigator("pdfNavigator", navigator)

        verify(navigator).dispose()
    }

    private fun detachDisposesNavigator(navigatorField: String, navigator: Any) {
        setReaderField(navigatorField, navigator)

        ReadiumReader.detach()

        assertNull(getReaderField(navigatorField))
    }

    private fun closeLeavesRegistrationAlone(navigatorField: String, navigator: Any, close: () -> Unit) {
        setReaderField(navigatorField, navigator)
        val widget = mock(ReadiumReaderWidget::class.java)
        ReadiumReader.currentReaderWidget = widget

        close()

        assertSame(widget, ReadiumReader.currentReaderWidget)
        assertNull(getReaderField(navigatorField))
    }

    private fun staleDisposeKeepsNewerRegistration(
        profile: Publication.Profile,
        navigatorField: String,
        navigator: Any
    ) {
        setReaderField("_currentPublication", publicationConformingTo(profile))
        setReaderField(navigatorField, navigator)
        val staleWidget = buildWidget()
        val isReadyChannel = assertNotNull(getReaderField("isReadyEventChannel"))
        val newerWidget = mock(ReadiumReaderWidget::class.java)
        ReadiumReader.currentReaderWidget = newerWidget

        staleWidget.dispose()

        assertSame(newerWidget, ReadiumReader.currentReaderWidget)
        assertSame(navigator, getReaderField(navigatorField))
        assertSame(isReadyChannel, getReaderField("isReadyEventChannel"))
    }

    private fun activeDisposeReleasesEverything(
        profile: Publication.Profile,
        navigatorField: String,
        navigator: Any
    ): List<String> {
        setReaderField("_currentPublication", publicationConformingTo(profile))
        setReaderField(navigatorField, navigator)
        val statuses = subscribeToReaderStatus()
        val widget = buildWidget()

        widget.dispose()

        assertNull(ReadiumReader.currentReaderWidget)
        assertNull(getReaderField(navigatorField))
        assertNull(getReaderField("isReadyEventChannel"))
        return statuses
    }

    private fun resetReaderState() {
        setReaderField("_currentPublication", null)
        setReaderField("epubNavigator", null)
        setReaderField("imageNavigator", null)
        setReaderField("pdfNavigator", null)
        setReaderField("isReadyEventChannel", null)
        setReaderField("readerStatusEventChannel", null)
        ReadiumReader.currentReaderWidget = null
    }

    /** Attaches a listener to the reader-status channel and records what it receives. */
    private fun subscribeToReaderStatus(): List<String> {
        val received = mutableListOf<String>()
        val channel = ReaderStatusEventChannel(mock(BinaryMessenger::class.java))
        setReaderField("readerStatusEventChannel", channel)
        channel.onListen(
            null,
            object : EventChannel.EventSink {
                override fun success(event: Any?) {
                    received.add(event as String)
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

                override fun endOfStream() = Unit
            }
        )
        return received
    }

    private fun buildWidget(): ReadiumReaderWidget {
        val activity = Robolectric.buildActivity(FragmentActivity::class.java).setup().get()
        return ReadiumReaderWidget(
            ContextWrapper(activity),
            1,
            emptyMap(),
            mock(BinaryMessenger::class.java)
        )
    }

    private fun publicationConformingTo(profile: Publication.Profile): Publication {
        val publication = mock(Publication::class.java)
        `when`(publication.conformsTo(profile)).thenReturn(true)
        return publication
    }
}
