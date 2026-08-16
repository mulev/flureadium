package dev.mulev.flureadium

import android.content.ContextWrapper
import android.os.Build
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.eq
import org.mockito.ArgumentMatchers.isNull
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.spy
import org.mockito.Mockito.verify
import org.readium.r2.shared.ExperimentalReadiumApi
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Follows one tap from the navigator callback to the bytes Dart receives.
 *
 * The chain has three hops on Android — navigator to ReadiumReader, reader to
 * the widget that still owns the view, widget to the method channel — and every
 * hop is a plain forward with no visible effect of its own. The wire payload is
 * asserted by decoding what the messenger was handed, because the keys and the
 * value type are the contract reader_channel.dart parses (`args['x'] as num`).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
internal class ReadiumReaderTapForwardingTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        resetReaderState()
    }

    @AfterTest
    fun tearDown() {
        resetReaderState()
        Dispatchers.resetMain()
    }

    @Test
    fun channelSendsCoordinatesAsAMap() {
        val channel = spy(ReadiumReaderChannel(mock(BinaryMessenger::class.java), "reader:1"))

        channel.onTap(4.0, 8.0)

        verify(channel).invokeMethod("onTap", mapOf("x" to 4.0, "y" to 8.0))
    }

    @Test
    fun readerForwardsToTheWidgetThatOwnsTheView() {
        val widget = mock(ReadiumReaderWidget::class.java)
        ReadiumReader.currentReaderWidget = widget

        ReadiumReader.onTap(4.0, 8.0)

        verify(widget).onTap(4.0, 8.0)
    }

    @Test
    fun readerIgnoresATapWithNoWidgetMounted() {
        // The window between detach and the next mount: a tap arriving then must
        // not reach the widget that is gone, and must not throw either.
        val widget = mock(ReadiumReaderWidget::class.java)
        ReadiumReader.currentReaderWidget = widget
        ReadiumReader.currentReaderWidget = null

        ReadiumReader.onTap(4.0, 8.0)

        verify(widget, never()).onTap(4.0, 8.0)
    }

    @Test
    fun widgetPostsTheTapOnItsMethodChannel() {
        val messenger = mock(BinaryMessenger::class.java)
        val activity = Robolectric.buildActivity(FragmentActivity::class.java).setup().get()
        val widget = ReadiumReaderWidget(ContextWrapper(activity), 7, emptyMap(), messenger)

        widget.onTap(4.0, 8.0)

        val payload = ArgumentCaptor.forClass(ByteBuffer::class.java)
        verify(messenger).send(
            eq("$viewTypeChannelName:7"),
            payload.capture(),
            isNull()
        )
        val sent = payload.value
        sent.rewind()
        val call = StandardMethodCodec.INSTANCE.decodeMethodCall(sent)
        assertEquals("onTap", call.method)
        assertEquals(mapOf("x" to 4.0, "y" to 8.0), call.arguments)
    }
}
