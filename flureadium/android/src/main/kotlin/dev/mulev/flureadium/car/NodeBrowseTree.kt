package dev.mulev.flureadium.car

import android.net.Uri
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaConstants

/**
 * Maps car browse content — root, tabs, provider nodes, and the empty-state
 * status row — into media3 [MediaItem]s for the Android Auto browse tree.
 *
 * Stateless and free of Android Auto/service state so it is JVM-unit-testable
 * with plain [CarBrowseNode]/[CarTab] values (see `NodeBrowseTreeTest`). Node
 * ids round-trip verbatim as media ids, so a selection can be handed back to the
 * host's provider by id.
 */
@UnstableApi
object NodeBrowseTree {
    const val ROOT_ID = "root"

    /** The browsable root the head unit starts from, carrying [title] when shown. */
    fun rootItem(title: String?): MediaItem =
        browsableItem(mediaId = ROOT_ID, title = title, subtitle = null)

    /** One browsable row per root tab (Continue / Library / Search). */
    fun tabItems(tabs: List<CarTab>): List<MediaItem> =
        tabs.map { browsableItem(mediaId = it.id, title = it.title, subtitle = null) }

    /**
     * One row per provider node, playable or browsable per its kind. A `siri`
     * node is an iOS CarPlay assistant-cell marker with no Android Auto browse
     * equivalent (voice search is Google Assistant, not a browse row), so it is
     * dropped rather than shown as a dead row.
     */
    fun nodeItems(nodes: List<CarBrowseNode>): List<MediaItem> =
        nodes.filter { it.kind != CarNodeKind.siri }.map(::nodeItem)

    /** A non-selectable status row shown when the tree is empty. */
    fun statusItem(title: String, subtitle: String?): MediaItem =
        item(
            mediaId = "status:$title",
            title = title,
            subtitle = subtitle,
            browsable = false,
            playable = false,
            mediaType = MediaMetadata.MEDIA_TYPE_MIXED,
            artworkPath = null,
            progress = null,
        )

    private fun nodeItem(node: CarBrowseNode): MediaItem {
        val browsable = node.kind == CarNodeKind.container || node.kind == CarNodeKind.tab
        val mediaType = when {
            browsable -> MediaMetadata.MEDIA_TYPE_FOLDER_AUDIO_BOOKS
            node.kind == CarNodeKind.chapter -> MediaMetadata.MEDIA_TYPE_AUDIO_BOOK_CHAPTER
            else -> MediaMetadata.MEDIA_TYPE_AUDIO_BOOK
        }
        return item(
            mediaId = node.id,
            title = node.title,
            subtitle = node.subtitle,
            browsable = browsable,
            playable = node.isPlayable,
            mediaType = mediaType,
            artworkPath = node.artworkPath,
            progress = node.progress,
        )
    }

    private fun browsableItem(mediaId: String, title: String?, subtitle: String?): MediaItem =
        item(
            mediaId = mediaId,
            title = title,
            subtitle = subtitle,
            browsable = true,
            playable = false,
            mediaType = MediaMetadata.MEDIA_TYPE_FOLDER_AUDIO_BOOKS,
            artworkPath = null,
            progress = null,
        )

    private fun item(
        mediaId: String,
        title: String?,
        subtitle: String?,
        browsable: Boolean,
        playable: Boolean,
        mediaType: Int,
        artworkPath: String?,
        progress: Double?,
    ): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setIsBrowsable(browsable)
            .setIsPlayable(playable)
            .setMediaType(mediaType)
            .apply {
                artworkPath?.let { setArtworkUri(Uri.parse(it)) }
                completionExtras(progress)?.let { setExtras(it) }
            }
            .build()
        return MediaItem.Builder()
            .setMediaId(mediaId)
            .setMediaMetadata(metadata)
            .build()
    }

    /**
     * The browse extras carrying listening progress, or null when there is none.
     * Android Auto reads [MediaConstants.EXTRAS_KEY_COMPLETION_PERCENTAGE] as a
     * float in `0..100`, so the node's `0..1` fraction is scaled up.
     */
    private fun completionExtras(progress: Double?): Bundle? {
        if (progress == null) return null
        val percentage = (progress * 100.0).coerceIn(0.0, 100.0).toFloat()
        return Bundle().apply {
            putFloat(MediaConstants.EXTRAS_KEY_COMPLETION_PERCENTAGE, percentage)
        }
    }
}
