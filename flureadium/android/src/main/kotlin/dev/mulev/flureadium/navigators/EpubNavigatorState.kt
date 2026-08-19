package dev.mulev.flureadium.navigators

import android.os.Bundle
import android.util.Log
import kotlinx.serialization.json.Json
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator

private const val TAG = "EpubNavigatorState"

/**
 * The two values an EPUB navigator has to survive process death with: where the
 * reader was, and how it looked.
 *
 * Both are optional on the way in. A bundle written before the first locator
 * arrived, or one that never carried preferences, is not an error — it means
 * "open at the beginning with default preferences", which is what a missing
 * value decodes to.
 *
 * A malformed value is another matter: a corrupt locator string throws out of
 * [fromBundle] during activity recreation. That is today's behaviour, pinned by
 * a test rather than blessed — hardening it is its own change.
 */
@OptIn(ExperimentalReadiumApi::class)
internal data class EpubNavigatorState(
    val locator: Locator?,
    val preferences: EpubPreferences,
) {
    companion object {
        internal const val LOCATOR_KEY = "currentVisualCurrentLocator"
        internal const val PREFERENCES_KEY = "epubPreferences"

        fun toBundle(locator: Locator?, preferences: EpubPreferences?): Bundle =
            Bundle().apply {
                putString(LOCATOR_KEY, locator?.toJSON()?.toString())

                preferences?.let { prefs ->
                    putString(PREFERENCES_KEY, Json.encodeToString(EpubPreferences.serializer(), prefs))
                }
            }

        fun fromBundle(bundle: Bundle): EpubNavigatorState {
            val locator = bundle.getString(LOCATOR_KEY)
                ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences = bundle.getString(PREFERENCES_KEY)
                ?.let { string -> Json.decodeFromString<EpubPreferences>(string) }
                ?: EpubPreferences()

            Log.d(TAG, "::fromBundle - locator: $locator, preferences: $preferences")

            return EpubNavigatorState(locator, preferences)
        }
    }
}
