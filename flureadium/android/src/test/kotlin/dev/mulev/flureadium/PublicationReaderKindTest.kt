package dev.mulev.flureadium

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.mediatype.MediaType

@OptIn(ExperimentalReadiumApi::class)
internal class PublicationReaderKindTest {

    @Test
    fun `returns pdf for pdf publications`() {
        val publication = publicationWith(
            conformsToPdf = true,
            conformsToDivina = false,
            readingOrder = listOf(linkWithMediaType("application/xhtml+xml"))
        )

        assertEquals(PublicationReaderKind.PDF, publication.readerKind())
    }

    @Test
    fun `returns image for divina publications`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = true,
            readingOrder = listOf(linkWithMediaType("application/xhtml+xml"))
        )

        assertEquals(PublicationReaderKind.IMAGE, publication.readerKind())
    }

    @Test
    fun `returns image when every reading order item is a bitmap`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = false,
            readingOrder = listOf(
                linkWithMediaType("image/jpeg"),
                linkWithMediaType("image/png"),
            )
        )

        assertEquals(PublicationReaderKind.IMAGE, publication.readerKind())
    }

    @Test
    fun `returns pdf when publication matches both pdf and image profiles`() {
        val publication = publicationWith(
            conformsToPdf = true,
            conformsToDivina = true,
            readingOrder = listOf(
                linkWithMediaType("image/jpeg"),
                linkWithMediaType("image/png"),
            )
        )

        assertEquals(PublicationReaderKind.PDF, publication.readerKind())
    }

    @Test
    fun `returns image for standalone bitmap publication`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = false,
            readingOrder = listOf(linkWithMediaType("image/jpeg"))
        )

        assertEquals(PublicationReaderKind.IMAGE, publication.readerKind())
    }

    @Test
    fun `returns epub when reading order is empty`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = false,
            readingOrder = emptyList()
        )

        assertEquals(PublicationReaderKind.EPUB, publication.readerKind())
    }

    @Test
    fun `returns epub when reading order mixes bitmap and html resources`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = false,
            readingOrder = listOf(
                linkWithMediaType("image/jpeg"),
                linkWithMediaType("application/xhtml+xml"),
            )
        )

        assertEquals(PublicationReaderKind.EPUB, publication.readerKind())
    }

    @Test
    fun `returns epub when reading order item has unknown media type`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = false,
            readingOrder = listOf(linkWithNullMediaType())
        )

        assertEquals(PublicationReaderKind.EPUB, publication.readerKind())
    }

    @Test
    fun `returns epub for non pdf non image publications`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = false,
            readingOrder = listOf(linkWithMediaType("application/xhtml+xml"))
        )

        assertEquals(PublicationReaderKind.EPUB, publication.readerKind())
    }

    @Test
    fun `returns audio for audiobook publications`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = false,
            readingOrder = listOf(
                linkWithMediaType("audio/mpeg"),
                linkWithMediaType("audio/mpeg"),
            ),
            conformsToAudiobook = true
        )

        assertEquals(PublicationReaderKind.AUDIO, publication.readerKind())
    }

    @Test
    fun `returns pdf when publication matches both pdf and audiobook profiles`() {
        val publication = publicationWith(
            conformsToPdf = true,
            conformsToDivina = false,
            readingOrder = listOf(linkWithMediaType("audio/mpeg")),
            conformsToAudiobook = true
        )

        assertEquals(PublicationReaderKind.PDF, publication.readerKind())
    }

    @Test
    fun `returns image when publication matches both divina and audiobook profiles`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = true,
            readingOrder = listOf(linkWithMediaType("audio/mpeg")),
            conformsToAudiobook = true
        )

        assertEquals(PublicationReaderKind.IMAGE, publication.readerKind())
    }

    @Test
    fun `returns epub when publication does not conform to audiobook profile`() {
        val publication = publicationWith(
            conformsToPdf = false,
            conformsToDivina = false,
            readingOrder = listOf(linkWithMediaType("audio/mpeg")),
            conformsToAudiobook = false
        )

        assertEquals(PublicationReaderKind.EPUB, publication.readerKind())
    }

    private fun publicationWith(
        conformsToPdf: Boolean,
        conformsToDivina: Boolean,
        readingOrder: List<Link>,
        conformsToAudiobook: Boolean = false,
    ): Publication {
        val publication = mock<Publication>()
        `when`(publication.conformsTo(Publication.Profile.PDF)).thenReturn(conformsToPdf)
        `when`(publication.conformsTo(Publication.Profile.DIVINA)).thenReturn(conformsToDivina)
        `when`(publication.conformsTo(Publication.Profile.AUDIOBOOK))
            .thenReturn(conformsToAudiobook)
        `when`(publication.readingOrder).thenReturn(readingOrder)
        return publication
    }

    private fun linkWithMediaType(mediaType: String): Link {
        val link = mock<Link>()
        val readiumMediaType = mock<MediaType>()
        `when`(readiumMediaType.isBitmap).thenReturn(mediaType.startsWith("image/"))
        `when`(link.mediaType).thenReturn(readiumMediaType)
        return link
    }

    private fun linkWithNullMediaType(): Link {
        val link = mock<Link>()
        `when`(link.mediaType).thenReturn(null)
        return link
    }
}
