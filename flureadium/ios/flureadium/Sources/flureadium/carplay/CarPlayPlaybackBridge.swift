import ReadiumShared

/// Shared seam between the active audiobook navigator and the CarPlay scene.
///
/// The plugin registers the open publication and a play handler when an audio
/// navigator starts playing; the CarPlay scene reads `chapters` to build its
/// list and routes row selections back through `playChapter(at:)`. Keeping the
/// navigator reference here (rather than in the scene delegate) lets the
/// CarPlay surface live in the host app while playback stays in the plugin.
public final class CarPlayPlaybackBridge {

  public static let shared = CarPlayPlaybackBridge()

  private var publication: Publication?
  private var onPlay: ((Locator) -> Void)?

  private init() {}

  public func register(publication: Publication, onPlay: @escaping (Locator) -> Void) {
    self.publication = publication
    self.onPlay = onPlay
  }

  public func unregister() {
    publication = nil
    onPlay = nil
  }

  public var chapters: [CarPlayChapter] {
    guard let publication = publication else { return [] }
    return CarPlayChapterList.chapters(from: publication)
  }

  public func playChapter(at index: Int) {
    guard let publication = publication,
          publication.readingOrder.indices.contains(index) else {
      return
    }
    let link = publication.readingOrder[index]
    let locator = Locator(
      href: link.url(),
      mediaType: link.mediaType ?? .binary,
      title: link.title
    )
    onPlay?(locator)
  }
}
