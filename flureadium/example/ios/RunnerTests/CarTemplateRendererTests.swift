import CarPlay
import XCTest

@testable import flureadium

@available(iOS 14.0, *)
private final class StubCarPlayContentBridge: CarPlayContentBridging {
  var tabs: [CarTab] = []
  var childrenByNode: [String: [CarBrowseNode]] = [:]
  var stubStrings: CarContentStrings?
  private(set) var selected: [String] = []

  func rootTabs(_ completion: @escaping ([CarTab]) -> Void) { completion(tabs) }

  func children(of nodeId: String, _ completion: @escaping ([CarBrowseNode]) -> Void) {
    completion(childrenByNode[nodeId] ?? [])
  }

  func strings(_ completion: @escaping (CarContentStrings?) -> Void) { completion(stubStrings) }

  func select(nodeId: String) { selected.append(nodeId) }
}

@available(iOS 14.0, *)
final class CarTemplateRendererTests: XCTestCase {

  private func strings(
    title: String = "Nothing to play yet",
    subtitle: String = "Add books to see them here"
  ) -> CarContentStrings {
    CarContentStrings(
      emptyRootTitle: title,
      emptyRootSubtitle: subtitle,
      voiceUnavailable: "Voice not installed",
      offline: "Needs a connection")
  }

  private func makeRenderer(
    bridge: CarPlayContentBridging,
    fallback: CarContentStrings,
    setRoot: @escaping (CPTemplate) -> Void = { _ in },
    push: @escaping (CPTemplate) -> Void = { _ in }
  ) -> CarTemplateRenderer {
    CarTemplateRenderer(bridge: bridge, fallbackStrings: fallback, setRoot: setRoot, push: push)
  }

  func testRootTabsBuildTabBarWithOneTemplatePerTab() {
    let bridge = StubCarPlayContentBridge()
    bridge.stubStrings = strings()
    bridge.tabs = [
      CarTab(id: "continue", title: "Continue", iconName: "play.circle"),
      CarTab(id: "library", title: "Library"),
      CarTab(id: "search", title: "Search", iconName: "magnifyingglass"),
    ]
    var root: CPTemplate?
    let renderer = makeRenderer(bridge: bridge, fallback: strings(), setRoot: { root = $0 })

    renderer.presentRoot()

    let tabBar = root as? CPTabBarTemplate
    XCTAssertEqual(tabBar?.templates.count, 3)
    XCTAssertEqual(
      tabBar?.templates.compactMap { ($0 as? CPListTemplate)?.tabTitle },
      ["Continue", "Library", "Search"])
    XCTAssertEqual(
      tabBar?.templates.compactMap { ($0 as? CPListTemplate)?.tabImage }.count, 3,
      "every tab gets a tab image (named icon, or a default when missing)")
  }

  func testEmptyTabShowsStatusPlaceholderFromLiveStrings() {
    let bridge = StubCarPlayContentBridge()
    bridge.stubStrings = strings(title: "Live empty", subtitle: "Live subtitle")
    bridge.tabs = [CarTab(id: "search", title: "Search")]
    // No children registered for "search" → the tab is empty.
    var root: CPTemplate?
    let renderer = makeRenderer(bridge: bridge, fallback: strings(), setRoot: { root = $0 })

    renderer.presentRoot()

    let tabBar = root as? CPTabBarTemplate
    let searchTab = tabBar?.templates.first as? CPListTemplate
    XCTAssertEqual(searchTab?.emptyViewTitleVariants, ["Live empty"])
    XCTAssertEqual(searchTab?.emptyViewSubtitleVariants, ["Live subtitle"])
  }

  func testEmptyRootShowsStatusPlaceholderFromLiveStrings() {
    let bridge = StubCarPlayContentBridge()
    bridge.tabs = []
    bridge.stubStrings = strings(title: "Live empty", subtitle: "Live subtitle")
    var root: CPTemplate?
    let renderer = makeRenderer(
      bridge: bridge, fallback: strings(title: "Fallback"), setRoot: { root = $0 })

    renderer.presentRoot()

    let list = root as? CPListTemplate
    XCTAssertTrue(list?.sections.isEmpty ?? false)
    XCTAssertEqual(list?.emptyViewTitleVariants, ["Live empty"])
    XCTAssertEqual(list?.emptyViewSubtitleVariants, ["Live subtitle"])
  }

