package dev.mulev.flureadium.events

import dev.mulev.flureadium.resetReaderState
import dev.mulev.flureadium.setReaderField
import dev.mulev.flureadium.subscribeToErrorEvents
import dev.mulev.flureadium.subscribeToReaderStatus
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.mockito.Mockito.mock
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Every event channel shares one scope in [EventChannelWrapper], and a send that
 * throws inside it used to reach Android's kill handler — the same way a failed
 * navigator enable did before flureadium-2xw.
 *
 * What a channel failure must *not* do is report itself. Reporting sends on the
 * reader-status and error channels, so a channel reporting its own failure sends
 * again, fails again, and never stops. The send is dispatched rather than
 * nested, so that loop spins forever instead of overflowing the stack: the
 * second case here is a hang if the handler ever starts reporting.
 */
@OptIn(ExperimentalCoroutinesApi::class)
internal class EventChannelFailureTest {

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
    fun aFailedSendDoesNotReachTheDefaultUncaughtHandler() {
        ThrowingChannel().sendEvent("the sink blew up")

        assertTrue(uncaught.isEmpty(), "a channel failure must not reach Android's kill handler")
    }

    @Test
    fun aFailedSendIsNotReportedThroughTheChannelsThatWouldCarryIt() {
        val statuses = subscribeToReaderStatus()
        val errors = subscribeToErrorEvents()

        ThrowingChannel().sendEvent("the sink blew up")

        assertTrue(statuses.isEmpty(), "reporting a channel failure would send through a channel")
        assertTrue(errors.isEmpty(), "reporting a channel failure would send through a channel")
    }

    @Test
    fun aFailingSinkIsAttemptedOnceAndNotRetriedForever() {
        val errorChannel = ErrorEventChannel(mock(BinaryMessenger::class.java))
        val sink = ThrowingSink()
        errorChannel.onListen(null, sink)
        setReaderField("errorEventChannel", errorChannel)

        errorChannel.sendEvent(mapOf("message" to "boom"))

        assertEquals(1, sink.attempts, "a failed send must not be re-sent by the handler")
        assertTrue(uncaught.isEmpty(), "the failure is logged, not thrown at the process")
    }

    /** A channel whose send fails, which is the only thing this suite needs one for. */
    private class ThrowingChannel :
        EventChannelWrapper<String>(mock(BinaryMessenger::class.java), "dev.mulev.flureadium/test") {
        override fun sendEvent(data: String) {
            mainScope.launch { throw IllegalStateException(data) }
        }
    }

    /** A sink that fails the way a codec rejection does, and counts the attempts. */
    private class ThrowingSink : EventChannel.EventSink {
        var attempts = 0

        override fun success(event: Any?) {
            attempts++
            throw IllegalArgumentException("cannot encode")
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

        override fun endOfStream() = Unit
    }
}
