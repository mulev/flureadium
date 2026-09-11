import XCTest
import Flutter
@testable import flureadium

/// iOS never probes track durations: `FlutterAudioNavigator` takes a track's
/// length from playback info as it plays (`currentDuration: info.duration`), so
/// there is no resolved list to report. The contract still requires the method
/// to be *answered* - an unhandled method reaches Dart as a
/// `MissingPluginException`, which would be an exception raised on a healthy
/// iOS open. Empty is the answer; this pins that it is given.
final class FlureadiumPluginAudioDurationsTests: XCTestCase {

  func testAudiobookTrackDurationsAnswersEmptyList() {
    let plugin = FlureadiumPlugin()
    let call = FlutterMethodCall(methodName: "audiobookTrackDurations", arguments: nil)

    var responses: [Any?] = []
    plugin.handle(call) { responses.append($0) }

    XCTAssertEqual(responses.count, 1, "the channel call completes exactly once")
    let response: Any? = responses.first ?? nil
    XCTAssertFalse(
      (response as AnyObject) === (FlutterMethodNotImplemented as AnyObject),
      "audiobookTrackDurations must be handled, not fall through to the default arm")
    let durations = response as? [Any?]
    XCTAssertNotNil(durations, "audiobookTrackDurations must answer with a list")
    XCTAssertEqual(durations?.count, 0, "iOS probes nothing, so the list is empty")
  }
}
