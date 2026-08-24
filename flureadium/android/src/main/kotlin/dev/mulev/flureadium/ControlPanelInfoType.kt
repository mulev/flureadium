package dev.mulev.flureadium

enum class ControlPanelInfoType {
    STANDARD,
    STANDARD_WCH,
    CHAPTER_TITLE_AUTHOR,
    CHAPTER_TITLE,
    TITLE_CHAPTER;

    /**
     * The Flutter spelling of this value — the same string Dart sends over the
     * method channel and the only form [Companion.fromString] can read back.
     */
    override fun toString(): String = when (this) {
        STANDARD -> "standard"
        STANDARD_WCH -> "standardWCh"
        CHAPTER_TITLE_AUTHOR -> "chapterTitleAuthor"
        CHAPTER_TITLE -> "chapterTitle"
        TITLE_CHAPTER -> "titleChapter"
    }

    companion object {
        fun fromString(value: String): ControlPanelInfoType = when (value) {
            "standard" -> STANDARD
            "standardWCh" -> STANDARD_WCH
            "chapterTitleAuthor" -> CHAPTER_TITLE_AUTHOR
            "chapterTitle" -> CHAPTER_TITLE
            "titleChapter" -> TITLE_CHAPTER
            else -> STANDARD
        }
    }
}
