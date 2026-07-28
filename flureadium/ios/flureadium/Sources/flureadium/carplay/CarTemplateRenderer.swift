import CarPlay
import UIKit

/// Turns `CarBrowseNode` trees into CarPlay's audio-app templates and drives the
/// interface controller.
///
/// The interface-controller calls (`setRootTemplate`/`pushTemplate`) are behind
/// injectable seams so the template-building logic is unit-testable without a
/// live `CPInterfaceController`, which has no test-accessible initializer. Rows
/// load asynchronously through `updateSections`, the pattern the car bridge ADR
/// relies on for cold connects: an initial template is shown immediately and
/// filled when the provider answers.
///
/// The host injects `fallbackStrings` — its own already-localized status copy —
/// so the renderer can show a status-only root **synchronously**, before the
/// provider (or even the engine) has answered, and never a blank screen. When
/// the channel later returns the live strings they are preferred; flureadium
/// itself owns no copy.
@available(iOS 14.0, *)
public final class CarTemplateRenderer {
  private let bridge: CarPlayContentBridging
  private let fallbackStrings: CarContentStrings
  private let setRoot: (CPTemplate) -> Void
  private let push: (CPTemplate) -> Void
  private var searchTemplateDelegate: NSObject?
  private let isKeyboardAvailable: () -> Bool

  public convenience init(
    interfaceController: CPInterfaceController,
    bridge: CarPlayContentBridging,
    fallbackStrings: CarContentStrings,
    isKeyboardAvailable: @escaping () -> Bool = { false }
  ) {
    self.init(
      bridge: bridge,
      fallbackStrings: fallbackStrings,
      setRoot: { interfaceController.setRootTemplate($0, animated: false, completion: nil) },
      push: { interfaceController.pushTemplate($0, animated: true, completion: nil) },
      isKeyboardAvailable: isKeyboardAvailable)
  }

  init(
    bridge: CarPlayContentBridging,
    fallbackStrings: CarContentStrings,
    setRoot: @escaping (CPTemplate) -> Void,
    push: @escaping (CPTemplate) -> Void,
    isKeyboardAvailable: @escaping () -> Bool = { false }
  ) {
    self.bridge = bridge
    self.fallbackStrings = fallbackStrings
    self.setRoot = setRoot
    self.push = push
    self.isKeyboardAvailable = isKeyboardAvailable
  }

  /// Sets a status-only root immediately (from the injected fallback strings),
  /// then replaces it with the tab bar once the root tabs arrive — or with the
  /// live-strings status placeholder when the root is empty. The synchronous
  /// first set guarantees the head unit is never blank while the provider
  /// answers, even on a cold connect with no provider registered yet.
  public func presentRoot() {
    setRoot(Self.emptyRoot(strings: fallbackStrings))
    bridge.strings { strings in
      let resolved = strings ?? self.fallbackStrings
      self.bridge.rootTabs { tabs in
        if !tabs.isEmpty {
          let templates = tabs.map { self.listTemplate(for: $0, strings: resolved) }
          self.setRoot(CPTabBarTemplate(templates: templates))
        } else {
          self.setRoot(Self.emptyRoot(strings: resolved))
        }
      }
    }
  }

  /// Pushes the children of [nodeId] as a list, populated asynchronously.
  public func pushChildren(of nodeId: String) {
    let template = CPListTemplate(title: "", sections: [])
    Self.applyEmptyView(to: template, strings: fallbackStrings)
    push(template)
    bridge.children(of: nodeId) { nodes in
      template.updateSections(self.sections(for: nodes))
    }
  }

  /// Installs the Now Playing action buttons (Bookmark, Speed, Chapters) on the
  /// shared Now Playing template, routing taps through this renderer's bridge and
  /// pushing the chapters list with its interface-controller push. The caller
  /// supplies whether the active item is an audiobook (app playback state), so a
  /// read-aloud item omits the audiobook-only bookmark button.
  public func installNowPlayingButtons(isAudiobook: Bool) {
    CarNowPlayingButtons.install(
      on: CPNowPlayingTemplate.shared,
      bridge: bridge,
      isAudiobook: isAudiobook,
      push: push)
  }

