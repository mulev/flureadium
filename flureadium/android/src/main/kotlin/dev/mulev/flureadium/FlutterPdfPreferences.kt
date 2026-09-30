package dev.mulev.flureadium

import kotlinx.serialization.Serializable
import org.json.JSONObject
import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.preferences.Axis
import org.readium.r2.navigator.preferences.Configurable
import org.readium.r2.navigator.preferences.Fit

/**
 * PDF preferences for Flutter Readium.
 *
 * Maps to PDFPreferences in Flutter's reader_pdf_preferences.dart.
 */
@Serializable
data class FlutterPdfPreferences(
    val fit: FlutterPdfFit? = null,
    val scrollMode: FlutterPdfScrollMode? = null,
    val pageLayout: FlutterPdfPageLayout? = null,
    val offsetFirstPage: Boolean? = null,
) : Configurable.Preferences<FlutterPdfPreferences> {

    override fun plus(other: FlutterPdfPreferences): FlutterPdfPreferences =
        FlutterPdfPreferences(
            fit = other.fit ?: fit,
            scrollMode = other.scrollMode ?: scrollMode,
            pageLayout = other.pageLayout ?: pageLayout,
            offsetFirstPage = other.offsetFirstPage ?: offsetFirstPage
        )

    /**
     * Converts to the preference object Readium's pdfium navigator accepts.
     *
     * `PdfiumPreferences` in Readium 3.1.2 carries only `fit`, `pageSpacing`,
     * `readingProgression` and `scrollAxis` — [pageLayout] and [offsetFirstPage]
     * have no pdfium counterpart and are dropped here on purpose.
     *
     * Nulls are passed through rather than defaulted: `PdfiumSettingsResolver`
     * turns a null axis into `Axis.VERTICAL` and a null fit into the right value
     * for the resolved axis, and it is the one place that decision belongs.
     */
    fun toPdfiumPreferences(): PdfiumPreferences = PdfiumPreferences(
        fit = fit?.toReadiumFit(),
        scrollAxis = when (scrollMode) {
            FlutterPdfScrollMode.VERTICAL -> Axis.VERTICAL
            FlutterPdfScrollMode.HORIZONTAL -> Axis.HORIZONTAL
            null -> null
        },
    )

    companion object {
        /**
         * Creates FlutterPdfPreferences from a JSON string.
         */
        fun fromJSON(json: String): FlutterPdfPreferences {
            return fromJSON(JSONObject(json))
        }

        /**
         * Creates FlutterPdfPreferences from a JSON object.
         */
        fun fromJSON(jsonObject: JSONObject): FlutterPdfPreferences {
            return FlutterPdfPreferences(
                fit = if (jsonObject.has("fit") && !jsonObject.isNull("fit"))
                    FlutterPdfFit.fromString(jsonObject.getString("fit"))
                else null,
                scrollMode = if (jsonObject.has("scrollMode") && !jsonObject.isNull("scrollMode"))
                    FlutterPdfScrollMode.fromString(jsonObject.getString("scrollMode"))
                else null,
                pageLayout = if (jsonObject.has("pageLayout") && !jsonObject.isNull("pageLayout"))
                    FlutterPdfPageLayout.fromString(jsonObject.getString("pageLayout"))
                else null,
                offsetFirstPage = if (jsonObject.has("offsetFirstPage") && !jsonObject.isNull("offsetFirstPage"))
                    jsonObject.getBoolean("offsetFirstPage")
                else null
            )
        }

        /**
         * Converts FlutterPdfPreferences to a JSON object.
         */
        fun toJSON(preferences: FlutterPdfPreferences): JSONObject {
            val jsonObject = JSONObject()
            preferences.fit?.let { jsonObject.put("fit", it.toFlutterString()) }
            preferences.scrollMode?.let { jsonObject.put("scrollMode", it.toFlutterString()) }
            preferences.pageLayout?.let { jsonObject.put("pageLayout", it.toFlutterString()) }
            preferences.offsetFirstPage?.let { jsonObject.put("offsetFirstPage", it) }
            return jsonObject
        }

        /**
         * Creates FlutterPdfPreferences from a Map (from Flutter method channel).
         */
        fun fromMap(prefs: Map<*, *>?): FlutterPdfPreferences {
            if (prefs == null) return FlutterPdfPreferences()

            return FlutterPdfPreferences(
                fit = (prefs["fit"] as? String)?.let { FlutterPdfFit.fromString(it) },
                scrollMode = (prefs["scrollMode"] as? String)?.let { FlutterPdfScrollMode.fromString(it) },
                pageLayout = (prefs["pageLayout"] as? String)?.let { FlutterPdfPageLayout.fromString(it) },
                offsetFirstPage = prefs["offsetFirstPage"] as? Boolean
            )
        }
    }
}

/**
 * How a PDF page fits within the viewport.
 *
 * Maps to PDFFit enum in Flutter.
 */
@Serializable
enum class FlutterPdfFit {
    WIDTH,
    CONTAIN;

    fun toReadiumFit(): Fit = when (this) {
        WIDTH -> Fit.WIDTH
        CONTAIN -> Fit.CONTAIN
    }

    fun toFlutterString(): String = when (this) {
        WIDTH -> "width"
        CONTAIN -> "contain"
    }

    companion object {
        fun fromString(value: String): FlutterPdfFit = when (value.lowercase()) {
            "width" -> WIDTH
            "contain" -> CONTAIN
            else -> CONTAIN
        }
    }
}

/**
 * Scroll direction for PDF navigation.
 *
 * Maps to PDFScrollMode enum in Flutter.
 */
@Serializable
enum class FlutterPdfScrollMode {
    HORIZONTAL,
    VERTICAL;

    fun toFlutterString(): String = when (this) {
        HORIZONTAL -> "horizontal"
        VERTICAL -> "vertical"
    }

    companion object {
        fun fromString(value: String): FlutterPdfScrollMode = when (value.lowercase()) {
            "horizontal" -> HORIZONTAL
            "vertical" -> VERTICAL
            else -> HORIZONTAL
        }
    }
}

/**
 * Page layout mode for PDF display.
 *
 * Maps to PDFPageLayout enum in Flutter.
 */
@Serializable
enum class FlutterPdfPageLayout {
    SINGLE,
    DOUBLE,
    AUTOMATIC;

    fun toFlutterString(): String = when (this) {
        SINGLE -> "single"
        DOUBLE -> "double"
        AUTOMATIC -> "automatic"
    }

    companion object {
        fun fromString(value: String): FlutterPdfPageLayout = when (value.lowercase()) {
            "single" -> SINGLE
            "double" -> DOUBLE
            "automatic" -> AUTOMATIC
            else -> SINGLE
        }
    }
}
