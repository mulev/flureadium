import XCTest
import Flutter
import ReadiumShared
@testable import flureadium

/// Records which navigation method the plugin invokes, so routing of the
/// "next"/"previous"/"audioSeekBy" method-channel calls can be asserted.
private final class RecordingTimebasedNavigator: FlutterTimebasedNavigator {
  private(set) var calls: [String] = []
  private let onCall: (String) -> Void

  init(onCall: @escaping (String) -> Void) {
    self.onCall = onCall
  }

  var publication: Publication = Publication(manifest: Manifest(metadata: Metadata(title: "Rec")))
  var initialLocator: Locator? = nil
  var listener: TimebasedListener? = nil

  func initNavigator() async throws {}
  func setupNavigatorListeners() {}
  @MainActor func dispose() {}
  @MainActor func play(fromLocator: Locator?) async {}
  @MainActor func pause() async {}
  @MainActor func resume() async {}
  @MainActor func togglePlayPause() async {}
  @MainActor func seekForward() async -> Bool { record("seekForward"); return true }
  @MainActor func seekBackward() async -> Bool { record("seekBackward"); return true }
  @MainActor func skipForward() async -> Bool { record("skipForward"); return true }
  @MainActor func skipBackward() async -> Bool { record("skipBackward"); return true }
  @MainActor func seek(toLocator: Locator) async -> Bool { record("seekToLocator"); return true }
  @MainActor func seek(toOffset: Double) async -> Bool { record("seekToOffset"); return true }
  @MainActor func seekRelative(byOffsetSeconds: Double) async -> Bool {
    record("seekRelative(\(byOffsetSeconds))"); return true
  }

  @MainActor private func record(_ name: String) {
    calls.append(name)
    onCall(name)
  }
}

final class FlureadiumPluginChapterNavTests: XCTestCase {

  private func makePlugin(
    expecting expected: String
  ) -> (FlureadiumPlugin, RecordingTimebasedNavigator, XCTestExpectation) {
    let plugin = FlureadiumPlugin()
    let navCalled = expectation(description: "\(expected) called")
    let nav = RecordingTimebasedNavigator { call in
      if call == expected { navCalled.fulfill() }
    }
    plugin.timebasedNavigator = nav
    return (plugin, nav, navCalled)
  }

  func testNextRoutesToSkipForward() {
    let (plugin, nav, navCalled) = makePlugin(expecting: "skipForward")
    let resultCalled = expectation(description: "result called")

    plugin.handle(FlutterMethodCall(methodName: "next", arguments: nil)) { _ in
      resultCalled.fulfill()
    }

    wait(for: [navCalled, resultCalled], timeout: 2.0)
    XCTAssertEqual(nav.calls, ["skipForward"])
    XCTAssertFalse(nav.calls.contains("seekForward"),
                   "next must navigate by track, not 30s seek")
  }

  func testPreviousRoutesToSkipBackward() {
    let (plugin, nav, navCalled) = makePlugin(expecting: "skipBackward")
    let resultCalled = expectation(description: "result called")

    plugin.handle(FlutterMethodCall(methodName: "previous", arguments: nil)) { _ in
      resultCalled.fulfill()
    }

    wait(for: [navCalled, resultCalled], timeout: 2.0)
    XCTAssertEqual(nav.calls, ["skipBackward"])
    XCTAssertFalse(nav.calls.contains("seekBackward"),
                   "previous must navigate by track, not 30s seek")
  }

  func testAudioSeekByStillRoutesToSeekRelative() {
    let (plugin, nav, navCalled) = makePlugin(expecting: "seekRelative(-30.0)")
    let resultCalled = expectation(description: "result called")

    plugin.handle(FlutterMethodCall(methodName: "audioSeekBy", arguments: -30.0)) { _ in
      resultCalled.fulfill()
    }

    wait(for: [navCalled, resultCalled], timeout: 2.0)
    XCTAssertEqual(nav.calls, ["seekRelative(-30.0)"])
    XCTAssertFalse(nav.calls.contains("skipBackward"),
                   "audioSeekBy must remain a relative seek, not a track skip")
  }
}
