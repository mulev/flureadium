package dev.mulev.flureadium.models

import dev.mulev.flureadium.navigators.TimebasedNavigator
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Serialization contract of [ReadiumTimebasedState], which is what the method
 * channel carries to Dart.
 *
 * Two properties are load-bearing, and both are about what Dart can read back.
 * An unknown duration must be *absent* from the object rather than reported as
 * zero — `AudiobookNowPlaying.copyWith` keeps its last known value on a null
 * and would pin a zero forever, freezing the scrubber at 0:00. And a known
 * duration must serialize without a decimal point, because
 * `state_model.dart` gates on `map['currentDuration'] is int` and silently
 * nulls anything else.
 */
internal class ReadiumTimebasedStateTest {

    @Test
    fun toJSON_omitsCurrentDurationWhenItIsUnknown() {
        val json = state(duration = null).toJSON()

        assertFalse(
            json.has("currentDuration"),
            "an unknown duration must be absent, not zero"
        )
    }

    @Test
    fun toJSON_keepsAKnownCurrentDuration() {
        val json = state(duration = 1001.0).toJSON()

        assertTrue(json.has("currentDuration"))
        assertEquals(1001.0, json.getDouble("currentDuration"))
    }

    @Test
    fun toJSON_serializesAWholeMillisecondDurationWithoutADecimalPoint() {
        val serialized = state(duration = 1001.0).toJSON().toString()

        assertTrue(
            serialized.contains("\"currentDuration\":1001"),
            "Dart reads the field only when it serializes as an integer: $serialized"
        )
    }

    private fun state(duration: Double?) = ReadiumTimebasedState(
        currentLocator = null,
        state = TimebasedNavigator.TimebasedState.Paused,
        currentOffset = null,
        currentBuffer = null,
        currentDuration = duration,
    )
}
