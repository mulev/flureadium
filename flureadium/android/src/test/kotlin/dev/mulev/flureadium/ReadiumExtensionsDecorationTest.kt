package dev.mulev.flureadium

import android.os.Build
import androidx.core.graphics.toColorInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue
import org.junit.runner.RunWith
import org.readium.r2.navigator.Decoration
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
internal class ReadiumExtensionsDecorationTest {

    // The payload Dart sends, element for element:
    // flureadium/lib/reader_channel.dart:126-129 -> ReaderDecoration.toJson()
    private fun dartDecoration(
        id: Any? = "highlight-1",
        locator: Any? = dartLocator(),
        style: Any? = mapOf("style" to "highlight", "tint" to "#FFFFFF00"),
    ): Map<String, Any> = buildMap {
        id?.let { put("id", it) }
        locator?.let { put("locator", it) }
        style?.let { put("style", it) }
    }

    private fun dartLocator(): Map<String, Any> = mapOf(
        "href" to "/chapter1.xhtml",
        "type" to "application/xhtml+xml",
        "locations" to mapOf("progression" to 0.25),
        "text" to mapOf("highlight" to "decorated words"),
    )

    @Test
    fun decorationFromMap_decodesTheDartPayload() {
        val decoration = decorationFromMap(dartDecoration())

        assertEquals("highlight-1", decoration.id)
        assertEquals("/chapter1.xhtml", decoration.locator.href.toString())
        val style = assertIs<Decoration.Style.Highlight>(decoration.style)
        assertEquals("#FFFFFF00".toColorInt(), style.tint)
    }

    @Test
    fun decorationFromMap_keepsNestedLocatorFields() {
        val decoration = decorationFromMap(dartDecoration())

        assertEquals(0.25, decoration.locator.locations.progression)
        assertEquals("decorated words", decoration.locator.text.highlight)
    }

    @Test
    fun decorationFromMap_decodesUnderlineStyle() {
        val decoration = decorationFromMap(
            dartDecoration(style = mapOf("style" to "underline", "tint" to "#FFFFFF00"))
        )

        val style = assertIs<Decoration.Style.Underline>(decoration.style)
        assertEquals("#FFFFFF00".toColorInt(), style.tint)
    }

    @Test
    fun decorationFromMap_fallsBackToHighlightForUnknownStyle() {
        val decoration = decorationFromMap(
            dartDecoration(style = mapOf("style" to "sparkle", "tint" to "#FFFFFF00"))
        )

        assertIs<Decoration.Style.Highlight>(decoration.style)
    }

    @Test
    fun decorationFromMap_throwsWhenIdIsMissing() {
        val error = assertFailsWith<IllegalArgumentException> {
            decorationFromMap(dartDecoration(id = null))
        }

        assertTrue(error.message!!.contains("/chapter1.xhtml"))
    }

    @Test
    fun decorationFromMap_throwsWhenLocatorIsMissing() {
        val error = assertFailsWith<IllegalArgumentException> {
            decorationFromMap(dartDecoration(locator = null))
        }

        assertTrue(error.message!!.contains("highlight-1"))
    }

    @Test
    fun decorationFromMap_throwsWhenLocatorIsAString() {
        val error = assertFailsWith<IllegalArgumentException> {
            decorationFromMap(dartDecoration(locator = """{"href":"/chapter1.xhtml"}"""))
        }

        assertTrue(error.message!!.contains("highlight-1"))
    }

    @Test
    fun decorationFromMap_throwsWhenLocatorHasNoHref() {
        val error = assertFailsWith<IllegalArgumentException> {
            decorationFromMap(dartDecoration(locator = emptyMap<String, Any>()))
        }

        assertTrue(error.message!!.contains("highlight-1"))
    }

    @Test
    fun decorationFromMap_throwsWhenTintIsNotCssParseable() {
        val error = assertFailsWith<IllegalArgumentException> {
            decorationFromMap(
                dartDecoration(style = mapOf("style" to "highlight", "tint" to "rebeccapurple"))
            )
        }

        assertTrue(error.message!!.contains("highlight-1"))
    }
}
