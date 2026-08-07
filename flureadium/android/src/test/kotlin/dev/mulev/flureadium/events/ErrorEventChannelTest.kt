package dev.mulev.flureadium.events

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.mockito.Mockito.mock
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Tests that an error sent before Flutter subscribes is still delivered.
 *
 * The reader widget reports a failed enable from init, which runs inside the
 * platform-view create call — before Flutter replies to Dart and therefore
 * before a host app can subscribe from onReady. Unlike reader status, an error
 * is an event and not a state, so pending errors keep their order.
 */
@OptIn(ExperimentalCoroutinesApi::class)
internal class ErrorEventChannelTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun deliversErrorSentBeforeTheFirstSubscriber() {
        val channel = ErrorEventChannel(mock(BinaryMessenger::class.java))
        val sink = RecordingSink()

        channel.sendEvent(errorMap("boom"))
        channel.onListen(null, sink)

        assertEquals(listOf(errorMap("boom")), sink.events)
    }

    @Test
    fun keepsEveryPendingErrorInOrder() {
        val channel = ErrorEventChannel(mock(BinaryMessenger::class.java))
        val sink = RecordingSink()

        channel.sendEvent(errorMap("first"))
        channel.sendEvent(errorMap("second"))
        channel.sendEvent(errorMap("third"))
        channel.onListen(null, sink)

        assertEquals(
            listOf(errorMap("first"), errorMap("second"), errorMap("third")),
            sink.events,
            "one error does not supersede another, so all of them arrive in order"
        )
    }

    @Test
    fun stopsQueueingPendingErrorsAtTheCapAndKeepsTheOldest() {
        val channel = ErrorEventChannel(mock(BinaryMessenger::class.java))
        val sink = RecordingSink()

        repeat(9) { index -> channel.sendEvent(errorMap("error $index")) }
        channel.onListen(null, sink)

        assertEquals(
            (0..7).map { index -> errorMap("error $index") },
            sink.events,
            "the cap keeps the first failures, which explain the ones that follow"
        )
    }

    @Test
    fun deliversErrorDirectlyWhileSubscribed() {
        val channel = ErrorEventChannel(mock(BinaryMessenger::class.java))
        val sink = RecordingSink()
        channel.onListen(null, sink)

        channel.sendEvent(errorMap("first"))
        channel.sendEvent(errorMap("second"))

        assertEquals(listOf(errorMap("first"), errorMap("second")), sink.events)
    }

    @Test
    fun doesNotReplayADeliveredErrorToALaterSubscriber() {
        val channel = ErrorEventChannel(mock(BinaryMessenger::class.java))
        val firstSink = RecordingSink()
        channel.onListen(null, firstSink)
        channel.sendEvent(errorMap("boom"))

        val secondSink = RecordingSink()
        channel.onListen(null, secondSink)

        assertEquals(
            emptyList(),
            secondSink.events,
            "a delivered error is drained, not retained"
        )
    }

    @Test
    fun keepsPendingErrorsWhenOnListenArrivesWithoutASink() {
        val channel = ErrorEventChannel(mock(BinaryMessenger::class.java))
        channel.sendEvent(errorMap("boom"))

        channel.onListen(null, null)

        val sink = RecordingSink()
        channel.onListen(null, sink)
        assertEquals(
            listOf(errorMap("boom")),
            sink.events,
            "there was nowhere to send the error, so it stays queued for a real subscriber"
        )
    }

    @Test
    fun dropsPendingErrorsWhenTheChannelIsDisposed() {
        val channel = ErrorEventChannel(mock(BinaryMessenger::class.java))
        val sink = RecordingSink()

        channel.sendEvent(errorMap("first"))
        channel.sendEvent(errorMap("second"))
        channel.dispose()
        channel.onListen(null, sink)

        assertEquals(
            emptyList(),
            sink.events,
            "errors held for a subscriber that never arrived belong to the session that ended"
        )
    }

    private fun errorMap(message: String): Map<String, Any?> =
        mapOf("message" to message, "code" to null, "data" to null)

    private class RecordingSink : EventChannel.EventSink {
        val events = mutableListOf<Map<String, Any?>>()

        @Suppress("UNCHECKED_CAST")
        override fun success(event: Any?) {
            events.add(event as Map<String, Any?>)
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

        override fun endOfStream() = Unit
    }
}
