import CarPlay
import XCTest

@testable import flureadium

@available(iOS 14.0, *)
private final class StubNowPlayingBridge: CarPlayContentBridging {
  private(set) var bookmarks = 0
  private(set) var speedCycles = 0
  private(set) var selected: [String] = []
  var chapters: [CarBrowseNode] = []

  func rootTabs(_ completion: @escaping ([CarTab]) -> Void) { completion([]) }
  func children(of nodeId: String, _ completion: @escaping ([CarBrowseNode]) -> Void) { completion([]) }
  func search(_ query: String, _ completion: @escaping ([CarBrowseNode]) -> Void) { completion([]) }
  func strings(_ completion: @escaping (CarContentStrings?) -> Void) { completion(nil) }
  func select(nodeId: String) { selected.append(nodeId) }
  func addBookmark() { bookmarks += 1 }
  func cycleSpeed() { speedCycles += 1 }
  func nowPlayingChapters(_ completion: @escaping ([CarBrowseNode]) -> Void) { completion(chapters) }
}

/// Covers `CarNowPlayingButtons`: the ordered action set (Bookmark only for an
/// audiobook), the buttons installed on the Now Playing template, and each tap's
/// routing through the bridge — including the chapters button pushing a list
/// whose rows forward their selection back to the host.
@available(iOS 14.0, *)
final class CarNowPlayingButtonsTests: XCTestCase {

  private var bridge: StubNowPlayingBridge!

  override func setUp() {
    super.setUp()
    bridge = StubNowPlayingBridge()
  }

  override func tearDown() {
    bridge = nil
    super.tearDown()
  }

  func testActionsForAudiobookIncludeBookmarkFirst() {
    XCTAssertEqual(
      CarNowPlayingButtons.actions(isAudiobook: true), [.bookmark, .speed, .chapters])
  }

  func testActionsForReadAloudOmitBookmark() {
    XCTAssertEqual(CarNowPlayingButtons.actions(isAudiobook: false), [.speed, .chapters])
  }

  func testInstallSetsBookmarkRateChaptersInOrderForAudiobook() {
    let template = CPNowPlayingTemplate.shared
    CarNowPlayingButtons.install(on: template, bridge: bridge, isAudiobook: true, push: { _ in })

    XCTAssertEqual(template.nowPlayingButtons.count, 3)
    XCTAssertTrue(template.nowPlayingButtons[0] is CPNowPlayingImageButton)
    XCTAssertTrue(template.nowPlayingButtons[1] is CPNowPlayingPlaybackRateButton)
    XCTAssertTrue(template.nowPlayingButtons[2] is CPNowPlayingImageButton)
  }

  func testInstallOmitsBookmarkForReadAloud() {
    let template = CPNowPlayingTemplate.shared
    CarNowPlayingButtons.install(on: template, bridge: bridge, isAudiobook: false, push: { _ in })

    XCTAssertEqual(template.nowPlayingButtons.count, 2)
    XCTAssertTrue(template.nowPlayingButtons[0] is CPNowPlayingPlaybackRateButton)
    XCTAssertTrue(template.nowPlayingButtons[1] is CPNowPlayingImageButton)
  }

  func testBookmarkTapCallsBridgeAddBookmark() {
    CarNowPlayingButtons.perform(.bookmark, bridge: bridge, push: { _ in })

    XCTAssertEqual(bridge.bookmarks, 1)
    XCTAssertEqual(bridge.speedCycles, 0)
  }

  func testSpeedTapCallsBridgeCycleSpeed() {
    CarNowPlayingButtons.perform(.speed, bridge: bridge, push: { _ in })

    XCTAssertEqual(bridge.speedCycles, 1)
    XCTAssertEqual(bridge.bookmarks, 0)
  }

  func testChaptersTapPushesListWithChapterCount() {
    bridge.chapters = [
      CarBrowseNode(id: "ch:0", title: "Chapter 1", kind: .chapter, isPlayable: true),
      CarBrowseNode(id: "ch:1", title: "Chapter 2", kind: .chapter, isPlayable: true),
    ]
    var pushed: CPTemplate?
    CarNowPlayingButtons.perform(.chapters, bridge: bridge, push: { pushed = $0 })

    let list = pushed as? CPListTemplate
    XCTAssertEqual(list?.sections.first?.items.count, 2)
  }

  func testChapterRowTapForwardsSelectionToBridge() {
    let node = CarBrowseNode(id: "ch:3", title: "Chapter 4", kind: .chapter, isPlayable: true)
    let list = CarNowPlayingButtons.chapterList(from: [node], bridge: bridge)

    let item = list.sections.first?.items.first as? CPListItem
    item?.handler?(item!, {})

    XCTAssertEqual(bridge.selected, ["ch:3"])
  }
}
