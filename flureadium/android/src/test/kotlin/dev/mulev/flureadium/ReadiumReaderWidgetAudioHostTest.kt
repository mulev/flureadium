package dev.mulev.flureadium

import android.content.ContextWrapper
import android.os.Build
import androidx.fragment.app.FragmentActivity
import dev.mulev.flureadium.events.ReaderStatusEventChannel
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
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.Robolectric
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
 * Uses reflection to set private fields on the ReadiumReader singleton, the
 * same harness as ReadiumReaderSamePubCacheTest. Dispatchers.setMain with an
 * unconfined test dispatcher makes the widget's init coroutine run inline
 * during construction, so both assertions hold as soon as the constructor
 * returns.
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
        setReaderField("_currentPublication", audiobookPublication())
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        resetReaderState()
    }

    private fun resetReaderState() {
        setReaderField("_currentPublication", null)
        setReaderField("isReadyEventChannel", null)
        setReaderField("readerStatusEventChannel", null)
        ReadiumReader.currentReaderWidget = null
    }

    @Test
    fun audioHostDoesNotSetUpEpubNavigatorMachinery() {
        buildAudioHostWidget()

        assertNull(getReaderField("isReadyEventChannel"))
    }

    @Test
    fun audioHostDisposeKeepsNewerWidgetRegistration() {
        val audioWidget = buildAudioHostWidget()
        val newerWidget = mock(ReadiumReaderWidget::class.java)
        ReadiumReader.currentReaderWidget = newerWidget

        audioWidget.dispose()

        assertSame(newerWidget, ReadiumReader.currentReaderWidget)
    }

    @Test
    fun audioHostReportsLoadingThenReady() {
        val statuses = subscribeToReaderStatus()

        buildAudioHostWidget()

        assertEquals(listOf("loading", "ready"), statuses)
    }

    @Test
    fun activeAudioHostDisposeClearsItsRegistration() {
        val audioWidget = buildAudioHostWidget()

        audioWidget.dispose()

        assertNull(ReadiumReader.currentReaderWidget)
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

    private fun buildAudioHostWidget(): ReadiumReaderWidget {
        val activity = Robolectric.buildActivity(FragmentActivity::class.java).setup().get()
        return ReadiumReaderWidget(
            ContextWrapper(activity),
            1,
            emptyMap(),
            mock(BinaryMessenger::class.java)
        )
    }

    private fun audiobookPublication(): Publication {
        val publication = mock(Publication::class.java)
        `when`(publication.conformsTo(Publication.Profile.AUDIOBOOK)).thenReturn(true)
        return publication
    }

    private fun setReaderField(name: String, value: Any?) {
        val field = ReadiumReader::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(ReadiumReader, value)
    }

    private fun getReaderField(name: String): Any? {
        val field = ReadiumReader::class.java.getDeclaredField(name)
        field.isAccessible = true
        return field.get(ReadiumReader)
    }
}
