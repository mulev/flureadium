package dev.mulev.flureadium.car

import android.os.Build
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaConstants
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Covers [NodeBrowseTree]'s pure mapping from car content types to media3
 * [androidx.media3.common.MediaItem]s: playable/browsable flags, progress
 * extras, artwork, and the root/tab/status shapes the Android Auto browse tree
 * is built from.
 */
@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
internal class NodeBrowseTreeTest {

    private fun node(
        id: String = "book:1",
        title: String = "Project Hail Mary",
        subtitle: String? = "Andy Weir",
        artworkPath: String? = null,
        kind: CarNodeKind = CarNodeKind.audiobook,
        isPlayable: Boolean = true,
        progress: Double? = null,
        isNowPlaying: Boolean = false,
    ) = CarBrowseNode(
        id = id,
        title = title,
        subtitle = subtitle,
        artworkPath = artworkPath,
        kind = kind,
        isPlayable = isPlayable,
        progress = progress,
        isNowPlaying = isNowPlaying,
    )

    @Test
    fun nodeItems_playableAudiobook_isPlayableWithTitleAndSubtitle() {
        val item = NodeBrowseTree.nodeItems(listOf(node(progress = 0.62))).single()

        assertEquals("book:1", item.mediaId)
        assertEquals("Project Hail Mary", item.mediaMetadata.title)
        assertEquals("Andy Weir", item.mediaMetadata.subtitle)
        assertEquals(true, item.mediaMetadata.isPlayable)
        assertEquals(false, item.mediaMetadata.isBrowsable)
    }

    @Test
    fun nodeItems_withProgress_setsCompletionPercentageExtraOutOf100() {
        val item = NodeBrowseTree.nodeItems(listOf(node(progress = 0.62))).single()

        val extras = item.mediaMetadata.extras
        assertNotNull(extras)
        assertEquals(
            62f,
            extras.getFloat(MediaConstants.EXTRAS_KEY_COMPLETION_PERCENTAGE),
        )
    }

    @Test
    fun nodeItems_withoutProgress_setsNoCompletionExtra() {
        val item = NodeBrowseTree.nodeItems(listOf(node(progress = null))).single()

        val extras = item.mediaMetadata.extras
        assertFalse(
            extras != null &&
                extras.containsKey(MediaConstants.EXTRAS_KEY_COMPLETION_PERCENTAGE),
        )
    }

    @Test
    fun nodeItems_container_isBrowsableNotPlayable() {
        val item = NodeBrowseTree.nodeItems(
            listOf(node(id = "genre:sci-fi", title = "Science Fiction", kind = CarNodeKind.container, isPlayable = false)),
        ).single()

        assertEquals(true, item.mediaMetadata.isBrowsable)
        assertEquals(false, item.mediaMetadata.isPlayable)
    }

    @Test
    fun nodeItems_withArtworkPath_setsArtworkUri() {
        val item = NodeBrowseTree.nodeItems(
            listOf(node(artworkPath = "file:///covers/hail-mary.jpg")),
        ).single()

        assertEquals(
            "file:///covers/hail-mary.jpg",
            item.mediaMetadata.artworkUri?.toString(),
        )
    }

    @Test
    fun nodeItems_withoutArtworkPath_leavesArtworkUriNull() {
        val item = NodeBrowseTree.nodeItems(listOf(node(artworkPath = null))).single()

        assertEquals(null, item.mediaMetadata.artworkUri)
    }

    @Test
    fun tabItems_areBrowsableRowsCarryingTabIdAndTitle() {
        val items = NodeBrowseTree.tabItems(
            listOf(
                CarTab(id = "continue", title = "Continue", iconName = "play.circle"),
                CarTab(id = "library", title = "Library", iconName = null),
            ),
        )

        assertEquals(2, items.size)
        assertEquals("continue", items[0].mediaId)
        assertEquals("Continue", items[0].mediaMetadata.title)
        assertEquals(true, items[0].mediaMetadata.isBrowsable)
        assertEquals(false, items[0].mediaMetadata.isPlayable)
    }

    @Test
    fun rootItem_isBrowsableWithGivenTitle() {
        val root = NodeBrowseTree.rootItem("My Library")

        assertEquals(NodeBrowseTree.ROOT_ID, root.mediaId)
        assertEquals("My Library", root.mediaMetadata.title)
        assertEquals(true, root.mediaMetadata.isBrowsable)
        assertEquals(false, root.mediaMetadata.isPlayable)
    }

    @Test
    fun statusItem_isNeitherBrowsableNorPlayable_carryingTitleAndSubtitle() {
        val item = NodeBrowseTree.statusItem("Nothing to play yet", "Add books to see them here")

        assertEquals("Nothing to play yet", item.mediaMetadata.title)
        assertEquals("Add books to see them here", item.mediaMetadata.subtitle)
        assertEquals(false, item.mediaMetadata.isBrowsable)
        assertEquals(false, item.mediaMetadata.isPlayable)
    }

    @Test
    fun statusItem_usesMediaTypeMixed() {
        // A status row is not an audiobook; it must not claim an audiobook media type.
        val item = NodeBrowseTree.statusItem("Nothing to play yet", "Add books to see them here")

        assertEquals(MediaMetadata.MEDIA_TYPE_MIXED, item.mediaMetadata.mediaType)
    }
}
