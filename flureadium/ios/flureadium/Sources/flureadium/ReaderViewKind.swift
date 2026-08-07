import ReadiumShared

enum ReaderViewKind {
  case epub
  case pdf
  case image
  case audio
}

func readerViewKind(for publication: Publication) -> ReaderViewKind {
  let conformsTo = publication.metadata.conformsTo

  if conformsTo.contains(.pdf) || publication.conforms(to: .pdf) {
    return .pdf
  }

  if conformsTo.contains(.divina) || publication.conforms(to: .divina) ||
    (!publication.readingOrder.isEmpty && publication.readingOrder.allAreBitmap)
  {
    return .image
  }

  // Checked last, so PDF and image precedence is untouched. Readium defines
  // conforms(to: .audiobook) as readingOrder.allAreAudio behind a non-empty
  // guard (Manifest.swift:110-117), so a media-overlay EPUB — an all-HTML
  // reading order — is not captured here and keeps both its EPUB navigator and
  // the karaoke path. Mirrors PublicationReaderKind.kt:27-33.
  //
  // metadata.conformsTo is deliberately not consulted, unlike the PDF and
  // DiViNa branches above: a manifest may declare the audiobook profile over an
  // HTML reading order, and that publication has pages to render.
  if publication.conforms(to: .audiobook) {
    return .audio
  }

  return .epub
}