  private func listTemplate(for tab: CarTab, strings: CarContentStrings) -> CPListTemplate {
    let template = CPListTemplate(title: tab.title, sections: [])
    template.tabTitle = tab.title
    // Every tab needs an image or CarPlay falls back to the generic "More" tab;
    // the host's iconName is only a hint, so default when it's missing/unknown.
    template.tabImage =
      tab.iconName.flatMap { UIImage(systemName: $0) } ?? UIImage(systemName: "list.bullet")
    Self.applyEmptyView(to: template, strings: strings)
    bridge.children(of: tab.id) { nodes in
      self.updateTabSections(nodes, for: tab, into: template)
    }
    return template
  }

  private func item(for node: CarBrowseNode) -> CPListItem {
    CarListItemFactory.item(from: node) { [weak self] selected in
      guard let self = self else { return }
      if selected.isPlayable {
        self.bridge.select(nodeId: selected.id)
      } else {
        self.pushChildren(of: selected.id)
      }
    }
  }

  /// Builds the list sections for [nodes], or none when empty so the template's
  /// built-in empty view (host status copy) shows instead of a blank section. A
  /// `siri` node is a marker for the Siri assistant cell, not an ordinary row,
  /// so it never appears here.
  private func sections(for nodes: [CarBrowseNode]) -> [CPListSection] {
    let rows = nodes.compactMap { self.row(for: $0) }
    return rows.isEmpty ? [] : [CPListSection(items: rows)]
  }

  /// One row for [node], or nil when it contributes no ordinary row — a `siri`
  /// node is the Siri assistant-cell marker, surfaced by `updateTabSections`
  /// rather than as a list row.
  private func row(for node: CarBrowseNode) -> CPListItem? {
    node.kind == .siri ? nil : item(for: node)
  }

  /// Fills the Search tab's list: a `siri` node installs the Siri assistant cell
  /// (iOS 15+), and on the iOS 27+ typed-search path a single row — labeled from
  /// the tab's own title, since it opens the keyboard rather than Siri — is
  /// appended to push `CarSearchTemplate`. The two paths are independent, so on
  /// iOS 15 through pre-27 (or without a keyboard) the assistant cell shows with
  /// no typed row.
  private func updateTabSections(
    _ nodes: [CarBrowseNode], for tab: CarTab, into template: CPListTemplate
  ) {
    let hasSiri = nodes.contains { $0.kind == .siri }
    if hasSiri, #available(iOS 15.0, *) {
      template.assistantCellConfiguration = CarAssistantCell.configuration()
    }
    var rows = nodes.compactMap { self.row(for: $0) }
    if hasSiri, #available(iOS 27.0, *), isKeyboardAvailable() {
      rows.append(typedSearchRow(title: tab.title))
    }
    template.updateSections(rows.isEmpty ? [] : [CPListSection(items: rows)])
  }

  /// A row that opens CarPlay's typed search (`CarSearchTemplate`) on iOS 27+.
  /// Retains the search delegate for the renderer's lifetime, since
  /// `CPSearchTemplate` holds its delegate weakly. Keyboard availability is
  /// re-checked at tap time: it can change after the row is built (e.g. the car
  /// disables the keyboard once moving), and a stale row must not present typed
  /// search then.
  @available(iOS 27.0, *)
  private func typedSearchRow(title: String) -> CPListItem {
    let searchRow = CPListItem(text: title, detailText: nil)
    searchRow.handler = { [weak self] _, completion in
      guard let self = self, self.isKeyboardAvailable() else { return completion() }
      let search = CarSearchTemplate(bridge: self.bridge)
      self.searchTemplateDelegate = search
      self.push(search.makeTemplate())
      completion()
    }
    return searchRow
  }

  /// Applies the host's localized status copy to a template's built-in empty
  /// view, so an empty list shows the status placeholder, never a blank screen.
  private static func applyEmptyView(to template: CPListTemplate, strings: CarContentStrings) {
    template.emptyViewTitleVariants = [strings.emptyRootTitle]
    template.emptyViewSubtitleVariants = [strings.emptyRootSubtitle]
  }

  /// The status-only root shown when there are no tabs: an empty `CPListTemplate`
  /// whose built-in empty view carries the host's localized copy. Using the
  /// template's empty-view variants (not a fake one-item list) gives the
  /// intended non-tappable status presentation, never a blank screen.
  static func emptyRoot(strings: CarContentStrings) -> CPListTemplate {
    let template = CPListTemplate(title: strings.emptyRootTitle, sections: [])
    applyEmptyView(to: template, strings: strings)
    return template
  }
}
