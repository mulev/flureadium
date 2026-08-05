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
 * Tests that a status sent before Flutter subscribes is still delivered.
 *
 * The reader widget reports "loading" — and an audio-only host reports
 * "ready" — while the platform view is being created, which is before Flutter
 * replies to Dart and therefore before a host app can subscribe from onReady.
 */
@OptIn(ExperimentalCoroutinesApi::class)
internal class ReaderStatusEventChannelTest {

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
    fun deliversStatusSentBeforeTheFirstSubscriber() {
        val channel = ReaderStatusEventChannel(mock(BinaryMessenger::class.java))
        val sink = RecordingSink()

        channel.sendEvent("ready")
        channel.onListen(null, sink)

        assertEquals(listOf("ready"), sink.events)
    }

    @Test
    fun keepsOnlyTheLatestStatusForTheFirstSubscriber() {
        val channel = ReaderStatusEventChannel(mock(BinaryMessenger::class.java))
        val sink = RecordingSink()

        channel.sendEvent("loading")
        channel.sendEvent("ready")
        channel.onListen(null, sink)

        assertEquals(listOf("ready"), sink.events)
    }

    @Test
    fun deliversStatusDirectlyWhileSubscribed() {
        val channel = ReaderStatusEventChannel(mock(BinaryMessenger::class.java))
        val sink = RecordingSink()
        channel.onListen(null, sink)

        channel.sendEvent("loading")
        channel.sendEvent("ready")

        assertEquals(listOf("loading", "ready"), sink.events)
    }

    @Test
    fun doesNotReplayADeliveredStatusToALaterSubscriber() {
        val channel = ReaderStatusEventChannel(mock(BinaryMessenger::class.java))
        val firstSink = RecordingSink()
        channel.onListen(null, firstSink)
        channel.sendEvent("ready")

        val secondSink = RecordingSink()
        channel.onListen(null, secondSink)

        assertEquals(emptyList(), secondSink.events)
    }

    @Test
    fun buffersAgainForAStatusSentBetweenSubscriptions() {
        val channel = ReaderStatusEventChannel(mock(BinaryMessenger::class.java))
        val firstSink = RecordingSink()
        channel.onListen(null, firstSink)
        channel.onCancel(null)

        // A publication swap: Dart unsubscribes, the replacement widget reports
        // its status, then the host re-subscribes from onReady.
        channel.sendEvent("ready")
        val secondSink = RecordingSink()
        channel.onListen(null, secondSink)

        assertEquals(emptyList(), firstSink.events, "the cancelled subscriber must receive nothing")
        assertEquals(listOf("ready"), secondSink.events, "buffering resumes once the sink is cleared")
    }

    @Test
    fun disposeDropsThePendingStatus() {
        val channel = ReaderStatusEventChannel(mock(BinaryMessenger::class.java))
        val sink = RecordingSink()

        channel.sendEvent("ready")
        channel.dispose()
        channel.onListen(null, sink)

        assertEquals(
            emptyList(),
            sink.events,
            "a status buffered for a subscriber that never arrived is stale"
        )
    }

    private class RecordingSink : EventChannel.EventSink {
        val events = mutableListOf<String>()

        override fun success(event: Any?) {
            events.add(event as String)
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

        override fun endOfStream() = Unit
    }
}
