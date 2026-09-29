package dev.mulev.flureadium

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertFalse
import org.json.JSONObject
import org.readium.r2.navigator.preferences.Fit

/**
 * Unit tests for FlutterPdfPreferences and related enums.
 */
internal class FlutterPdfPreferencesTest {

    @Test
    fun fromMap_parsesAllFieldsCorrectly() {
        val map = mapOf(
            "fit" to "width",
            "scrollMode" to "vertical",
            "pageLayout" to "double",
            "offsetFirstPage" to true
        )

        val prefs = FlutterPdfPreferences.fromMap(map)

        assertEquals(FlutterPdfFit.WIDTH, prefs.fit)
        assertEquals(FlutterPdfScrollMode.VERTICAL, prefs.scrollMode)
        assertEquals(FlutterPdfPageLayout.DOUBLE, prefs.pageLayout)
        assertEquals(true, prefs.offsetFirstPage)
    }

    @Test
    fun fromMap_handlesEmptyMap() {
        val prefs = FlutterPdfPreferences.fromMap(emptyMap<String, Any>())

        assertNull(prefs.fit)
        assertNull(prefs.scrollMode)
        assertNull(prefs.pageLayout)
        assertNull(prefs.offsetFirstPage)
    }

    @Test
    fun fromMap_handlesNullMap() {
        val prefs = FlutterPdfPreferences.fromMap(null)

        assertNull(prefs.fit)
        assertNull(prefs.scrollMode)
        assertNull(prefs.pageLayout)
        assertNull(prefs.offsetFirstPage)
    }

    @Test
    fun toJSON_serializesAllFieldsCorrectly() {
        val prefs = FlutterPdfPreferences(
            fit = FlutterPdfFit.CONTAIN,
            scrollMode = FlutterPdfScrollMode.HORIZONTAL,
            pageLayout = FlutterPdfPageLayout.AUTOMATIC,
            offsetFirstPage = false
        )

        val json = FlutterPdfPreferences.toJSON(prefs)

        assertEquals("contain", json.getString("fit"))
        assertEquals("horizontal", json.getString("scrollMode"))
        assertEquals("automatic", json.getString("pageLayout"))
        assertEquals(false, json.getBoolean("offsetFirstPage"))
    }

    @Test
    fun toJSON_omitsNullFields() {
        val prefs = FlutterPdfPreferences(fit = FlutterPdfFit.WIDTH)

        val json = FlutterPdfPreferences.toJSON(prefs)

        assertTrue(json.has("fit"))
        assertFalse(json.has("scrollMode"))
        assertFalse(json.has("pageLayout"))
        assertFalse(json.has("offsetFirstPage"))
    }

    @Test
    fun fromJSON_parsesAllFieldsCorrectly() {
        val json = JSONObject().apply {
            put("fit", "contain")
            put("scrollMode", "vertical")
            put("pageLayout", "single")
            put("offsetFirstPage", true)
        }

        val prefs = FlutterPdfPreferences.fromJSON(json)

        assertEquals(FlutterPdfFit.CONTAIN, prefs.fit)
        assertEquals(FlutterPdfScrollMode.VERTICAL, prefs.scrollMode)
        assertEquals(FlutterPdfPageLayout.SINGLE, prefs.pageLayout)
        assertEquals(true, prefs.offsetFirstPage)
    }

    @Test
    fun fromJSON_handlesEmptyJson() {
        val json = JSONObject()

        val prefs = FlutterPdfPreferences.fromJSON(json)

        assertNull(prefs.fit)
        assertNull(prefs.scrollMode)
        assertNull(prefs.pageLayout)
        assertNull(prefs.offsetFirstPage)
    }

    @Test
    fun toReadiumFit_mapsCorrectly() {
        assertEquals(Fit.WIDTH, FlutterPdfFit.WIDTH.toReadiumFit())
        assertEquals(Fit.CONTAIN, FlutterPdfFit.CONTAIN.toReadiumFit())
    }

    @Test
    fun plus_mergesPreferencesCorrectly() {
        val base = FlutterPdfPreferences(
            fit = FlutterPdfFit.WIDTH,
            scrollMode = FlutterPdfScrollMode.HORIZONTAL
        )
        val override = FlutterPdfPreferences(
            scrollMode = FlutterPdfScrollMode.VERTICAL,
            pageLayout = FlutterPdfPageLayout.SINGLE
        )

        val merged = base.plus(override)

        assertEquals(FlutterPdfFit.WIDTH, merged.fit) // from base
        assertEquals(FlutterPdfScrollMode.VERTICAL, merged.scrollMode) // from override
        assertEquals(FlutterPdfPageLayout.SINGLE, merged.pageLayout) // from override
        assertNull(merged.offsetFirstPage) // both null
    }

    @Test
    fun plus_overridesAllFields() {
        val base = FlutterPdfPreferences(
            fit = FlutterPdfFit.WIDTH,
            scrollMode = FlutterPdfScrollMode.HORIZONTAL,
            pageLayout = FlutterPdfPageLayout.SINGLE,
            offsetFirstPage = true
        )
        val override = FlutterPdfPreferences(
            fit = FlutterPdfFit.CONTAIN,
            scrollMode = FlutterPdfScrollMode.VERTICAL,
            pageLayout = FlutterPdfPageLayout.DOUBLE,
            offsetFirstPage = false
        )

        val merged = base.plus(override)

        assertEquals(FlutterPdfFit.CONTAIN, merged.fit)
        assertEquals(FlutterPdfScrollMode.VERTICAL, merged.scrollMode)
        assertEquals(FlutterPdfPageLayout.DOUBLE, merged.pageLayout)
        assertEquals(false, merged.offsetFirstPage)
    }

