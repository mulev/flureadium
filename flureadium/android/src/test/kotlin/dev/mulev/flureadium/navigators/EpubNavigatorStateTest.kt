package dev.mulev.flureadium.navigators

import android.os.Bundle
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import org.json.JSONException
import org.json.JSONObject
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Pins the saved-state bundle an EPUB navigator survives process death with:
 * what a round trip preserves, what an absent key decodes to, and what a
 * corrupt one does today.
 *
 * No navigator is constructed here — the codec is the whole subject.
 *
 * Robolectric is required because Bundle is an Android type and Locator.fromJSON
 * builds a Readium Url, which calls android.net.Uri.parse.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@OptIn(ExperimentalReadiumApi::class)
internal class EpubNavigatorStateTest {

    private fun locator(): Locator =
        Locator.fromJSON(
            JSONObject(
                """
                {
                  "href": "chapter1.xhtml",
                  "type": "application/xhtml+xml",
                  "locations": { "progression": 0.42 }
                }
                """.trimIndent()
            )
        )!!

    private val preferences = EpubPreferences(fontSize = 1.4, scroll = true)

    @Test
    fun roundTripsLocatorAndPreferences() {
        val locator = locator()

        val restored = EpubNavigatorState.fromBundle(
            EpubNavigatorState.toBundle(locator, preferences)
        )

        assertEquals(locator, restored.locator)
        assertEquals(preferences, restored.preferences)
    }

    @Test
    fun roundTripsPreferencesWithoutALocator() {
        val restored = EpubNavigatorState.fromBundle(
            EpubNavigatorState.toBundle(null, preferences)
        )

        assertNull(restored.locator)
        assertEquals(preferences, restored.preferences)
    }

    @Test
    fun roundTripsALocatorWithoutPreferences() {
        val locator = locator()

        val restored = EpubNavigatorState.fromBundle(
            EpubNavigatorState.toBundle(locator, null)
        )

        assertEquals(locator, restored.locator)
        assertEquals(EpubPreferences(), restored.preferences)
    }

    @Test
    fun decodesAnEmptyBundleToDefaults() {
        val restored = EpubNavigatorState.fromBundle(Bundle())

        assertNull(restored.locator)
        assertEquals(EpubPreferences(), restored.preferences)
    }

    @Test
    fun decodesABundleWhoseLocatorKeyIsAbsent() {
        val bundle = Bundle().apply {
            putString(
                EpubNavigatorState.PREFERENCES_KEY,
                """{"fontSize":1.4,"scroll":true}"""
            )
        }

        val restored = EpubNavigatorState.fromBundle(bundle)

        assertNull(restored.locator)
        assertEquals(preferences, restored.preferences)
    }

    /**
     * Known gap, deliberately pinned rather than blessed: a corrupt locator string
     * crashes the decode during activity recreation instead of costing only the
     * position. The hardening bead owns the fix; this test is what it flips.
     */
    @Test
    fun malformedLocatorThrows_knownGap_seeHardeningBead() {
        val bundle = Bundle().apply {
            putString(EpubNavigatorState.LOCATOR_KEY, "{ not json")
        }

        assertFailsWith<JSONException> { EpubNavigatorState.fromBundle(bundle) }
    }

    /**
     * The key strings are the contract with bundles already written to user
     * devices: rename one and every saved position out there is orphaned.
     */
    @Test
    fun keepsTheBundleKeysStable() {
        assertEquals("currentVisualCurrentLocator", EpubNavigatorState.LOCATOR_KEY)
        assertEquals("epubPreferences", EpubNavigatorState.PREFERENCES_KEY)

        val locator = locator()
        val bundle = EpubNavigatorState.toBundle(locator, preferences)

        assertEquals(
            locator.toJSON().toString(),
            bundle.getString("currentVisualCurrentLocator")
        )
        assertEquals(
            """{"fontSize":1.4,"scroll":true}""",
            bundle.getString("epubPreferences")
        )
    }
}
