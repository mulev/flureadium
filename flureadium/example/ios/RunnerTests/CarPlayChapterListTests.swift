import XCTest
import ReadiumShared
@testable import flureadium

final class CarPlayChapterListTests: XCTestCase {

    private func makePublication(
        chapters: [(href: String, title: String?)] = [
            ("ch1.xhtml", "First Chapter"),
            ("ch2.xhtml", "Second Chapter"),
            ("ch3.xhtml", nil),
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

    func testChaptersHaveOneEntryPerReadingOrderItem() {
        let pub = makePublication()
        let chapters = CarPlayChapterList.chapters(from: pub)
        XCTAssertEqual(chapters.count, 3)
    }

    func testChaptersPreserveReadingOrderIndices() {
        let pub = makePublication()
        let chapters = CarPlayChapterList.chapters(from: pub)
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
    }

    func testChaptersUseReadingOrderTitleWhenPresent() {
        let pub = makePublication()
        let chapters = CarPlayChapterList.chapters(from: pub)
        XCTAssertEqual(chapters[0].title, "First Chapter")
        XCTAssertEqual(chapters[1].title, "Second Chapter")
    }

    func testChaptersFallBackToGeneratedTitleWhenMissing() {
        let pub = makePublication()
        let chapters = CarPlayChapterList.chapters(from: pub)
        // The third chapter has no title — a "<word> 3" fallback is generated.
        XCTAssertFalse(chapters[2].title.isEmpty)
        XCTAssertTrue(chapters[2].title.hasSuffix("3"))
    }

    func testEmptyReadingOrderProducesNoChapters() {
        let pub = makePublication(chapters: [])
        XCTAssertTrue(CarPlayChapterList.chapters(from: pub).isEmpty)
    }
}
