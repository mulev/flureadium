package dev.mulev.flureadium

import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

/**
 * Builds the browsable media tree that Android Auto requests from
 * [PluginMediaService] via [androidx.media3.session.MediaLibraryService.MediaLibrarySession.Callback].
 *
 * The tree is one level deep: a browsable root whose children are the
 * publication's chapters (its `readingOrder` entries). Each chapter is a
 * playable [MediaItem] whose id round-trips, through [locatorForId], to the
 * [Locator] the audiobook navigator can seek to.
 *
 * Kept free of Android Auto and service state so it is JVM-unit-testable with
 * a stubbed [Publication].
 */
@OptIn(ExperimentalReadiumApi::class)
class AudiobookBrowseTree(private val publication: Publication) {

    /** The browsable root Android Auto starts from. */
    fun rootItem(): MediaItem =
        item(
            mediaId = ROOT_ID,
            title = publication.metadata.title ?: DEFAULT_ROOT_TITLE,
            browsable = true,
            playable = false,
        )

    /** One playable item per chapter, in reading order. */
    fun children(): List<MediaItem> =
        publication.readingOrder.indices.map(::chapterItem)

    /** Resolve a single item by id, or null if the id is unknown. */
    fun mediaItemForId(mediaId: String): MediaItem? {
        if (mediaId == ROOT_ID) return rootItem()
        val index = chapterIndexForId(mediaId) ?: return null
        return chapterItem(index)
    }

    /** Map a chapter item id back to the locator the navigator can play. */
    fun locatorForId(mediaId: String): Locator? {
        val index = chapterIndexForId(mediaId) ?: return null
        return publication.locatorFromLink(publication.readingOrder[index])
    }

    /**
     * The reading-order index a chapter item id points to, or null if the id is
     * not a known chapter. This index matches the audio player's timeline index,
     * so it can drive a seek when a chapter is picked on a head unit.
     */
    fun chapterIndexForId(mediaId: String): Int? {
        val raw = mediaId.removePrefix(CHILD_ID_PREFIX)
        if (raw == mediaId) return null
        return raw.toIntOrNull()?.takeIf { it in publication.readingOrder.indices }
    }

    private fun chapterItem(index: Int): MediaItem {
        val title = publication.readingOrder[index].title ?: "$CHAPTER_FALLBACK ${index + 1}"
        return item(
            mediaId = "$CHILD_ID_PREFIX$index",
            title = title,
            browsable = false,
            playable = true,
        )
    }

    private fun item(
        mediaId: String,
        title: String,
        browsable: Boolean,
        playable: Boolean,
    ): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .setIsBrowsable(browsable)
            .setIsPlayable(playable)
            .setMediaType(
                if (browsable) {
                    MediaMetadata.MEDIA_TYPE_FOLDER_AUDIO_BOOKS
                } else {
                    MediaMetadata.MEDIA_TYPE_AUDIO_BOOK_CHAPTER
                }
            )
            .build()
        return MediaItem.Builder()
            .setMediaId(mediaId)
            .setMediaMetadata(metadata)
            .build()
    }

    companion object {
        const val ROOT_ID = "root"
        private const val CHILD_ID_PREFIX = "ch_"
        private const val CHAPTER_FALLBACK = "Chapter"
        private const val DEFAULT_ROOT_TITLE = "Audiobook"
    }
}
