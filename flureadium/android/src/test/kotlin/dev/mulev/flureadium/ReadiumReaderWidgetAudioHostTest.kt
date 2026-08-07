package dev.mulev.flureadium

import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertSame

/**
 * Tests that an audio-only publication can host the reader widget: the widget
 * mounts with no visual navigator, and its teardown releases only what it
 * registered.
 *
 * Seeds the ReadiumReader singleton and mounts the widget through
 * ReaderTestHarness.kt. Dispatchers.setMain with an unconfined test dispatcher
 * makes the widget's init coroutine run inline during construction, so both
 * assertions hold as soon as the constructor returns.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
internal class ReadiumReaderWidgetAudioHostTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        resetReaderState()
        setReaderField("_currentPublication", publicationConformingTo(Publication.Profile.AUDIOBOOK))
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        resetReaderState()
    }

    @Test
    fun audioHostDoesNotSetUpEpubNavigatorMachinery() {
        buildReaderWidget()

        assertNull(getReaderField("isReadyEventChannel"))
    }

    @Test
    fun audioHostDisposeKeepsNewerWidgetRegistration() {
        val audioWidget = buildReaderWidget()
        val newerWidget = mock(ReadiumReaderWidget::class.java)
        ReadiumReader.currentReaderWidget = newerWidget

        audioWidget.dispose()

        assertSame(newerWidget, ReadiumReader.currentReaderWidget)
    }

    @Test
    fun audioHostReportsLoadingThenReady() {
        val statuses = subscribeToReaderStatus()

        buildReaderWidget()

        assertEquals(listOf("loading", "ready"), statuses)
    }

    @Test
    fun activeAudioHostDisposeClearsItsRegistration() {
        val audioWidget = buildReaderWidget()

        audioWidget.dispose()

        assertNull(ReadiumReader.currentReaderWidget)
    }

}
