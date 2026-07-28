package dev.mulev.flureadium.car

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Covers the lenient map decoders on the car value types: a well-formed map
 * decodes with defaults applied, and a payload missing or blanking a required
 * field returns null so a malformed row is dropped rather than crashing.
 */
internal class CarContentModelsTest {

    @Test
    fun carBrowseNode_decodesFullMap() {
        val node = CarBrowseNode.fromMap(
            mapOf(
                "id" to "book:1",
                "title" to "Dune",
                "subtitle" to "Frank Herbert",
                "artworkPath" to "file:///dune.jpg",
                "kind" to "audiobook",
                "isPlayable" to true,
                "progress" to 0.5,
                "isNowPlaying" to true,
            ),
        )

        assertEquals("book:1", node?.id)
        assertEquals("Dune", node?.title)
        assertEquals("Frank Herbert", node?.subtitle)
        assertEquals(CarNodeKind.audiobook, node?.kind)
        assertEquals(true, node?.isPlayable)
        assertEquals(0.5, node?.progress)
        assertEquals(true, node?.isNowPlaying)
    }

    @Test
    fun carBrowseNode_appliesDefaultsForAbsentOptionalFields() {
        val node = CarBrowseNode.fromMap(mapOf("id" to "g:1", "title" to "Sci-Fi", "kind" to "container"))

        assertEquals(false, node?.isPlayable)
        assertNull(node?.progress)
        assertEquals(false, node?.isNowPlaying)
    }

    @Test
    fun carBrowseNode_isNull_whenRequiredFieldMissingOrKindUnknown() {
        assertNull(CarBrowseNode.fromMap(mapOf("title" to "x", "kind" to "audiobook")))
        assertNull(CarBrowseNode.fromMap(mapOf("id" to "x", "kind" to "audiobook")))
        assertNull(CarBrowseNode.fromMap(mapOf("id" to "", "title" to "x", "kind" to "audiobook")))
        assertNull(CarBrowseNode.fromMap(mapOf("id" to "x", "title" to "y", "kind" to "nope")))
    }

    @Test
    fun carTab_decodesAndRejectsBlankIdOrTitle() {
        assertEquals(CarTab("library", "Library", null), CarTab.fromMap(mapOf("id" to "library", "title" to "Library")))
        assertNull(CarTab.fromMap(mapOf("id" to "", "title" to "Library")))
        assertNull(CarTab.fromMap(mapOf("id" to "library", "title" to "")))
    }

    @Test
    fun carContentStrings_decodesAndRejectsMissingOrBlankField() {
        val full = mapOf(
            "emptyRootTitle" to "a",
            "emptyRootSubtitle" to "b",
            "voiceUnavailable" to "c",
            "offline" to "d",
        )
        assertEquals("a", CarContentStrings.fromMap(full)?.emptyRootTitle)
        assertNull(CarContentStrings.fromMap(full - "offline"))
        assertNull(CarContentStrings.fromMap(full + ("voiceUnavailable" to "")))
    }
}
