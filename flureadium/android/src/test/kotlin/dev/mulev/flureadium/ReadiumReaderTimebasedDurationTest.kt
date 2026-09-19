package dev.mulev.flureadium

import android.os.Build
import dev.mulev.flureadium.models.ReadiumTimebasedState
import dev.mulev.flureadium.navigators.TimebasedNavigator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * What the timebased duration looks like by the time it reaches Flutter.
 *
 * The reading order carries a duration in seconds, so this path multiplies by
 * 1000 — and a seconds value that itself came from `millis / 1000.0` does not
 * survive the round trip exactly (1001 ms becomes 1000.9999999999999). Dart
 * gates on `map['currentDuration'] is int`, so an unrounded double is dropped
 * on the floor and the scrubber never learns the track length. A track with no
 * declared duration must arrive as null rather than zero, for the same reason.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class ReadiumReaderTimebasedDurationTest {

    // ReadiumReader's initializer builds a CoroutineScope on Dispatchers.Main,
    // so the singleton cannot be touched until a Main dispatcher is installed.
    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    // The singleton outlives this class, so every flow seeded here is cleared
    // again — a stale duration would leak into the other reader tests.
    @AfterTest
    fun tearDown() {
        listOf(
            "currentTimebasedState",
            "currentTimebasedDuration",
            "currentTimebasedOffset",
            "currentTimebasedBuffer",
            "currentTimebasedLocator",
        ).forEach { clearReaderFlow(it) }
        ReadiumReader.ttsErrorType = null
        Dispatchers.resetMain()
    }

    @Test
    fun onTimebasedCurrentLocatorChanges_roundsDurationToWholeMilliseconds() = runTest {
        val state = emitState(trackLink(duration = 1001 / 1000.0))

        assertEquals(1001.0, state.currentDuration)
    }

    @Test
    fun onTimebasedCurrentLocatorChanges_reportsAnUnknownDurationAsNull() = runTest {
        val state = emitState(trackLink(duration = null))

        assertNull(state.currentDuration, "an unknown duration must not be coerced to zero")
    }

    private suspend fun emitState(link: Link): ReadiumTimebasedState {
        ReadiumReader.onTimebasedPlaybackStateChanged(TimebasedNavigator.TimebasedState.Paused)
        ReadiumReader.onTimebasedCurrentLocatorChanges(locator(), link)

        return ReadiumReader.createCurrentTimebasedReaderState().first { it != null }!!
    }

    private fun trackLink(duration: Double?) =
        Link(href = Href(Url("t1.mp3")!!), mediaType = MediaType.MP3, duration = duration)

    private fun locator() = Locator(href = Url("t1.mp3")!!, mediaType = MediaType.MP3)

    @Suppress("UNCHECKED_CAST")
    private fun clearReaderFlow(name: String) {
        (getReaderField(name) as MutableStateFlow<Any?>).value = null
    }
}