  func testColdNoProviderShowsPlaceholderFromFallbackStrings() {
    let bridge = StubCarPlayContentBridge()
    bridge.tabs = []
    bridge.stubStrings = nil  // no provider registered yet
    var lastRoot: CPTemplate?
    let renderer = makeRenderer(
      bridge: bridge,
      fallback: strings(title: "Fallback empty", subtitle: "Fallback subtitle"),
      setRoot: { lastRoot = $0 })

    renderer.presentRoot()

    let list = lastRoot as? CPListTemplate
    XCTAssertTrue(list?.sections.isEmpty ?? false)
    XCTAssertEqual(list?.emptyViewTitleVariants, ["Fallback empty"])
    XCTAssertEqual(list?.emptyViewSubtitleVariants, ["Fallback subtitle"])
  }

  func testPresentRootSetsAStatusRootSynchronouslyBeforeAsyncAnswers() {
    let bridge = SuspendingBridge()
    var setRootCount = 0
    let renderer = makeRenderer(
      bridge: bridge, fallback: strings(title: "Loading state"), setRoot: { _ in setRootCount += 1 })

    renderer.presentRoot()  // bridge never calls its completions

    XCTAssertEqual(setRootCount, 1, "an initial root must be set before the provider answers")
  }

  func testPushChildrenBuildsListWithMatchingItems() {
    let bridge = StubCarPlayContentBridge()
    bridge.childrenByNode["library"] = [
      CarBrowseNode(id: "b1", title: "Book 1", kind: .audiobook, isPlayable: true),
      CarBrowseNode(id: "b2", title: "Book 2", kind: .audiobook, isPlayable: true),
    ]
    var pushed: CPTemplate?
    let renderer = makeRenderer(bridge: bridge, fallback: strings(), push: { pushed = $0 })

    renderer.pushChildren(of: "library")

    let list = pushed as? CPListTemplate
    XCTAssertEqual(list?.sections.first?.items.count, 2)
    XCTAssertEqual((list?.sections.first?.items.first as? CPListItem)?.text, "Book 1")
  }

  func testSelectingPlayableRowForwardsToBridge() {
    let bridge = StubCarPlayContentBridge()
    bridge.stubStrings = strings()
    bridge.tabs = [CarTab(id: "library", title: "Library")]
    bridge.childrenByNode["library"] = [
      CarBrowseNode(id: "book:7", title: "Book 7", kind: .audiobook, isPlayable: true)
    ]
    var root: CPTemplate?
    let renderer = makeRenderer(bridge: bridge, fallback: strings(), setRoot: { root = $0 })

    renderer.presentRoot()
    let list = (root as? CPTabBarTemplate)?.templates.first as? CPListTemplate
    let item = list?.sections.first?.items.first as? CPListItem
    item?.handler?(item!, {})

    XCTAssertEqual(bridge.selected, ["book:7"])
  }

  func testSelectingContainerRowPushesChildren() {
    let bridge = StubCarPlayContentBridge()
    bridge.stubStrings = strings()
    bridge.tabs = [CarTab(id: "library", title: "Library")]
    bridge.childrenByNode["library"] = [
      CarBrowseNode(id: "genre:sci-fi", title: "Sci-Fi", kind: .container)
    ]
    bridge.childrenByNode["genre:sci-fi"] = [
      CarBrowseNode(id: "b1", title: "Book 1", kind: .audiobook, isPlayable: true)
    ]
    var root: CPTemplate?
    var pushed: CPTemplate?
    let renderer = makeRenderer(
      bridge: bridge, fallback: strings(), setRoot: { root = $0 }, push: { pushed = $0 })

    renderer.presentRoot()
    let list = (root as? CPTabBarTemplate)?.templates.first as? CPListTemplate
    let item = list?.sections.first?.items.first as? CPListItem
    item?.handler?(item!, {})

    let pushedList = pushed as? CPListTemplate
    XCTAssertEqual(pushedList?.sections.first?.items.count, 1)
    XCTAssertTrue(bridge.selected.isEmpty)
  }
}

/// A bridge that never answers, to prove the synchronous initial root is set
/// before any provider response.
@available(iOS 14.0, *)
private final class SuspendingBridge: CarPlayContentBridging {
  func rootTabs(_ completion: @escaping ([CarTab]) -> Void) {}
  func children(of nodeId: String, _ completion: @escaping ([CarBrowseNode]) -> Void) {}
  func strings(_ completion: @escaping (CarContentStrings?) -> Void) {}
  func select(nodeId: String) {}
}