    @Test
    fun flutterPdfFit_fromString_handlesAllValues() {
        assertEquals(FlutterPdfFit.WIDTH, FlutterPdfFit.fromString("width"))
        assertEquals(FlutterPdfFit.CONTAIN, FlutterPdfFit.fromString("contain"))
        assertEquals(FlutterPdfFit.CONTAIN, FlutterPdfFit.fromString("unknown")) // default
    }

    @Test
    fun flutterPdfFit_fromString_handlesCaseInsensitive() {
        assertEquals(FlutterPdfFit.WIDTH, FlutterPdfFit.fromString("WIDTH"))
        assertEquals(FlutterPdfFit.CONTAIN, FlutterPdfFit.fromString("Contain"))
    }

    @Test
    fun flutterPdfFit_toFlutterString_returnsCorrectValues() {
        assertEquals("width", FlutterPdfFit.WIDTH.toFlutterString())
        assertEquals("contain", FlutterPdfFit.CONTAIN.toFlutterString())
    }

    @Test
    fun flutterPdfScrollMode_fromString_handlesAllValues() {
        assertEquals(FlutterPdfScrollMode.HORIZONTAL, FlutterPdfScrollMode.fromString("horizontal"))
        assertEquals(FlutterPdfScrollMode.VERTICAL, FlutterPdfScrollMode.fromString("vertical"))
        assertEquals(FlutterPdfScrollMode.HORIZONTAL, FlutterPdfScrollMode.fromString("unknown")) // default
    }

    @Test
    fun flutterPdfScrollMode_fromString_handlesCaseInsensitive() {
        assertEquals(FlutterPdfScrollMode.HORIZONTAL, FlutterPdfScrollMode.fromString("HORIZONTAL"))
        assertEquals(FlutterPdfScrollMode.VERTICAL, FlutterPdfScrollMode.fromString("Vertical"))
    }

    @Test
    fun flutterPdfScrollMode_toFlutterString_returnsCorrectValues() {
        assertEquals("horizontal", FlutterPdfScrollMode.HORIZONTAL.toFlutterString())
        assertEquals("vertical", FlutterPdfScrollMode.VERTICAL.toFlutterString())
    }

    @Test
    fun flutterPdfPageLayout_fromString_handlesAllValues() {
        assertEquals(FlutterPdfPageLayout.SINGLE, FlutterPdfPageLayout.fromString("single"))
        assertEquals(FlutterPdfPageLayout.DOUBLE, FlutterPdfPageLayout.fromString("double"))
        assertEquals(FlutterPdfPageLayout.AUTOMATIC, FlutterPdfPageLayout.fromString("automatic"))
        assertEquals(FlutterPdfPageLayout.SINGLE, FlutterPdfPageLayout.fromString("unknown")) // default
    }

    @Test
    fun flutterPdfPageLayout_fromString_handlesCaseInsensitive() {
        assertEquals(FlutterPdfPageLayout.SINGLE, FlutterPdfPageLayout.fromString("SINGLE"))
        assertEquals(FlutterPdfPageLayout.DOUBLE, FlutterPdfPageLayout.fromString("Double"))
        assertEquals(FlutterPdfPageLayout.AUTOMATIC, FlutterPdfPageLayout.fromString("AUTOMATIC"))
    }

    @Test
    fun flutterPdfPageLayout_toFlutterString_returnsCorrectValues() {
        assertEquals("single", FlutterPdfPageLayout.SINGLE.toFlutterString())
        assertEquals("double", FlutterPdfPageLayout.DOUBLE.toFlutterString())
        assertEquals("automatic", FlutterPdfPageLayout.AUTOMATIC.toFlutterString())
    }

    @Test
    fun roundTrip_jsonToPreferencesToJson() {
        val original = FlutterPdfPreferences(
            fit = FlutterPdfFit.WIDTH,
            scrollMode = FlutterPdfScrollMode.VERTICAL,
            pageLayout = FlutterPdfPageLayout.DOUBLE,
            offsetFirstPage = true
        )

        val json = FlutterPdfPreferences.toJSON(original)
        val restored = FlutterPdfPreferences.fromJSON(json)

        assertEquals(original.fit, restored.fit)
        assertEquals(original.scrollMode, restored.scrollMode)
        assertEquals(original.pageLayout, restored.pageLayout)
        assertEquals(original.offsetFirstPage, restored.offsetFirstPage)
    }

    @Test
    fun roundTrip_mapToPreferencesToMap() {
        val originalMap = mapOf(
            "fit" to "contain",
            "scrollMode" to "horizontal",
            "pageLayout" to "automatic",
            "offsetFirstPage" to false
        )

        val prefs = FlutterPdfPreferences.fromMap(originalMap)
        val json = FlutterPdfPreferences.toJSON(prefs)

        assertEquals("contain", json.getString("fit"))
        assertEquals("horizontal", json.getString("scrollMode"))
        assertEquals("automatic", json.getString("pageLayout"))
        assertEquals(false, json.getBoolean("offsetFirstPage"))
    }
}
