package dev.mulev.flureadium

import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication

@OptIn(ExperimentalReadiumApi::class)
internal enum class PublicationReaderKind {
    EPUB,
    PDF,
    IMAGE,
    AUDIO,
}

@OptIn(ExperimentalReadiumApi::class)
internal fun Publication.readerKind(): PublicationReaderKind {
    if (conformsTo(Publication.Profile.PDF)) {
        return PublicationReaderKind.PDF
    }

    val isImagePublication =
        conformsTo(Publication.Profile.DIVINA) ||
            (readingOrder.isNotEmpty() && readingOrder.all { it.mediaType?.isBitmap == true })
    if (isImagePublication) {
        return PublicationReaderKind.IMAGE
    }

    // Checked last, so PDF and image precedence is untouched. readium defines
    // conformsTo(AUDIOBOOK) as readingOrder.allAreAudio behind a non-empty
    // guard, so a media-overlay EPUB — an all-HTML reading order — is not
    // captured here and keeps both its EPUB navigator and the karaoke path.
    if (conformsTo(Publication.Profile.AUDIOBOOK)) {
        return PublicationReaderKind.AUDIO
    }

    return PublicationReaderKind.EPUB
}
