package dev.mulev.flureadium

import android.os.Build
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
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class AudiobookBrowseTreeTest {

    private fun publicationWith(
        chapterTitles: List<String?>,
        publicationTitle: String? = "My Audiobook",
    ): Pair<Publication, List<Locator>> {
        val publication = mock(Publication::class.java)
        val metadata = mock(Metadata::class.java)
        `when`(metadata.title).thenReturn(publicationTitle)
        `when`(publication.metadata).thenReturn(metadata)

        val locators = mutableListOf<Locator>()
        val links = chapterTitles.map { title ->
            val link = mock(Link::class.java)
            `when`(link.title).thenReturn(title)
            val locator = mock(Locator::class.java)
            `when`(publication.locatorFromLink(link)).thenReturn(locator)
            locators.add(locator)
            link
        }
        `when`(publication.readingOrder).thenReturn(links)
        return publication to locators
    }

    @Test
    fun rootItem_isBrowsableNotPlayable_withPublicationTitle() {
        val (publication, _) = publicationWith(listOf("One", "Two"))
        val tree = AudiobookBrowseTree(publication)

        val root = tree.rootItem()

        assertEquals(AudiobookBrowseTree.ROOT_ID, root.mediaId)
        assertEquals(true, root.mediaMetadata.isBrowsable)
        assertEquals(false, root.mediaMetadata.isPlayable)
        assertEquals("My Audiobook", root.mediaMetadata.title)
    }

    @Test
    fun children_oneItemPerReadingOrderEntry_allPlayable() {
        val (publication, _) = publicationWith(listOf("One", "Two", "Three"))
        val tree = AudiobookBrowseTree(publication)

        val children = tree.children()

        assertEquals(3, children.size)
        children.forEach { child ->
            assertEquals(false, child.mediaMetadata.isBrowsable)
            assertEquals(true, child.mediaMetadata.isPlayable)
        }
    }

    @Test
    fun children_useChapterTitle_whenPresent() {
        val (publication, _) = publicationWith(listOf("Prologue", "Chapter Two"))
        val tree = AudiobookBrowseTree(publication)

        val children = tree.children()

        assertEquals("Prologue", children[0].mediaMetadata.title)
        assertEquals("Chapter Two", children[1].mediaMetadata.title)
    }

    @Test
    fun children_fallBackToNumberedTitle_whenChapterTitleMissing() {
        val (publication, _) = publicationWith(listOf(null, null))
        val tree = AudiobookBrowseTree(publication)

        val children = tree.children()

        assertEquals("Chapter 1", children[0].mediaMetadata.title)
        assertEquals("Chapter 2", children[1].mediaMetadata.title)
    }

    @Test
    fun locatorForId_roundTripsChildMediaIdToPublicationLocator() {
        val (publication, locators) = publicationWith(listOf("One", "Two"))
        val tree = AudiobookBrowseTree(publication)

        val children = tree.children()

        assertSame(locators[0], tree.locatorForId(children[0].mediaId))
        assertSame(locators[1], tree.locatorForId(children[1].mediaId))
    }

    @Test
    fun locatorForId_returnsNull_forRootId() {
        val (publication, _) = publicationWith(listOf("One"))
        val tree = AudiobookBrowseTree(publication)

        assertNull(tree.locatorForId(AudiobookBrowseTree.ROOT_ID))
    }

    @Test
    fun locatorForId_returnsNull_forUnknownId() {
        val (publication, _) = publicationWith(listOf("One"))
        val tree = AudiobookBrowseTree(publication)

        assertNull(tree.locatorForId("ch_999"))
        assertNull(tree.locatorForId("garbage"))
    }

    @Test
    fun chapterIndexForId_roundTripsChildMediaIdToReadingOrderIndex() {
        val (publication, _) = publicationWith(listOf("One", "Two", "Three"))
        val tree = AudiobookBrowseTree(publication)

        val children = tree.children()

        assertEquals(0, tree.chapterIndexForId(children[0].mediaId))
        assertEquals(2, tree.chapterIndexForId(children[2].mediaId))
    }

    @Test
    fun chapterIndexForId_returnsNull_forRootOrUnknownId() {
        val (publication, _) = publicationWith(listOf("One"))
        val tree = AudiobookBrowseTree(publication)

        assertNull(tree.chapterIndexForId(AudiobookBrowseTree.ROOT_ID))
        assertNull(tree.chapterIndexForId("ch_999"))
        assertNull(tree.chapterIndexForId("nope"))
    }

    @Test
    fun mediaItemForId_returnsRoot_forRootId() {
        val (publication, _) = publicationWith(listOf("One"))
        val tree = AudiobookBrowseTree(publication)

        val item = tree.mediaItemForId(AudiobookBrowseTree.ROOT_ID)

        assertEquals(AudiobookBrowseTree.ROOT_ID, item?.mediaId)
        assertTrue(item?.mediaMetadata?.isBrowsable == true)
    }

    @Test
    fun mediaItemForId_returnsChild_forChildId() {
        val (publication, _) = publicationWith(listOf("One", "Two"))
        val tree = AudiobookBrowseTree(publication)

        val childId = tree.children()[1].mediaId
        val item = tree.mediaItemForId(childId)

        assertEquals(childId, item?.mediaId)
        assertEquals("Two", item?.mediaMetadata?.title)
        assertFalse(item?.mediaMetadata?.isBrowsable == true)
    }
}
