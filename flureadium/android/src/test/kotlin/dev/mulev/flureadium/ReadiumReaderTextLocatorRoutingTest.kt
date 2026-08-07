package dev.mulev.flureadium

import android.os.Build
import dev.mulev.flureadium.events.TextLocatorEventChannel
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

/**
 * ReadiumReader.sendTextLocatorEvent is what every page change on every reader
 * kind calls (ReadiumReaderWidget.emitOnPageChanged), and it reaches a channel
 * that only exists between attach and detach.
 *
 * The window matters: a navigator can report a page while the reader is being
 * torn down. Sending then must be a no-op rather than a crash, and the `?.` in
 * the sender is the only thing making that true.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class)
internal class ReadiumReaderTextLocatorRoutingTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        setReaderField("textLocatorEventChannel", null)
    }

    @AfterTest
    fun tearDown() {
        setReaderField("textLocatorEventChannel", null)
        Dispatchers.resetMain()
    }

    @Test
    fun forwardsTheLocatorToTheAttachedChannel() {
        val sink = RecordingSink()
        val channel = TextLocatorEventChannel(mock(BinaryMessenger::class.java))
        channel.onListen(null, sink)
        setReaderField("textLocatorEventChannel", channel)

        ReadiumReader.sendTextLocatorEvent(locator("chapter1.xhtml"))

        assertEquals(
            listOf("chapter1.xhtml"),
            sink.events.map { JSONObject(it as String).getString("href") }
        )
    }

    @Test
    fun isANoOpBeforeAttachAndAfterDetach() {
        // No channel: the state before ReadiumReader.attach runs, and again
        // after detach nulls the field.
        ReadiumReader.sendTextLocatorEvent(locator("chapter1.xhtml"))
    }

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
