import XCTest
import Flutter
import ReadiumShared
@testable import flureadium

/// `audioEnable` must answer Dart exactly once, on every path it can take.
///
/// Its work runs in a detached Task whose `Task<Void, Error>` is discarded, so
/// a throw inside it is stored in that Task and dropped: no `result(...)`, no
/// error event, and a Dart future that never completes. That is the iOS shape
/// of the hole the Android method-channel guard closed in flureadium-2xw.4.
///
/// Neither conforming navigator throws today - `FlutterAudioNavigator` and
/// `FlutterMediaOverlayNavigator` both declare `initNavigator()` as
/// `async -> Void` - so the catch added alongside these tests cannot be driven
/// from here. What these cases pin is the reachable half of the same contract:
/// the guards answer, and they answer once.
final class FlureadiumPluginAudioEnableTests: XCTestCase {

  override func setUp() {
    super.setUp()
    currentPublication = nil
    currentPublicationUrlStr = nil
  }

  override func tearDown() {
    currentPublication = nil
    currentPublicationUrlStr = nil
    super.tearDown()
  }

  func testAudioEnableAnswersWhenNoPublicationIsOpen() {
    let plugin = FlureadiumPlugin()
    let answered = expectation(description: "result called")

    plugin.handle(audioEnableCall()) { response in
      let error = response as? FlutterError
      XCTAssertNotNil(error, "audioEnable with no open publication must answer, not hang")
      XCTAssertEqual(error?.code, "InvalidArgument")
      answered.fulfill()
    }

    wait(for: [answered], timeout: 2.0)
  }

  func testAudioEnableAnswersWhenPublicationIsNeitherAudiobookNorMediaOverlay() {
    currentPublication = publication(profile: .epub)
    currentPublicationUrlStr = "file:///tmp/not-an-audiobook.epub"
    let plugin = FlureadiumPlugin()
    let answered = expectation(description: "result called")

    plugin.handle(audioEnableCall()) { response in
      let error = response as? FlutterError
      XCTAssertNotNil(error, "an EPUB with no media overlays must answer, not hang")
      XCTAssertEqual(error?.code, "InvalidArgument")
      answered.fulfill()
    }

    wait(for: [answered], timeout: 5.0)
  }

  func testAudioEnableAnswersOnlyOnce() {
    let plugin = FlureadiumPlugin()
    let answered = expectation(description: "result called")
    answered.assertForOverFulfill = true

    plugin.handle(audioEnableCall()) { _ in answered.fulfill() }

    wait(for: [answered], timeout: 2.0)
  }

  private func audioEnableCall() -> FlutterMethodCall {
    let args: [Any?] = [[:], nil]
    return FlutterMethodCall(methodName: "audioEnable", arguments: args)
  }

  private func publication(profile: Publication.Profile) -> Publication {
    Publication(
      manifest: Manifest(
        metadata: Metadata(conformsTo: [profile], title: "Audio Enable"),
        readingOrder: [Link(href: "/chapter.xhtml", mediaType: .xhtml)]
      )
    )
  }
}
