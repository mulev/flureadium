package dev.mulev.flureadium.models

import dev.mulev.flureadium.navigators.TimebasedNavigator
import org.json.JSONObject
import org.readium.r2.shared.JSONable
import org.readium.r2.shared.publication.Locator

/**
 * State of a timebased navigator to be sent to the Flutter side
 */
data class ReadiumTimebasedState(
    /**
     * Current timebased locator
     */
    val currentLocator: Locator?,

    /**
     *  Current state of the timebased navigator
     */
    val state: TimebasedNavigator.TimebasedState,

    /**
     *  Current offset in milliseconds
     */
    val currentOffset: Double?,

    /**
     *  Current buffered position in milliseconds
     */
    val currentBuffer: Long?,

    /**
     *  Current duration in milliseconds, or `null` when the platform does not
     *  know it. Absent from the JSON rather than reported as zero — matching
     *  ReadiumTimeBasedState.swift, which writes the key only `if let`.
     */
    val currentDuration: Double?,

    /**
     *  TTS error type when state is Failure (null otherwise)
     */
    val ttsErrorType: String? = null
) : JSONable {
    /**
     * Convert to JSON object
     */
    override fun toJSON(): JSONObject = JSONObject().apply {
        put("currentLocator", currentLocator?.toJSON())
        put("state", state.name)
        put("currentOffset", currentOffset)
        put("currentBuffer", currentBuffer)
        put("currentDuration", currentDuration)
        if (ttsErrorType != null) {
            put("ttsErrorType", ttsErrorType)
        }
    }
}
