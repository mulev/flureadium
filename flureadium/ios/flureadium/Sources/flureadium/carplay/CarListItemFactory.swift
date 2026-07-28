import CarPlay
import UIKit

/// Builds one `CPListItem` from one `CarBrowseNode`.
///
/// Stamps the node id on `userInfo` so selection handlers (and the Phase 8
/// search results) can recover it — `CPListItem` has no node-id property of its
/// own. Maps `subtitle` → detail text, `progress` → `playbackProgress`,
/// `isNowPlaying` → `isPlaying`, and `artworkPath` → an async-loaded image.
@available(iOS 14.0, *)
public enum CarListItemFactory {
  public static func item(
    from node: CarBrowseNode,
    onSelect: @escaping (CarBrowseNode) -> Void
  ) -> CPListItem {
    let item = CPListItem(text: node.title, detailText: node.subtitle)
    item.userInfo = node.id

    if node.isPlayable, let progress = node.progress {
      item.playbackProgress = CGFloat(progress)
    }
    item.isPlaying = node.isNowPlaying

    if let path = node.artworkPath {
      loadArtwork(at: path) { image in
        item.setImage(image)
      }
    }

    item.handler = { _, completion in
      onSelect(node)
      completion()
    }
    return item
  }

  /// Loads cover art off the main thread and delivers it on the main thread —
  /// the same discipline `NowPlayingInfoUpdater` uses to avoid the cover-load
  /// race that could clobber a concurrent title update.
  private static func loadArtwork(at path: String, completion: @escaping (UIImage) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let filePath: String
      if let url = URL(string: path), url.isFileURL {
        filePath = url.path
      } else {
        filePath = path
      }
      guard let image = UIImage(contentsOfFile: filePath) else { return }
      DispatchQueue.main.async { completion(image) }
    }
  }
}
