import XCTest
import ReadiumShared
@testable import flureadium

final class LoadFailureObservingResourceTests: XCTestCase {

  func testSuccessfulReadsDoNotReportFailure() async {
    var reported: [ReadError] = []
    let underlying = DataResource(string: "hello world")
    let sut = LoadFailureObservingResource(wrapping: underlying) { reported.append($0) }

    let length = await sut.estimatedLength()
    let data = await sut.read()

    // DataResource reports no estimated length and serves its bytes unchanged.
    if case let .success(value) = length {
      XCTAssertNil(value)
    } else {
      XCTFail("estimatedLength should pass through the underlying success")
    }
    XCTAssertEqual(try? data.get(), Data("hello world".utf8))
    XCTAssertTrue(reported.isEmpty, "a healthy resource must not report a failure")
  }

  func testFailedReadsReportTheError() async {
    var reported: [ReadError] = []
    let underlying = FailureResource(error: .decoding("track missing"))
    let sut = LoadFailureObservingResource(wrapping: underlying) { reported.append($0) }

    let length = await sut.estimatedLength()
    let stream = await sut.stream(range: nil) { _ in }

    // Both read entry points must surface the underlying failure to the callback.
    if case .success = length { XCTFail("estimatedLength should surface the failure") }
    if case .success = stream { XCTFail("stream should surface the failure") }
    XCTAssertEqual(reported.count, 2)
    for error in reported {
      guard case .decoding = error else {
        return XCTFail("expected the wrapped .decoding error, got \(error)")
      }
    }
  }

  func testPropertiesAndSourceURLPassThroughWithoutReporting() async {
    var reported: [ReadError] = []
    let sourceURL = HTTPURL(string: "https://example.com/track.mp3")!
    let underlying = DataResource(string: "hello", sourceURL: sourceURL)
    let sut = LoadFailureObservingResource(wrapping: underlying) { reported.append($0) }

    let properties = await sut.properties()

    if case .failure = properties { XCTFail("properties should pass through the success") }
    XCTAssertEqual(
      sut.sourceURL?.string, sourceURL.string,
      "sourceURL must forward the wrapped resource's value, not a hardcoded nil"
    )
    XCTAssertTrue(reported.isEmpty, "metadata access must not report a load failure")
  }

  func testPropertiesFailureIsForwardedButNotReported() async {
    var reported: [ReadError] = []
    let underlying = FailureResource(error: .decoding("no props"))
    let sut = LoadFailureObservingResource(wrapping: underlying) { reported.append($0) }

    let properties = await sut.properties()

    // Only the read entry points (estimatedLength/stream) are observed; a
    // properties() failure is forwarded verbatim and never reported as a
    // playback error.
    if case .success = properties { XCTFail("properties should surface the underlying failure") }
    XCTAssertTrue(reported.isEmpty, "a properties() failure must not surface as a load failure")
  }
}
