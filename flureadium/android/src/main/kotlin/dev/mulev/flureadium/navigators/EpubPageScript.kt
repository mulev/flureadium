package dev.mulev.flureadium.navigators

import android.util.Log
import dev.mulev.flureadium.jsonDecode
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator

private const val TAG = "EpubPageScript"

/**
 * Calls into `window.epubPage`, the JavaScript object the EPUB reader injects.
 *
 * [evaluate] is the navigator's own `evaluateJavascript`, and [verticalScroll] is
 * read per call because the reading mode changes under the same script object:
 * every entry point takes the flag as an argument, so a cached value would send
 * the wrong geometry after a preference change.
 */
internal class EpubPageScript(
    private val evaluate: suspend (script: String) -> String?,
    private val verticalScroll: () -> Boolean,
) {
    /** Resolves a locator's DOM fragments, or null when the page cannot answer. */
    suspend fun locatorFragments(locator: Locator): Locator? {
        val json = evaluate(
            "window.epubPage.getLocatorFragments(${locator.toJSON()}, ${verticalScroll()})"
        )
        if (json == null || json == "null" || json == "undefined") {
            Log.e(TAG, "::locatorFragments - no answer from window.epubPage")
            return null
        }

        return try {
            Locator.fromJSON(jsonDecode(json) as JSONObject)
        } catch (e: Exception) {
            Log.e(TAG, "::locatorFragments - unparseable answer: $json ($e)")
            null
        }
    }

    /** Scrolls the current page to [locations]; [toStart] pins it to the top edge. */
    suspend fun scrollTo(locations: Locator.Locations, toStart: Boolean) {
        val script =
            "window.epubPage.scrollToLocations(${locations.toJSON()},${verticalScroll()},$toStart);"
        Log.d(TAG, "::scrollTo - $script")
        evaluate(script)
    }
}
