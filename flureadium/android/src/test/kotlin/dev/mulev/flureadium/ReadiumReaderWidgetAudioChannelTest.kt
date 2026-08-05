package dev.mulev.flureadium

import android.content.ContextWrapper
import android.os.Build
import androidx.fragment.app.FragmentActivity
import dev.mulev.flureadium.events.ReaderStatusEventChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Pins what an audio-only host answers on the reader method channel.
 *
 * The answers matter more here than on a visual reader: an audio host has no
 * navigator, so most of the surface has nothing to act on. Android reaches
 * those answers a different way than iOS does — iOS routes audio to a separate
 * AudioReaderView whose cases return explicitly, while Android falls through to
 * the EPUB branch and no-ops only because every ReadiumReader.epub* accessor
 * null-guards on a navigator that was never created. Same observable contract,
 * different mechanism, so it needs its own tests rather than trusting the
 * fallthrough.
 *
 * Arguments use the real shapes Dart sends (reader_channel.dart), not nil
 * placeholders, so a branch that parses its payload is actually exercised.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
internal class ReadiumReaderWidgetAudioChannelTest {

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

    // MARK: - Queries

    @Test
    fun getLocatorFragmentsEchoesItsArgument() {
        val widget = buildAudioHostWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("getLocatorFragments", LOCATOR_JSON), result)

        assertEquals(LOCATOR_JSON, result.value, "no DOM to resolve a fragment against")
    }

    @Test
    fun isReaderReadyIsTrue() {
        val widget = buildAudioHostWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("isReaderReady", null), result)

        assertEquals(true, result.value)
    }

    @Test
    fun isLocatorVisibleIsFalse() {
        val widget = buildAudioHostWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("isLocatorVisible", LOCATOR_JSON), result)

        assertEquals(false, result.value, "nothing is on screen, so no locator is visible")
    }

    @Test
    fun getCurrentLocatorIsNull() {
        val widget = buildAudioHostWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("getCurrentLocator", null), result)

        assertTrue(result.succeeded)
        assertNull(result.value, "an audio host must not report a locator from a previous EPUB")
    }

    // MARK: - No-ops

    @Test
    fun navigationAndStylingCallsAreSilentNoOps() {
        val statuses = subscribeToReaderStatus()
        val widget = buildAudioHostWidget()
        val statusesAfterInit = statuses.size

        val calls = listOf(
            MethodCall("go", listOf(LOCATOR_JSON, false, false)),
            MethodCall("goLeft", true),
            MethodCall("goRight", true),
            MethodCall("setLocation", listOf(LOCATOR_JSON, false)),
            MethodCall("setPreferences", mapOf("verticalScroll" to "true")),
            MethodCall("setNavigationConfig", mapOf("enableEdgeTapNavigation" to true)),
            MethodCall("applyDecorations", listOf("group", emptyList<Map<String, String>>()))
        )

        for (call in calls) {
            val result = RecordingResult()
            widget.onMethodCall(call, result)
            assertTrue(result.succeeded, "${call.method} must answer the channel")
            assertNull(result.errorCode, "${call.method} must not raise: ${result.errorMessage}")
            assertNull(result.value, "${call.method} is typed Future<void> in Dart")
        }

        assertEquals(
            statusesAfterInit,
            statuses.size,
            "a no-op must not look like a state change"
        )
    }

    // MARK: - Dispose

    @Test
    fun disposeReportsClosed() {
        val statuses = subscribeToReaderStatus()
        val widget = buildAudioHostWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("dispose", null), result)

        assertTrue(result.succeeded)
        assertEquals("closed", statuses.last(), "a host waiting on status must see the reader close")
    }

    // MARK: - Unknown methods

    @Test
    fun unknownMethodIsNotImplemented() {
        val widget = buildAudioHostWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("somethingElse", null), result)

        assertTrue(result.notImplemented, "an unknown method must reach Dart's MissingPluginException")
        assertFalse(result.succeeded)
    }

    // MARK: - Harness

    /** Records what the widget answers, so a missing answer is distinguishable from a null one. */
    private class RecordingResult : MethodChannel.Result {
        var value: Any? = null
        var succeeded = false
        var errorCode: String? = null
        var errorMessage: String? = null
        var notImplemented = false

        override fun success(result: Any?) {
            value = result
            succeeded = true
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            this.errorCode = errorCode
            this.errorMessage = errorMessage
        }

        override fun notImplemented() {
            notImplemented = true
        }
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

    private companion object {
        const val LOCATOR_JSON = """{"href":"track1.mp3","type":"audio/mpeg"}"""
    }
}
