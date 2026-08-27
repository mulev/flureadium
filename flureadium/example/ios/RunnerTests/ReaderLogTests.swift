//
//  ReaderLogTests.swift
//  RunnerTests
//
//  Pins the two things the shell runner depends on: the line shape a reader
//  diagnostic takes, and the subsystem string
//  scripts/run_integration_tests.sh filters its log stream on.
//

import XCTest
@testable import flureadium

final class ReaderLogTests: XCTestCase {

  func testFormatJoinsTagAndMessageWithOneSpace() {
    XCTAssertEqual(
      ReaderLog.format(tag: "EpubLocatorReporter", message: "report: locator=x"),
      "EpubLocatorReporter report: locator=x")
  }

  func testFormatPreservesAMultiLineMessageVerbatim() {
    let json = "{\n  \"href\": \"ch1.xhtml\"\n}"
    XCTAssertEqual(
      ReaderLog.format(tag: "EpubLocatorReporter", message: json),
      "EpubLocatorReporter \(json)")
  }

  /// The runner streams `subsystem == "dev.mulev.flureadium"`. A rename here that
  /// is not mirrored there produces an empty ios_native.log and no error.
  func testSubsystemMatchesTheRunnersPredicate() {
    XCTAssertEqual(readerLogSubsystem, "dev.mulev.flureadium")
  }
}
