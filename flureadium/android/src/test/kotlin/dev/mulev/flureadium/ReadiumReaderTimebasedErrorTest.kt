package dev.mulev.flureadium

import dev.mulev.flureadium.events.ErrorEventChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.readium.r2.shared.ExperimentalReadiumApi
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test

/**
 * Verifies that a timebased (audiobook/TTS) playback failure reported by the
 * native player is forwarded to Flutter's onErrorEvent stream. Without this,
 * a failed streaming load (e.g. an unreachable host) stalls silently at 0:00
 * with nothing surfaced to the client — the gap covered by the audiobook
 * integration test "unreachable streamed audio surfaces an error event".
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class ReadiumReaderTimebasedErrorTest {

    // ReadiumReader's initializer builds a CoroutineScope on Dispatchers.Main,
    // so the singleton cannot be touched until a Main dispatcher is installed.
    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    private fun setReaderField(name: String, value: Any?) {
        val field = ReadiumReader::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(ReadiumReader, value)
    }

    @AfterTest
    fun tearDown() {
        setReaderField("errorEventChannel", null)
        Dispatchers.resetMain()
    }

    @Test
    fun onTimebasedPlaybackFailure_forwardsMessageAndTimebasedCodeToErrorChannel() {
        val channel = mock(ErrorEventChannel::class.java)
        setReaderField("errorEventChannel", channel)

        ReadiumReader.onTimebasedPlaybackFailure(PublicationError.Unknown("boom"))

        verify(channel).sendEvent(
            mapOf("message" to "boom", "code" to "TimebasedError", "data" to "unknown")
        )
    }
}
