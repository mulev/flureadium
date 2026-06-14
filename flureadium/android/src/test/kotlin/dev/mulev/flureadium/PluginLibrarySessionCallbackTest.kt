package dev.mulev.flureadium

import android.os.Build
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Covers the Android Auto glue in [PluginLibrarySessionCallback]: serving the
 * browse tree and, crucially, turning a head-unit chapter pick into a seek on
 * the already-loaded audiobook timeline (rather than replacing the playlist).
 */
@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class PluginLibrarySessionCallbackTest {

    private fun publicationWith(chapterTitles: List<String?>): Publication {
        val publication = mock(Publication::class.java)
        val metadata = mock(Metadata::class.java)
        `when`(metadata.title).thenReturn("My Audiobook")
        `when`(publication.metadata).thenReturn(metadata)

        val links = chapterTitles.map { title ->
            val link = mock(Link::class.java)
            `when`(link.title).thenReturn(title)
            `when`(publication.locatorFromLink(link)).thenReturn(mock(Locator::class.java))
            link
        }
        `when`(publication.readingOrder).thenReturn(links)
        return publication
    }

    private fun callbackWith(publication: Publication?) =
        PluginLibrarySessionCallback(publicationProvider = { publication })

    private val session = mock(MediaLibrarySession::class.java)
    private val browser = mock(MediaSession.ControllerInfo::class.java)

    @Test
    fun commandButtons_exposeRewindAndForward() {
        val callback = callbackWith(null)

        assertEquals(2, callback.commandButtons.size)
    }

    @Test
    fun onGetLibraryRoot_withOpenPublication_returnsAudiobookRoot() {
        val callback = callbackWith(publicationWith(listOf("One", "Two")))

        val root = callback.onGetLibraryRoot(session, browser, null).get().value!!

        assertEquals(AudiobookBrowseTree.ROOT_ID, root.mediaId)
        assertEquals("My Audiobook", root.mediaMetadata.title)
        assertEquals(true, root.mediaMetadata.isBrowsable)
    }

    @Test
    fun onGetLibraryRoot_withNoPublication_returnsEmptyBrowsableRoot() {
        val callback = callbackWith(null)

        val root = callback.onGetLibraryRoot(session, browser, null).get().value!!

        assertEquals(AudiobookBrowseTree.ROOT_ID, root.mediaId)
        assertEquals(true, root.mediaMetadata.isBrowsable)
    }

    @Test
    fun onGetChildren_ofRoot_returnsOneItemPerChapter() {
        val callback = callbackWith(publicationWith(listOf("One", "Two", "Three")))

        val children = callback.onGetChildren(
            session, browser, AudiobookBrowseTree.ROOT_ID, 0, 100, null
        ).get().value!!

        assertEquals(3, children.size)
    }

    @Test
    fun onGetChildren_ofNonRoot_returnsEmpty() {
        val callback = callbackWith(publicationWith(listOf("One", "Two")))

        val children = callback.onGetChildren(
            session, browser, "ch_0", 0, 100, null
        ).get().value!!

        assertTrue(children.isEmpty())
    }

    @Test
    fun onGetItem_knownChapterId_returnsThatChapter() {
        val callback = callbackWith(publicationWith(listOf("One", "Two")))

        val item = callback.onGetItem(session, browser, "ch_1").get().value!!

        assertEquals("ch_1", item.mediaId)
        assertEquals("Two", item.mediaMetadata.title)
    }

    @Test
    fun onGetItem_unknownId_returnsBadValueError() {
        val callback = callbackWith(publicationWith(listOf("One")))

        val result = callback.onGetItem(session, browser, "ch_999").get()

        assertEquals(LibraryResult.RESULT_ERROR_BAD_VALUE, result.resultCode)
    }

    @Test
    fun onSetMediaItems_chapterPick_seeksToChapterIndexKeepingTimeline() {
        val callback = callbackWith(publicationWith(listOf("One", "Two", "Three")))

        val mediaSession = mock(MediaSession::class.java)
        val player = mock(Player::class.java)
        `when`(mediaSession.player).thenReturn(player)
        val timelineItems = listOf(
            MediaItem.Builder().setMediaId("track0").build(),
            MediaItem.Builder().setMediaId("track1").build(),
            MediaItem.Builder().setMediaId("track2").build(),
        )
        `when`(player.mediaItemCount).thenReturn(timelineItems.size)
        timelineItems.forEachIndexed { index, item ->
            `when`(player.getMediaItemAt(index)).thenReturn(item)
        }

        val picked = mutableListOf(MediaItem.Builder().setMediaId("ch_2").build())
        val result = callback.onSetMediaItems(mediaSession, browser, picked, 0, 0L).get()

        // Seeks to the picked chapter's reading-order index, keeping the player's
        // existing timeline rather than replacing it with the single browse item.
        assertEquals(2, result.startIndex)
        assertEquals(timelineItems, result.mediaItems)
    }
}
