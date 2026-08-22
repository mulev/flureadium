//
//  FlureadiumPluginDecorationStyleTests.swift
//  RunnerTests
//
//  `setDecorationStyle` decodes style maps Dart supplies. A map the decoder
//  cannot use has to be answered with an error: trapping here takes the whole
//  host process down, and the styles it would have set are optional anyway.
//

import Flutter
import ReadiumNavigator
import ReadiumShared
import XCTest

@testable import flureadium

final class FlureadiumPluginDecorationStyleTests: XCTestCase {

  private var plugin: FlureadiumPlugin!

  override func setUp() {
    super.setUp()
    plugin = FlureadiumPlugin()
    // Both styles start swapped away from their defaults, so "left unchanged"
    // is a real assertion rather than a match against the default value.
    plugin.ttsUtteranceDecorationStyle = .underline(tint: .black)
    plugin.ttsRangeDecorationStyle = .highlight(tint: .yellow)
  }

  override func tearDown() {
    plugin = nil
    super.tearDown()
  }

  /// Drives the real method channel and returns the plugin's reply.
  private func setDecorationStyle(_ arguments: [Any?]) -> Any? {
    var reply: Any?
    let answered = expectation(description: "setDecorationStyle answered")
    plugin.handle(FlutterMethodCall(methodName: "setDecorationStyle", arguments: arguments)) {
      reply = $0
      answered.fulfill()
    }
    wait(for: [answered], timeout: 5)
    return reply
  }

  func testUnusableStyleMapIsAnsweredWithAnError() {
    // No `tint`: Decoration.Style(fromMap:) throws and `try!` used to abort here.
    let reply = setDecorationStyle([["style": "highlight"], nil])

    XCTAssertNotNil(reply as? FlutterError, "an unusable style must be answered, not trapped")
    XCTAssertEqual(
      plugin.ttsUtteranceDecorationStyle?.id, Decoration.Style.Id.underline,
      "a rejected map must leave the style already in use alone")
  }

  func testUnusableRangeStyleMapIsAnsweredWithAnError() {
    // The second branch decodes the same way, so it fails the same way.
    let reply = setDecorationStyle([nil, ["style": "underline"]])

    XCTAssertNotNil(reply as? FlutterError)
    XCTAssertEqual(plugin.ttsRangeDecorationStyle?.id, Decoration.Style.Id.highlight)
  }

  func testValidStyleMapsAreStored() {
    let reply = setDecorationStyle([
      ["style": "highlight", "tint": "#FF9800"],
      ["style": "underline", "tint": "#000000"],
    ])

    XCTAssertNil(reply as? FlutterError)
    XCTAssertEqual(plugin.ttsUtteranceDecorationStyle?.id, Decoration.Style.Id.highlight)
    XCTAssertEqual(plugin.ttsRangeDecorationStyle?.id, Decoration.Style.Id.underline)
  }
}
