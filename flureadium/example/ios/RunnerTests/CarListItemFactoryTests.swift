import CarPlay
import XCTest

@testable import flureadium

@available(iOS 14.0, *)
final class CarListItemFactoryTests: XCTestCase {

  func testPlayableNodeMapsProgressPlayingAndNodeId() {
    let node = CarBrowseNode(
      id: "book:42",
      title: "Project Hail Mary",
      subtitle: "Andy Weir",
      kind: .audiobook,
      isPlayable: true,
      progress: 0.62,
      isNowPlaying: true)

    let item = CarListItemFactory.item(from: node) { _ in }

    XCTAssertEqual(item.text, "Project Hail Mary")
    XCTAssertEqual(item.detailText, "Andy Weir")
    XCTAssertEqual(item.userInfo as? String, "book:42")
    XCTAssertEqual(item.playbackProgress, 0.62, accuracy: 0.0001)
    XCTAssertTrue(item.isPlaying)
  }

  func testContainerNodeHasNoPlaybackIndicator() {
    let node = CarBrowseNode(id: "genre:sci-fi", title: "Sci-Fi", kind: .container)

    let item = CarListItemFactory.item(from: node) { _ in }

    XCTAssertEqual(item.userInfo as? String, "genre:sci-fi")
    XCTAssertEqual(item.playbackProgress, 0, accuracy: 0.0001)
    XCTAssertFalse(item.isPlaying)
  }

  func testHandlerForwardsSelectedNode() {
    let node = CarBrowseNode(id: "book:7", title: "Book", kind: .audiobook, isPlayable: true)
    var selected: CarBrowseNode?
    let item = CarListItemFactory.item(from: node) { selected = $0 }

    item.handler?(item, {})

    XCTAssertEqual(selected?.id, "book:7")
  }
}
