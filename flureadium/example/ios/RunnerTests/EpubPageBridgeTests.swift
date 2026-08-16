//
//  EpubPageBridgeTests.swift
//  RunnerTests
//
//  Pins the exact JavaScript the EPUB reader sends to `window.epubPage`. A typo
//  in one of these strings fails silently at runtime — `evaluateJavaScript`
//  returns a failure, the caller logs it and carries on — so every call is
//  asserted by literal value rather than by shape.
//

import XCTest
import ReadiumShared
@testable import flureadium

/// Records the JavaScript handed to the bridge and answers with a canned reply.
@MainActor
private final class ScriptRecorder {
  private(set) var scripts: [String] = []
  var reply: Result<Any, Error> = .success(())

  func evaluate(_ code: String) async -> Result<Any, Error> {
    scripts.append(code)
    return reply
  }
}

private struct JavascriptFailure: Error {}

@MainActor
final class EpubPageBridgeTests: XCTestCase {

  private func makeBridge() -> (EpubPageBridge, ScriptRecorder) {
    let recorder = ScriptRecorder()
    return (EpubPageBridge { await recorder.evaluate($0) }, recorder)
  }

  /// A locator-shaped JavaScript reply, the same shape the epub.js helper sends.
  private func locatorReply(href: String = "https://example.com/ch1.xhtml") -> [String: Any?] {
    [
      "href": href,
      "type": MediaType.html.string,
      "locations": ["fragments": ["#page-1"]],
    ]
  }

  // MARK: - getLocatorFragments

  func testLocatorFragmentsBuildsExactJavascript() async {
    let (bridge, recorder) = makeBridge()

    _ = await bridge.locatorFragments(locatorJson: "{\"href\":\"ch1.xhtml\"}", isScrollMode: false)
    _ = await bridge.locatorFragments(locatorJson: "{\"href\":\"ch1.xhtml\"}", isScrollMode: true)

    XCTAssertEqual(
      recorder.scripts,
      [
        "window.epubPage.getLocatorFragments({\"href\":\"ch1.xhtml\"}, false);",
        "window.epubPage.getLocatorFragments({\"href\":\"ch1.xhtml\"}, true);",
      ])
  }

  /// The method-channel `getLocatorFragments` case returns the raw JavaScript
  /// value to Dart, so it takes the unparsed variant. Both must build the same
  /// script — that is the duplicate this bridge collapsed.
  func testLocatorFragmentsResultBuildsTheSameJavascriptAsTheParsingCall() async {
    let (rawBridge, rawRecorder) = makeBridge()
    let (bridge, recorder) = makeBridge()

    _ = await rawBridge.locatorFragmentsResult(locatorJson: "null", isScrollMode: true)
    _ = await bridge.locatorFragments(locatorJson: "null", isScrollMode: true)

    XCTAssertEqual(rawRecorder.scripts, ["window.epubPage.getLocatorFragments(null, true);"])
    XCTAssertEqual(rawRecorder.scripts, recorder.scripts)
  }

  func testLocatorFragmentsParsesReply() async {
    let (bridge, recorder) = makeBridge()
    recorder.reply = .success(locatorReply())

    let locator = await bridge.locatorFragments(locatorJson: "null", isScrollMode: false)

    XCTAssertEqual(locator?.href.string, "https://example.com/ch1.xhtml")
    XCTAssertEqual(locator?.mediaType, .html)
    XCTAssertEqual(locator?.locations.fragments, ["#page-1"])
  }

  func testLocatorFragmentsReturnsNilOnUnparsableReply() async {
    let (bridge, recorder) = makeBridge()
    // Readium hands back `()` when the JavaScript side yields null.
    recorder.reply = .success(())

    let locator = await bridge.locatorFragments(locatorJson: "null", isScrollMode: false)

    XCTAssertNil(locator)
  }

  func testLocatorFragmentsReturnsNilOnEvaluationFailure() async {
    let (bridge, recorder) = makeBridge()
    recorder.reply = .failure(JavascriptFailure())

    let locator = await bridge.locatorFragments(locatorJson: "null", isScrollMode: false)

    XCTAssertNil(locator)
  }

  func testNullLocatorJsonIsPassedThrough() async {
    let (bridge, recorder) = makeBridge()

    _ = await bridge.locatorFragments(locatorJson: "null", isScrollMode: false)

    XCTAssertEqual(recorder.scripts, ["window.epubPage.getLocatorFragments(null, false);"])
  }

  // MARK: - scrollToLocations

  func testScrollToLocationsBuildsExactJavascript() async {
    let (bridge, recorder) = makeBridge()

    await bridge.scroll(toLocations: "{\"progression\":0.5}", isScrollMode: true, toStart: false)

    // No space after either comma: the original interpolation had none, and the
    // helper script is matched on the argument list, not on whitespace.
    XCTAssertEqual(
      recorder.scripts,
      ["window.epubPage.scrollToLocations({\"progression\":0.5},true,false);"])
  }

  func testScrollToLocationsForwardsBothFlags() async {
    let (bridge, recorder) = makeBridge()

    await bridge.scroll(toLocations: "null", isScrollMode: false, toStart: true)

    XCTAssertEqual(recorder.scripts, ["window.epubPage.scrollToLocations(null,false,true);"])
  }

  // MARK: - setLocation

  func testSetLocationBuildsExactJavascript() async {
    let (bridge, recorder) = makeBridge()

    _ = await bridge.setLocation(
      locatorJson: "{\"href\":\"ch1.xhtml\"}", isAudioBookWithText: false)
    _ = await bridge.setLocation(
      locatorJson: "{\"href\":\"ch1.xhtml\"}", isAudioBookWithText: true)

    XCTAssertEqual(
      recorder.scripts,
      [
        "window.epubPage.setLocation({\"href\":\"ch1.xhtml\"}, false);",
        "window.epubPage.setLocation({\"href\":\"ch1.xhtml\"}, true);",
      ])
  }

  func testSetLocationReturnsTheEvaluationResult() async {
    let (bridge, recorder) = makeBridge()
    recorder.reply = .success(true)

    let result = await bridge.setLocation(locatorJson: "null", isAudioBookWithText: false)

    XCTAssertEqual(try? result.get() as? Bool, true)
  }

  // MARK: - isLocatorVisible

  func testIsLocatorVisibleBuildsExactJavascript() async {
    let (bridge, recorder) = makeBridge()

    _ = await bridge.isLocatorVisible(locatorJson: "{\"href\":\"ch1.xhtml\"}")

    XCTAssertEqual(
      recorder.scripts, ["window.epubPage.isLocatorVisible({\"href\":\"ch1.xhtml\"});"])
  }

  func testIsLocatorVisibleReturnsTheEvaluationResult() async {
    let (bridge, recorder) = makeBridge()
    recorder.reply = .success(false)

    let result = await bridge.isLocatorVisible(locatorJson: "null")

    XCTAssertEqual(try? result.get() as? Bool, false)
  }

  // MARK: - isReaderReady

  /// The existence guard matters: a broken IIFE makes the reader look
  /// permanently unready to the host, with no error anywhere.
  func testIsReaderReadySourceIsTheGuardedIife() async {
    let (bridge, recorder) = makeBridge()

    _ = await bridge.isReaderReady()

    let expected = [
      "    (function() {",
      "        if (typeof window.epubPage !== 'undefined' && typeof window.epubPage.isReaderReady === 'function') {",
      "            return window.epubPage.isReaderReady();",
      "        } else {",
      "            return false;",
      "        }",
      "    })();",
    ].joined(separator: "\n")
    XCTAssertEqual(recorder.scripts, [expected])
  }
}
