import XCTest
import ReadiumShared
@testable import flureadium

final class AudioResourceLoadFailureReporterTests: XCTestCase {

  private let anyError = ReadError.decoding("track missing")

  func testReportsEachTrackFailureOnce() {
    var sends: [(message: String, data: String)] = []
    let sut = AudioResourceLoadFailureReporter { message, data in sends.append((message, data)) }
    let href = AnyURL(string: "track1.mp3")!

    sut.report(href: href, error: anyError)
    sut.report(href: href, error: anyError)

    XCTAssertEqual(sends.count, 1, "repeated failures for the same track must send once")
  }

  func testReportsDistinctTracksSeparately() {
    var sends: [(message: String, data: String)] = []
    let sut = AudioResourceLoadFailureReporter { message, data in sends.append((message, data)) }

    sut.report(href: AnyURL(string: "track1.mp3")!, error: anyError)
    sut.report(href: AnyURL(string: "track2.mp3")!, error: anyError)

    XCTAssertEqual(sends.count, 2)
  }

  func testResetAllowsReReporting() {
    var sends: [(message: String, data: String)] = []
    let sut = AudioResourceLoadFailureReporter { message, data in sends.append((message, data)) }
    let href = AnyURL(string: "track1.mp3")!

    sut.report(href: href, error: anyError)
    sut.reset()
    sut.report(href: href, error: anyError)

    XCTAssertEqual(sends.count, 2, "reset clears the per-publication de-dup set")
  }

  func testConcurrentReportsForSameTrackSendOnce() {
    let lock = NSLock()
    var count = 0
    let sut = AudioResourceLoadFailureReporter { _, _ in
      lock.lock(); count += 1; lock.unlock()
    }
    let href = AnyURL(string: "track1.mp3")!
    let error = anyError

    DispatchQueue.concurrentPerform(iterations: 200) { _ in
      sut.report(href: href, error: error)
    }

    XCTAssertEqual(count, 1, "concurrent failures for one track must not race past the de-dup guard")
  }

  // Exercises the opener transform end-to-end through the real Publication.get
  // path: only audio reading-order tracks are wrapped; a failing cover/resource
  // entry served by the same container is left untouched.
  func testTransformReportsOnlyAudioTrackFailures() async {
    var sends: [(message: String, data: String)] = []
    let sut = AudioResourceLoadFailureReporter { message, data in sends.append((message, data)) }

    let manifest = Manifest(
      metadata: Metadata(title: "Audiobook"),
      readingOrder: [Link(href: "track1.mp3", mediaType: .mp3)]
    )
    let container = CompositeContainer([
      SingleResourceContainer(resource: FailureResource(error: anyError), at: AnyURL(string: "track1.mp3")!),
      // A cover that also fails to load; because it is not in the reading order
      // it must stay unwrapped and never surface as a playback error.
      SingleResourceContainer(resource: FailureResource(error: anyError), at: AnyURL(string: "cover.jpg")!),
    ])
    var builder = Publication.Builder(manifest: manifest, container: container)
    builder.apply(sut.makeTransform())
    let publication = builder.build()

    // Two range reads of the failing track collapse into a single report.
    _ = await publication.get(publication.readingOrder[0])!.read()
    _ = await publication.get(publication.readingOrder[0])!.read()
    // The failing cover is not a reading-order track, so it must not be reported
    // even though its own read fails.
    _ = await publication.get(Link(href: "cover.jpg", mediaType: .jpeg))!.read()

    XCTAssertEqual(sends.count, 1, "only the audio track's load failure surfaces, once")
  }

  func testTransformIgnoresNonAudiobookManifests() async {
    var sends: [(message: String, data: String)] = []
    let sut = AudioResourceLoadFailureReporter { message, data in sends.append((message, data)) }

    let manifest = Manifest(
      metadata: Metadata(title: "EPUB"),
      readingOrder: [Link(href: "chapter1.xhtml", mediaType: .xhtml)]
    )
    let container = SingleResourceContainer(
      resource: FailureResource(error: anyError),
      at: AnyURL(string: "chapter1.xhtml")!
    )
    var builder = Publication.Builder(manifest: manifest, container: container)
    builder.apply(sut.makeTransform())
    let publication = builder.build()

    _ = await publication.get(publication.readingOrder[0])!.read()

    XCTAssertTrue(sends.isEmpty, "a non-audiobook reading order is left untouched")
  }
}
