import XCTest
import Flutter
import ReadiumShared
@testable import flureadium

/// The ceiling every positive wait in this target uses.
///
/// This is a hang guard, not a sleep. `wait(for:timeout:)` returns the moment
/// the expectation is fulfilled, so a wait that takes 2 s still costs 2 s under
/// a 60 s ceiling: raising the number cannot slow a green run, and it cannot
/// hide a defect either — a broken path never fulfils and still fails, only
/// later. The ceiling exists so a genuine deadlock fails with a readable
/// failing-test list instead of being killed at the 25-minute step timeout
/// (`.github/workflows/test.yml:240`) with no summary at all.
///
/// The per-call budgets this replaced were chosen on a fast local Mac and lost
/// on contended CI runners on 2026-09-17, 2026-09-19, 2026-09-22 and 2026-09-29.
let asyncTimeout: TimeInterval = 60

class RunnerTests: XCTestCase {

  func testTtsCanSpeakReturnsFalseWhenNoPublicationLoaded() {
    currentPublication = nil

    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "ttsCanSpeak", arguments: nil)
    plugin.handle(call) { response in
      XCTAssertEqual(response as? Bool, false,
                     "ttsCanSpeak should return false when no publication is loaded")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  // MARK: - ttsCanSpeak with an unspeakable publication

  func testTtsCanSpeakReturnsFalseForUnspeakablePublication() {
    currentPublication = Publication(manifest: Manifest(metadata: Metadata(title: "NoTTS")))

    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "ttsCanSpeak", arguments: nil)
    plugin.handle(call) { response in
      XCTAssertEqual(response as? Bool, false,
                     "ttsCanSpeak should return false for a publication without ContentService")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  // MARK: - Unknown method

  func testUnknownMethodReturnsNotImplemented() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "nonExistentMethod", arguments: nil)
    plugin.handle(call) { response in
      XCTAssertNotNil(response)
      XCTAssertTrue((response as AnyObject) === FlutterMethodNotImplemented,
                    "Unknown method should return FlutterMethodNotImplemented")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  // MARK: - setCustomHeaders

  func testSetCustomHeadersValidArgs() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let args: [String: Any] = ["httpHeaders": ["Authorization": "Bearer token123"]]
    let call = FlutterMethodCall(methodName: "setCustomHeaders", arguments: args)
    plugin.handle(call) { response in
      XCTAssertNil(response as? FlutterError,
                   "Valid setCustomHeaders should not return an error")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  func testSetCustomHeadersInvalidArgs() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "setCustomHeaders", arguments: nil)
    plugin.handle(call) { response in
      XCTAssertNotNil(response as? FlutterError,
                      "setCustomHeaders with nil args should return FlutterError")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  // MARK: - TTS methods without navigator

  func testTtsGetAvailableVoicesWithoutNavigator() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "ttsGetAvailableVoices", arguments: nil)
    plugin.handle(call) { response in
      XCTAssertNil(response as? FlutterError,
                   "a voice query with no TTS session is not an error - Android returns an empty list")
      XCTAssertEqual(response as? [String], [],
                     "ttsGetAvailableVoices without a TTS navigator should return an empty list")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  func testTtsSetVoiceWithoutNavigator() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let args: [Any?] = ["com.apple.voice.fake"]
    let call = FlutterMethodCall(methodName: "ttsSetVoice", arguments: args)
    plugin.handle(call) { response in
      XCTAssertNotNil(response as? FlutterError)
      let error = response as! FlutterError
      XCTAssertEqual(error.code, "TTSError")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  func testTtsSetPreferencesWithoutNavigator() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "ttsSetPreferences", arguments: ["speed": 1.5])
    plugin.handle(call) { response in
      XCTAssertNotNil(response as? FlutterError)
      let error = response as! FlutterError
      XCTAssertEqual(error.code, "TTSError")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  // MARK: - ttsGetSystemVoices

  func testTtsGetSystemVoicesReturnsArray() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "ttsGetSystemVoices", arguments: nil)
    plugin.handle(call) { response in
      XCTAssertTrue(response is [String],
                    "ttsGetSystemVoices should return array of JSON strings")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  // MARK: - ttsRequestInstallVoice

  func testTtsRequestInstallVoiceReturnsNil() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "ttsRequestInstallVoice", arguments: nil)
    plugin.handle(call) { response in
      XCTAssertNil(response, "ttsRequestInstallVoice should return nil (no-op on iOS)")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  // MARK: - Audio methods without navigator

  func testAudioSetPreferencesWithoutNavigator() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "audioSetPreferences", arguments: ["speed": 1.5])
    plugin.handle(call) { response in
      XCTAssertNotNil(response as? FlutterError)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  // MARK: - goToLocator invalid args

  func testGoToLocatorInvalidArgsReturnsError() {
    let plugin = FlureadiumPlugin()
    let expectation = expectation(description: "result called")

    let call = FlutterMethodCall(methodName: "goToLocator", arguments: nil)
    plugin.handle(call) { response in
      XCTAssertNotNil(response as? FlutterError,
                      "goToLocator with nil args should return FlutterError")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: asyncTimeout)
  }

  override func tearDown() {
    currentPublication = nil
    super.tearDown()
  }
}
