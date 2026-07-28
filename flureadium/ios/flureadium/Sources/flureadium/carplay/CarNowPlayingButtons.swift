import CarPlay
import UIKit

/// Builds the Now Playing action buttons — Bookmark, Speed, and Chapters — and
/// routes their taps to the car content bridge.
///
/// The bookmark button records a bookmark, the speed button cycles the host's
/// playback-rate presets, and the chapters button pushes a `CPListTemplate` of
/// the now-playing chapters whose rows seek the loaded timeline. Whether the
/// active item is an audiobook is app playback state, so the caller passes
/// `isAudiobook` rather than the plugin tracking it — the OSS boundary holds and
/// a read-aloud item simply omits the (audiobook-only) bookmark button.
@available(iOS 14.0, *)
public enum CarNowPlayingButtons {

  /// A Now Playing action, listed in display order.
  public enum Action: Equatable {
    case bookmark
    case speed
    case chapters
  }

  /// The ordered actions for the active item — Bookmark only for an audiobook.
  public static func actions(isAudiobook: Bool) -> [Action] {
    isAudiobook ? [.bookmark, .speed, .chapters] : [.speed, .chapters]
  }

  /// Installs the action buttons on [template], routing taps through [bridge] and
  /// pushing the chapters list via [push].
  public static func install(
    on template: CPNowPlayingTemplate,
    bridge: CarPlayContentBridging,
    isAudiobook: Bool,
    push: @escaping (CPTemplate) -> Void
  ) {
    let buttons = actions(isAudiobook: isAudiobook).map {
      button(for: $0, bridge: bridge, push: push)
    }
    template.updateNowPlayingButtons(buttons)
  }

  /// Builds the CarPlay button for [action], wiring its tap to `perform`.
  static func button(
    for action: Action,
    bridge: CarPlayContentBridging,
    push: @escaping (CPTemplate) -> Void
  ) -> CPNowPlayingButton {
    switch action {
    case .bookmark:
      return CPNowPlayingImageButton(image: image(named: "bookmark")) { _ in
        perform(.bookmark, bridge: bridge, push: push)
      }
    case .speed:
      return CPNowPlayingPlaybackRateButton { _ in
        perform(.speed, bridge: bridge, push: push)
      }
    case .chapters:
      return CPNowPlayingImageButton(image: image(named: "list.bullet")) { _ in
        perform(.chapters, bridge: bridge, push: push)
      }
    }
  }

  /// Routes an [action] tap to the bridge — extracted from the button handler so
  /// it is unit-testable without a live CarPlay button (whose tap handler is not
  /// a readable property).
  static func perform(
    _ action: Action,
    bridge: CarPlayContentBridging,
    push: @escaping (CPTemplate) -> Void
  ) {
    switch action {
    case .bookmark:
      bridge.addBookmark()
    case .speed:
      bridge.cycleSpeed()
    case .chapters:
      bridge.nowPlayingChapters { nodes in
        push(chapterList(from: nodes, bridge: bridge))
      }
    }
  }

  /// The chapters pushed off the Now Playing screen — one selectable row per
  /// chapter, forwarding a tap to the host to seek the loaded timeline.
  static func chapterList(
    from nodes: [CarBrowseNode],
    bridge: CarPlayContentBridging
  ) -> CPListTemplate {
    let items = nodes.map { node in
      CarListItemFactory.item(from: node) { bridge.select(nodeId: $0.id) }
    }
    return CPListTemplate(title: nil, sections: [CPListSection(items: items)])
  }

  /// An SF Symbol image, falling back to an empty image if the symbol is missing
  /// so a button is always constructible.
  private static func image(named name: String) -> UIImage {
    UIImage(systemName: name) ?? UIImage()
  }
}
