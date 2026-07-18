import ReadiumShared

/// One browsable entry in the CarPlay chapter list.
public struct CarPlayChapter: Equatable {
  public let index: Int
  public let title: String

  public init(index: Int, title: String) {
    self.index = index
    self.title = title
  }
}

/// Derives the browsable chapter rows shown on CarPlay from an audiobook
/// publication's reading order.
public enum CarPlayChapterList {

  private static let fallbackChapterTitle: LocalizedString = LocalizedString.localized([
    "en": "Chapter",
    "da": "Kapitel",
    "sv": "Kapitel",
    "no": "Kapittel",
    "is": "Kafli",
  ])

  public static func chapters(from publication: Publication) -> [CarPlayChapter] {
    let languageCode = publication.metadata.language?.code.bcp47
    let fallback = fallbackChapterTitle.string(forLanguageCode: languageCode)

    return publication.readingOrder.enumerated().map { index, link in
      let title = link.title ?? "\(fallback) \(index + 1)"
      return CarPlayChapter(index: index, title: title)
    }
  }
}
