import CarPlay
import flureadium

/// Presents the open audiobook's chapters on a CarPlay head unit and routes
/// row selections back to the active navigator through `CarPlayPlaybackBridge`.
///
/// Transport controls (play/pause/skip/seek) and now-playing metadata come for
/// free from the plugin's `NowPlayingInfoUpdater`, which already drives
/// `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` for the lockscreen.
@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

  private var interfaceController: CPInterfaceController?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    interfaceController.setRootTemplate(makeChapterListTemplate(), animated: false, completion: nil)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
  }

  private func makeChapterListTemplate() -> CPListTemplate {
    let bridge = CarPlayPlaybackBridge.shared
    let items = bridge.chapters.map { chapter -> CPListItem in
      let item = CPListItem(text: chapter.title, detailText: nil)
      item.handler = { _, completion in
        bridge.playChapter(at: chapter.index)
        completion()
      }
      return item
    }
    let section = CPListSection(items: items)
    return CPListTemplate(title: "Chapters", sections: [section])
  }
}
