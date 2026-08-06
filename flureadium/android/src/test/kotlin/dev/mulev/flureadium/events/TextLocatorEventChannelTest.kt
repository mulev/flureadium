package dev.mulev.flureadium.events

import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.json.JSONObject
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.readium.r2.shared.publication.Locator
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The text-locator channel's delivery rules, which are deliberately not the
 * reader-status channel's.
 *
 * A locator is a log, not a state: it describes a page turn that already
 * happened. Replaying one into a later subscriber would move a reader that
 * never went there, so nothing is buffered — and that difference from
 * ReaderStatusEventChannel is asserted here so nobody "fixes" it by symmetry.
 *
 * Robolectric is needed because Locator.toJSON builds a JSONObject.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class)
internal class TextLocatorEventChannelTest {

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
    fun sendsTheLocatorAsAJsonString() {
        val channel = newChannel()
        val sink = RecordingSink()
        channel.onListen(null, sink)

        channel.sendEvent(locator("chapter1.xhtml"))

        // Dart parses this with Locator.fromJson, so the wire type is a String
        // holding JSON — not the Locator, and not a Map.
        val event = sink.events.single()
        assertTrue(event is String, "the wire type must be a JSON string, got ${event?.javaClass}")
        assertEquals("chapter1.xhtml", JSONObject(event).getString("href"))
    }

    @Test
    fun dropsALocatorSentBeforeAnyoneSubscribes() {
        val channel = newChannel()
        val sink = RecordingSink()

        channel.sendEvent(locator("chapter1.xhtml"))
        channel.onListen(null, sink)

        assertEquals(
            emptyList(),
            sink.events,
            "a page turn nobody was listening for must not replay into a later subscriber"
        )
    }

    @Test
    fun dropsALocatorSentAfterTheSubscriberCancels() {
        val channel = newChannel()
        val sink = RecordingSink()
        channel.onListen(null, sink)
        channel.onCancel(null)

        channel.sendEvent(locator("chapter2.xhtml"))

        assertEquals(emptyList(), sink.events)
    }

    @Test
    fun deliversEveryLocatorWhileSubscribed() {
        val channel = newChannel()
        val sink = RecordingSink()
        channel.onListen(null, sink)

        channel.sendEvent(locator("chapter1.xhtml"))
        channel.sendEvent(locator("chapter2.xhtml"))

        // Unlike a status, consecutive locators do not collapse: each page turn
        // is its own event.
        assertEquals(
            listOf("chapter1.xhtml", "chapter2.xhtml"),
            sink.events.map { JSONObject(it as String).getString("href") }
        )
    }

    @Test
    fun disposeStopsDelivery() {
        val channel = newChannel()
        val sink = RecordingSink()
        channel.onListen(null, sink)

        channel.dispose()
        channel.sendEvent(locator("chapter3.xhtml"))

        assertEquals(
            emptyList(),
            sink.events,
            "a channel replaced by ReadiumReader.attach must not keep writing to the old sink"
        )
    }

    private fun newChannel() = TextLocatorEventChannel(mock(BinaryMessenger::class.java))

    private fun locator(href: String) = Locator(
        href = org.readium.r2.shared.util.Url(href)!!,
        mediaType = org.readium.r2.shared.util.mediatype.MediaType.XHTML
    )

    private class RecordingSink : EventChannel.EventSink {
        val events = mutableListOf<Any?>()

        override fun success(event: Any?) {
            events.add(event)
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

        override fun endOfStream() = Unit
    }
}
