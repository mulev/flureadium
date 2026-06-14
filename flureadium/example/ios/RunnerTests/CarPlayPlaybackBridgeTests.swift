import XCTest
import ReadiumShared
@testable import flureadium

final class CarPlayPlaybackBridgeTests: XCTestCase {

    private func makePublication(
        chapters: [(href: String, title: String?)] = [
            ("ch1.xhtml", "First Chapter"),
            ("ch2.xhtml", "Second Chapter"),
        ]
    ) -> Publication {
        let readingOrder = chapters.map { ch in
            Link(href: ch.href, mediaType: .mp3, title: ch.title)
        }
        return Publication(manifest: Manifest(
            metadata: Metadata(title: "Test Book"),
            readingOrder: readingOrder
        ))
    }

    override func tearDown() {
        CarPlayPlaybackBridge.shared.unregister()
        super.tearDown()
    }

    func testRegisterExposesChapters() {
        CarPlayPlaybackBridge.shared.register(publication: makePublication()) { _ in }
        XCTAssertEqual(CarPlayPlaybackBridge.shared.chapters.count, 2)
        XCTAssertEqual(CarPlayPlaybackBridge.shared.chapters[0].title, "First Chapter")
    }

    func testPlayChapterRoutesLocatorForSelectedIndex() {
        var played: Locator?
        CarPlayPlaybackBridge.shared.register(publication: makePublication()) { played = $0 }

        CarPlayPlaybackBridge.shared.playChapter(at: 1)

        XCTAssertEqual(played?.title, "Second Chapter")
        XCTAssertTrue(played?.href.string.contains("ch2") ?? false)
    }

    func testPlayChapterIgnoresOutOfBoundsIndex() {
        var callCount = 0
        CarPlayPlaybackBridge.shared.register(publication: makePublication()) { _ in callCount += 1 }

        CarPlayPlaybackBridge.shared.playChapter(at: 99)
        CarPlayPlaybackBridge.shared.playChapter(at: -1)

        XCTAssertEqual(callCount, 0)
    }

    func testUnregisterClearsChaptersAndHandler() {
        var callCount = 0
        CarPlayPlaybackBridge.shared.register(publication: makePublication()) { _ in callCount += 1 }

        CarPlayPlaybackBridge.shared.unregister()

        XCTAssertTrue(CarPlayPlaybackBridge.shared.chapters.isEmpty)
        CarPlayPlaybackBridge.shared.playChapter(at: 0)
        XCTAssertEqual(callCount, 0)
    }
}
