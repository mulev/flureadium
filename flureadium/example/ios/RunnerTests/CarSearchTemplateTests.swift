import CarPlay
import XCTest

@testable import flureadium

@available(iOS 14.0, *)
private final class StubSearchBridge: CarPlayContentBridging {
  var searchResults: [CarBrowseNode] = []
  private(set) var searched: [String] = []
  private(set) var selected: [String] = []

  func rootTabs(_ completion: @escaping ([CarTab]) -> Void) { completion([]) }
  func children(of nodeId: String, _ completion: @escaping ([CarBrowseNode]) -> Void) {
    completion([])
  }

  func search(_ query: String, _ completion: @escaping ([CarBrowseNode]) -> Void) {
    searched.append(query)
    completion(searchResults)
  }

  func strings(_ completion: @escaping (CarContentStrings?) -> Void) { completion(nil) }
  func select(nodeId: String) { selected.append(nodeId) }
  func addBookmark() {}
  func cycleSpeed() {}
  func nowPlayingChapters(_ completion: @escaping ([CarBrowseNode]) -> Void) { completion([]) }
}

/// Covers the typed-search delegate: `updatedSearchText` runs the query through
/// the bridge and maps the returned nodes to list items (each stamped with its
/// node id on `userInfo`), and selecting a result forwards that id to
/// `bridge.select`. The delegate is version-agnostic — only its presentation is
/// gated to iOS 27 — so this runs on any supported simulator.
@available(iOS 14.0, *)
final class CarSearchTemplateTests: XCTestCase {

  func testUpdatedSearchTextQueriesBridgeAndMapsNodesToItems() {
    let bridge = StubSearchBridge()
    bridge.searchResults = [
      CarBrowseNode(id: "book:weir", title: "Project Hail Mary", kind: .audiobook, isPlayable: true)
    ]
    let delegate = CarSearchTemplate(bridge: bridge)

    var items: [CPListItem] = []
    delegate.searchTemplate(
      CPSearchTemplate(), updatedSearchText: "weir", completionHandler: { items = $0 })

    XCTAssertEqual(bridge.searched, ["weir"])
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.text, "Project Hail Mary")
    XCTAssertEqual(items.first?.userInfo as? String, "book:weir")
  }

  func testSelectedResultForwardsNodeIdToBridge() {
    let bridge = StubSearchBridge()
    let delegate = CarSearchTemplate(bridge: bridge)
    let item = CPListItem(text: "Project Hail Mary", detailText: nil)
    item.userInfo = "book:weir"

    var completed = false
    delegate.searchTemplate(
      CPSearchTemplate(), selectedResult: item, completionHandler: { completed = true })

    XCTAssertEqual(bridge.selected, ["book:weir"])
    XCTAssertTrue(completed)
  }
}
