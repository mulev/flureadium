package dev.mulev.flureadium

import android.os.Build
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.LocalizedString
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Reader-kind routing against real Readium manifests.
 *
 * PublicationReaderKindTest stubs `conformsTo` on a mock, which pins flureadium's
 * branch order but never runs Readium's own predicate — and the audio branch
 * rests entirely on that predicate. `Manifest.conformsTo(AUDIOBOOK)` is
 * `readingOrder.allAreAudio` behind a non-empty guard, and it consults
 * `metadata.conformsTo` only for profiles it cannot derive. These cases execute
 * it, so a Readium upgrade that changed the rule would fail here rather than on
 * a device.
 *
 * Mirrors ReaderViewKindRoutingTests.swift on iOS.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalReadiumApi::class)
internal class PublicationReaderKindManifestTest {

    @Test
    fun `returns audio for an all-audio reading order with no declared profile`() {
        val publication = publicationWith(
            profiles = emptySet(),
            readingOrder = listOf(link("track-1.mp3", MediaType.MP3), link("track-2.mp3", MediaType.MP3))
        )

        assertEquals(PublicationReaderKind.AUDIO, publication.readerKind())
    }

    @Test
    fun `returns epub for a declared audiobook profile over an html reading order`() {
        val publication = publicationWith(
            profiles = setOf(Publication.Profile.AUDIOBOOK),
            readingOrder = listOf(link("chapter.xhtml", MediaType.XHTML))
        )

        assertEquals(
            "a media-overlay EPUB declares the audiobook profile but has pages to render",
            PublicationReaderKind.EPUB,
            publication.readerKind()
        )
    }

    @Test
    fun `returns epub for a mixed audio and html reading order`() {
        val publication = publicationWith(
            profiles = emptySet(),
            readingOrder = listOf(link("track-1.mp3", MediaType.MP3), link("chapter.xhtml", MediaType.XHTML))
        )

        assertEquals(PublicationReaderKind.EPUB, publication.readerKind())
    }

    @Test
    fun `returns epub for a declared audiobook profile over an empty reading order`() {
        val publication = publicationWith(
            profiles = setOf(Publication.Profile.AUDIOBOOK),
            readingOrder = emptyList()
        )

        assertEquals(
            "Readium guards conformsTo with a non-empty reading order",
            PublicationReaderKind.EPUB,
            publication.readerKind()
        )
    }

    private fun publicationWith(
        profiles: Set<Publication.Profile>,
        readingOrder: List<Link>,
    ): Publication = Publication(
        manifest = Manifest(
            metadata = Metadata(
                conformsTo = profiles,
                localizedTitle = LocalizedString("Reader Kind")
            ),
            readingOrder = readingOrder
        )
    )

    // Readium's Url() rejects a bare filename, so the fixtures use absolute
    // hrefs. Only the media type decides allAreAudio.
    private fun link(href: String, mediaType: MediaType): Link =
        Link(href = org.readium.r2.shared.util.Url("https://example.com/$href")!!, mediaType = mediaType)
}
