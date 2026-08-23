package dev.mulev.flureadium

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Unit tests for the string contract of [ControlPanelInfoType].
 *
 * The saved-state path writes this enum with `?.toString()` and reads it back
 * through [ControlPanelInfoType.Companion.fromString], so the two must speak
 * the same spelling — the one Dart sends over the method channel. No case here
 * depends on the JSON-null differences between JSON-java and AOSP's `org.json`,
 * so no Robolectric runner is needed.
 */
internal class ControlPanelInfoTypeTest {

    @Test
    fun toString_returnsFlutterSpellingForEveryConstant() {
        assertEquals("standard", ControlPanelInfoType.STANDARD.toString())
        assertEquals("standardWCh", ControlPanelInfoType.STANDARD_WCH.toString())
        assertEquals("chapterTitleAuthor", ControlPanelInfoType.CHAPTER_TITLE_AUTHOR.toString())
        assertEquals("chapterTitle", ControlPanelInfoType.CHAPTER_TITLE.toString())
        assertEquals("titleChapter", ControlPanelInfoType.TITLE_CHAPTER.toString())
    }

    @Test
    fun fromString_roundTripsEveryConstant() {
        ControlPanelInfoType.entries.forEach { type ->
            assertEquals(type, ControlPanelInfoType.fromString(type.toString()))
        }
    }

    @Test
    fun fromString_unknownValueFallsBackToStandard() {
        assertEquals(ControlPanelInfoType.STANDARD, ControlPanelInfoType.fromString("CHAPTER_TITLE"))
        assertEquals(ControlPanelInfoType.STANDARD, ControlPanelInfoType.fromString("bogus"))
    }

    @Test
    fun ttsPreferences_roundTripKeepsChapterTitle() {
        val original = FlutterTtsPreferences(controlPanelInfoType = ControlPanelInfoType.CHAPTER_TITLE)

        val restored = FlutterTtsPreferences.fromJSON(FlutterTtsPreferences.toJSON(original))

        assertEquals(ControlPanelInfoType.CHAPTER_TITLE, restored.controlPanelInfoType)
    }

    @Test
    fun audioPreferences_roundTripKeepsTitleChapter() {
        // toJSON drops a null key and fromJSON reads these three with getDouble,
        // which throws on a missing key, so they must be real values here.
        val original = FlutterAudioPreferences(
            volume = 1.0,
            pitch = 1.0,
            speed = 1.0,
            controlPanelInfoType = ControlPanelInfoType.TITLE_CHAPTER,
        )

        val restored = FlutterAudioPreferences.fromJSON(FlutterAudioPreferences.toJSON(original))

        assertEquals(ControlPanelInfoType.TITLE_CHAPTER, restored.controlPanelInfoType)
    }
}
