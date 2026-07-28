import CarPlay

/// Presents CarPlay's typed search (`CPSearchTemplate`) and maps its results
/// through the bridge.
///
/// The `CPSearchTemplate` API exists from iOS 14, but audio apps may only
/// *present* it from iOS 27 — before that it is navigation-entitlement-only, and
/// even on iOS 27 it stays gated on vehicle keyboard availability. So the policy
/// gate lives at the single presentation site (`CarTemplateRenderer`), never in
/// this type: typed search is always an enhancement layered over the Siri
/// assistant cell (the iOS 15+ baseline), never the only search path. Keeping the
/// delegate itself version-agnostic lets its mapping logic be unit-tested on any
/// supported simulator.
///
/// `CarListItemFactory` stamps each result's `userInfo` with the node id, which
/// the selection delegate recovers to route the play — `CPListItem` carries no
/// node id of its own.
@available(iOS 14.0, *)
public final class CarSearchTemplate: NSObject, CPSearchTemplateDelegate {
  private let bridge: CarPlayContentBridging
  private let onSelect: (String) -> Void

  public convenience init(bridge: CarPlayContentBridging) {
    self.init(bridge: bridge, onSelect: { bridge.select(nodeId: $0) })
  }

  init(bridge: CarPlayContentBridging, onSelect: @escaping (String) -> Void) {
    self.bridge = bridge
    self.onSelect = onSelect
  }

  /// Builds a `CPSearchTemplate` bound to this delegate. `CPSearchTemplate`
  /// holds its delegate weakly, so the caller must retain this instance for as
  /// long as the template is presented.
  public func makeTemplate() -> CPSearchTemplate {
    let template = CPSearchTemplate()
    template.delegate = self
    return template
  }

  public func searchTemplate(
    _ searchTemplate: CPSearchTemplate,
    updatedSearchText searchText: String,
    completionHandler: @escaping ([CPListItem]) -> Void
  ) {
    bridge.search(searchText) { nodes in
      completionHandler(nodes.map { node in CarListItemFactory.item(from: node) { _ in } })
    }
  }

  public func searchTemplate(
    _ searchTemplate: CPSearchTemplate,
    selectedResult item: CPListItem,
    completionHandler: @escaping () -> Void
  ) {
    if let nodeId = item.userInfo as? String { onSelect(nodeId) }
    completionHandler()
  }
}
