package dev.mulev.flureadium

import android.os.Build
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import dev.mulev.flureadium.car.CarBrowseNode
import dev.mulev.flureadium.car.CarContentSource
import dev.mulev.flureadium.car.CarContentStrings
import dev.mulev.flureadium.car.CarNodeKind
import dev.mulev.flureadium.car.CarTab
import dev.mulev.flureadium.car.NodeBrowseTree
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
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
 * Covers the generalized Android Auto glue in [PluginLibrarySessionCallback]:
 * serving the browse tree and search from a [CarContentSource] (not a single
 * publication), showing a status row on an empty tree, forwarding a library-node
 * pick to the provider, and still seeking the open audiobook when a chapter is
 * picked.
 */
@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class PluginLibrarySessionCallbackTest {

    private class StubCarContentSource(
        val tabs: List<CarTab> = emptyList(),
        val childrenByParent: Map<String, List<CarBrowseNode>> = emptyMap(),
        val searchResults: List<CarBrowseNode> = emptyList(),
        val stringsValue: CarContentStrings? = null,
    ) : CarContentSource {
        val played = mutableListOf<String>()
        val searched = mutableListOf<String>()

        override fun rootTabs(): ListenableFuture<List<CarTab>> = Futures.immediateFuture(tabs)

        override fun children(nodeId: String): ListenableFuture<List<CarBrowseNode>> =
            Futures.immediateFuture(childrenByParent[nodeId].orEmpty())

        override fun search(query: String): ListenableFuture<List<CarBrowseNode>> {
            searched.add(query)
            return Futures.immediateFuture(searchResults)
        }

        override fun strings(): ListenableFuture<CarContentStrings?> =
            Futures.immediateFuture(stringsValue)

        override fun play(nodeId: String) {
            played.add(nodeId)
        }

        var bookmarks = 0

        override fun addBookmark() {
            bookmarks++
        }
    }

    private fun node(id: String, title: String, kind: CarNodeKind = CarNodeKind.audiobook, playable: Boolean = true) =
        CarBrowseNode(
            id = id,
            title = title,
            subtitle = null,
            artworkPath = null,
            kind = kind,
            isPlayable = playable,
            progress = null,
            isNowPlaying = false,
        )

    private fun strings() = CarContentStrings(
        emptyRootTitle = "Nothing to play yet",
        emptyRootSubtitle = "Add books to see them here",
        voiceUnavailable = "This voice is not installed",
        offline = "This book needs a connection",
    )

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

    private fun callback(
        source: CarContentSource? = null,
        publication: Publication? = null,
    ) = PluginLibrarySessionCallback(
        sourceProvider = { source },
        publicationProvider = { publication },
    )

    private val session = mock(MediaLibrarySession::class.java)
    private val browser = mock(MediaSession.ControllerInfo::class.java)

    @Test
    fun commandButtons_exposeRewindForwardAndBookmark() {
        assertEquals(3, callback().commandButtons.size)
    }

    @Test
    fun onCustomCommand_bookmark_routesToSourceAddBookmark() {
        val source = StubCarContentSource()

        val result = callback(source).onCustomCommand(
            session,
            browser,
            SessionCommand("BOOKMARK_CUSTOM", Bundle()),
            Bundle(),
        ).get()

        assertEquals(SessionResult.RESULT_SUCCESS, result.resultCode)
        assertEquals(1, source.bookmarks)
    }

    @Test
    fun onCustomCommand_unrelatedCommand_doesNotBookmark() {
        val source = StubCarContentSource()

        val result = callback(source).onCustomCommand(
            session,
            browser,
            SessionCommand("SOMETHING_ELSE", Bundle()),
            Bundle(),
        ).get()

        assertEquals(SessionResult.RESULT_SUCCESS, result.resultCode)
        assertEquals(0, source.bookmarks)
    }

    @Test
    fun onGetLibraryRoot_returnsBrowsableRoot() {
        val root = callback().onGetLibraryRoot(session, browser, null).get().value!!

        assertEquals(NodeBrowseTree.ROOT_ID, root.mediaId)
        assertEquals(true, root.mediaMetadata.isBrowsable)
    }

    @Test
    fun onGetChildren_ofRoot_returnsOneBrowsableItemPerTab() {
        val source = StubCarContentSource(
            tabs = listOf(
                CarTab("continue", "Continue", "play.circle"),
                CarTab("library", "Library", null),
            ),
        )

        val children = callback(source).onGetChildren(
            session, browser, NodeBrowseTree.ROOT_ID, 0, 100, null,
        ).get().value!!

        assertEquals(2, children.size)
        assertEquals("continue", children[0].mediaId)
        assertEquals(true, children[0].mediaMetadata.isBrowsable)
    }

    @Test
    fun onGetChildren_ofRoot_emptyTabsWithStrings_returnsStatusRow() {
        val source = StubCarContentSource(tabs = emptyList(), stringsValue = strings())

        val children = callback(source).onGetChildren(
            session, browser, NodeBrowseTree.ROOT_ID, 0, 100, null,
        ).get().value!!

        assertEquals(1, children.size)
        assertEquals("Nothing to play yet", children[0].mediaMetadata.title)
        assertEquals(false, children[0].mediaMetadata.isPlayable)
        assertEquals(false, children[0].mediaMetadata.isBrowsable)
    }

    @Test
    fun onGetChildren_ofRoot_emptyTabsNoStrings_returnsEmpty() {
        val source = StubCarContentSource(tabs = emptyList(), stringsValue = null)

        val children = callback(source).onGetChildren(
            session, browser, NodeBrowseTree.ROOT_ID, 0, 100, null,
        ).get().value!!

        assertTrue(children.isEmpty())
    }

    @Test
    fun onGetChildren_ofContainer_returnsProviderNodeItems() {
        val source = StubCarContentSource(
            childrenByParent = mapOf(
                "genre:sci-fi" to listOf(node("book:dune", "Dune")),
            ),
        )

        val children = callback(source).onGetChildren(
            session, browser, "genre:sci-fi", 0, 100, null,
        ).get().value!!

        assertEquals(1, children.size)
        assertEquals("book:dune", children[0].mediaId)
        assertEquals(true, children[0].mediaMetadata.isPlayable)
    }

    @Test
    fun onGetChildren_withNoSource_returnsEmpty() {
        val children = callback(source = null).onGetChildren(
            session, browser, NodeBrowseTree.ROOT_ID, 0, 100, null,
        ).get().value!!

        assertTrue(children.isEmpty())
    }

    @Test
    fun onGetSearchResult_returnsMatchingProviderNodes() {
        val source = StubCarContentSource(searchResults = listOf(node("book:dune", "Dune")))

        val results = callback(source).onGetSearchResult(
            session, browser, "weir", 0, 100, null,
        ).get().value!!

        assertEquals(1, results.size)
        assertEquals("book:dune", results[0].mediaId)
    }

    @Test
    fun onSearch_runsQueryAndSucceeds() {
        val source = StubCarContentSource(searchResults = listOf(node("book:dune", "Dune")))

        val result = callback(source).onSearch(session, browser, "weir", null).get()

        assertEquals(LibraryResult.RESULT_SUCCESS, result.resultCode)
        assertTrue(source.searched.contains("weir"))
        // Android Auto needs the result-count notification to fetch the results.
        verify(session).notifySearchResultChanged(browser, "weir", 1, null)
    }

    @Test
    fun onSetMediaItems_libraryNodePick_forwardsPlayToSource() {
        val source = StubCarContentSource()
        val mediaSession = mock(MediaSession::class.java)
        val picked = mutableListOf(MediaItem.Builder().setMediaId("book:dune").build())

        val result = callback(source, publication = null)
            .onSetMediaItems(mediaSession, browser, picked, 0, 0L).get()

        assertTrue(source.played.contains("book:dune"))
        assertEquals("book:dune", result.mediaItems.single().mediaId)
    }

    @Test
    fun onSetMediaItems_chapterPick_seeksToChapterIndexKeepingTimeline() {
        val callback = callback(
            source = StubCarContentSource(),
            publication = publicationWith(listOf("One", "Two", "Three")),
        )

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

        assertEquals(2, result.startIndex)
        assertEquals(timelineItems, result.mediaItems)
    }
}
