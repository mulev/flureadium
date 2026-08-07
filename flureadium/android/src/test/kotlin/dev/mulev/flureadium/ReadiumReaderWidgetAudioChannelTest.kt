package dev.mulev.flureadium

import android.os.Build
import dev.mulev.flureadium.navigators.EpubNavigator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
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

    // Stands in for Android's kill handler: a throw that still reaches the
    // thread's default handler is what used to take the process down.
    private val uncaught = mutableListOf<Throwable>()
    private var previousHandler: Thread.UncaughtExceptionHandler? = null

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        resetReaderState()
        setReaderField("_currentPublication", publicationConformingTo(Publication.Profile.AUDIOBOOK))
        previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { _, throwable -> uncaught.add(throwable) }
    }

    @AfterTest
    fun tearDown() {
        Thread.setDefaultUncaughtExceptionHandler(previousHandler)
        Dispatchers.resetMain()
        resetReaderState()
    }

    // MARK: - Queries

    @Test
    fun getLocatorFragmentsEchoesItsArgument() {
        val widget = buildReaderWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("getLocatorFragments", LOCATOR_JSON), result)

        assertEquals(LOCATOR_JSON, result.value, "no DOM to resolve a fragment against")
    }

    @Test
    fun isReaderReadyIsTrue() {
        val widget = buildReaderWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("isReaderReady", null), result)

        assertEquals(true, result.value)
    }

    @Test
    fun isLocatorVisibleIsFalse() {
        val widget = buildReaderWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("isLocatorVisible", LOCATOR_JSON), result)

        assertEquals(false, result.value, "nothing is on screen, so no locator is visible")
    }

    @Test
    fun getCurrentLocatorIsNull() {
        val widget = buildReaderWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("getCurrentLocator", null), result)

        assertTrue(result.succeeded)
        assertNull(result.value, "an audio host must not report a locator from a previous EPUB")
    }

    // MARK: - No-ops

    @Test
    fun navigationAndStylingCallsAreSilentNoOps() {
        val statuses = subscribeToReaderStatus()
        val widget = buildReaderWidget()
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
        val widget = buildReaderWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("dispose", null), result)

        assertTrue(result.succeeded)
        assertEquals("closed", statuses.last(), "a host waiting on status must see the reader close")
    }

    // MARK: - Unknown methods

    @Test
    fun unknownMethodIsNotImplemented() {
        val widget = buildReaderWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("somethingElse", null), result)

        assertTrue(result.notImplemented, "an unknown method must reach Dart's MissingPluginException")
        assertFalse(result.succeeded)
    }

    // MARK: - Failures

    @Test
    fun aMalformedGoCallRepliesAnError() {
        val widget = buildReaderWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("go", listOf("not-json", true, false)), result)

        assertEquals(1, result.errorCount, "an unparseable payload must answer Dart exactly once")
        assertNotNull(result.errorCode, "a Dart PlatformException needs a code")
        assertNotNull(result.errorDetails, "the stack trace is what makes the failure diagnosable")
        assertFalse(result.succeeded, "a failed call must not also look like a success")
    }

    @Test
    fun aMalformedGoCallDoesNotReachTheDefaultUncaughtHandler() {
        val widget = buildReaderWidget()

        widget.onMethodCall(MethodCall("go", listOf("not-json", true, false)), RecordingResult())

        assertEquals(emptyList(), uncaught, "reaching the default handler is what killed the process")
    }

    @Test
    fun aSucceedingCallStillReplies() {
        val widget = buildReaderWidget()
        val result = RecordingResult()

        widget.onMethodCall(MethodCall("isReaderReady", null), result)

        assertEquals(true, result.value)
        assertTrue(result.succeeded)
        assertEquals(0, result.errorCount, "the guard must not answer a call that already succeeded")
    }

    @Test
    fun aCallCancelledMidFlightIsNotAnswered() {
        // The case the guard rethrows for: Flutter disposes the platform view
        // while a call is still in flight, so the call unwinds with the scope's
        // CancellationException. Answering it would hand the host a phantom
        // PlatformException on a future it has already dropped, and reporting it
        // would flip a torn-down reader to "error".
        val navigator = mock(EpubNavigator::class.java)
        setReaderField("epubNavigator", navigator)
        val statuses = subscribeToReaderStatus()
        val errors = subscribeToErrorEvents()
        val widget = buildReaderWidget()
        val result = RecordingResult()
        doAnswer {
            widget.dispose()
            throw CancellationException("platform view disposed mid-call")
        }.`when`(navigator).clearPendingScrollTarget()

        widget.onMethodCall(MethodCall("go", listOf(LOCATOR_JSON, false, false)), result)

        assertFalse(result.succeeded, "a cancelled call has nobody left to answer")
        assertEquals(0, result.errorCount, "cancellation must not surface as a PlatformException")
        assertTrue(errors.isEmpty(), "cancelling a call is not a failure")
        assertFalse(statuses.contains("error"), "teardown must not flip the reader to error")
        assertEquals(emptyList(), uncaught)
    }

    // MARK: - Harness

    /** Records what the widget answers, so a missing answer is distinguishable from a null one. */
    private class RecordingResult : MethodChannel.Result {
        var value: Any? = null
        var succeeded = false
        var errorCode: String? = null
        var errorMessage: String? = null
        var errorDetails: Any? = null
        var errorCount = 0
        var notImplemented = false

        override fun success(result: Any?) {
            value = result
            succeeded = true
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            this.errorCode = errorCode
            this.errorMessage = errorMessage
            this.errorDetails = errorDetails
            errorCount++
        }

        override fun notImplemented() {
            notImplemented = true
        }
    }

    private companion object {
        const val LOCATOR_JSON = """{"href":"track1.mp3","type":"audio/mpeg"}"""
    }
}
