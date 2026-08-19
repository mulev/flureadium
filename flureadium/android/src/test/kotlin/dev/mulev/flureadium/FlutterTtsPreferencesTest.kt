package dev.mulev.flureadium

import android.os.Build
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.json.JSONObject
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Unit tests for FlutterTtsPreferences JSON parsing.
 *
 * Robolectric is not decoration here: it resolves AOSP's `org.json` out of the
 * android-all jar, and AOSP is where `optString("language", null)` answers with
 * the four characters `null` for a JSON-null value. Under the plain JVM
 * classpath the JSON-java library returns the fallback, so the JSON-null case
 * below would pass against the bug it exists to catch. See
 * `docs/05-testing/native-unit-tests.md`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
internal class FlutterTtsPreferencesTest {

    @Test
    fun fromJSON_parsesLanguageWhenPresent() {
        val prefs = FlutterTtsPreferences.fromJSON(JSONObject("""{"language":"en-US"}"""))

        assertEquals("en-US", prefs.language)
    }

    @Test
    fun fromJSON_returnsNullLanguageWhenKeyAbsent() {
        val prefs = FlutterTtsPreferences.fromJSON(JSONObject())

        assertNull(prefs.language)
    }

    @Test
    fun fromJSON_returnsNullLanguageWhenKeyIsJsonNull() {
        val prefs = FlutterTtsPreferences.fromJSON(JSONObject("""{"language":null}"""))

        assertNull(prefs.language)
    }

    @Test
    fun fromJSON_emptyJsonKeepsNeighbouringDefaults() {
        val prefs = FlutterTtsPreferences.fromJSON(JSONObject())

        assertNull(prefs.pitch)
        assertNull(prefs.speed)
        assertNull(prefs.voices)
        assertEquals(ControlPanelInfoType.STANDARD, prefs.controlPanelInfoType)
    }

    @Test
    fun fromJSON_parsesEveryFieldOfAFullPayload() {
        val json = JSONObject(
            """
            {
              "language": "nb-NO",
              "pitch": 1.2,
              "speed": 0.9,
              "voices": {"nb": "voice-id"},
              "controlPanelInfoType": "chapterTitle"
            }
            """.trimIndent()
        )

        val prefs = FlutterTtsPreferences.fromJSON(json)

        assertEquals("nb-NO", prefs.language)
        assertEquals(1.2, prefs.pitch)
        assertEquals(0.9, prefs.speed)
        assertEquals(mapOf("nb" to "voice-id"), prefs.voices)
        assertEquals(ControlPanelInfoType.CHAPTER_TITLE, prefs.controlPanelInfoType)
    }

    @Test
    fun toJSONThenFromJSON_roundTripsNullLanguage() {
        val original = FlutterTtsPreferences(language = null, pitch = 1.0)

        val restored = FlutterTtsPreferences.fromJSON(FlutterTtsPreferences.toJSON(original))

        assertNull(restored.language)
        assertEquals(1.0, restored.pitch)
    }
}
