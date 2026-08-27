//
//  EpubLocatorReporterTests.swift
//  RunnerTests
//
//  Covers the page-changed pipeline: fragments resolved over the WebView, then
//  the locator published on the view's method channel and on the plugin's
//  text-locator stream.
//
//  Includes the dispose race from docs/troubleshooting.md, "Reader crash while
//  turning pages or closing the reader": a page change still in flight when the
//  reader tears down must publish nothing, on either side of the WebView hop.
//
//  Also pins what happens when resolution yields nothing usable: a nil answer
//  publishes the locator Readium reported, and an answer a newer report has
//  already superseded publishes nothing.
//

import XCTest
import Flutter
import ReadiumShared
@testable import flureadium

/// Minimal mock of FlutterBinaryMessenger: keeps the encoded payloads so a test
/// can decode them without a running Flutter engine.
private final class MockBinaryMessenger: NSObject, FlutterBinaryMessenger {

  var sentMessages: [Data] = []

  func send(onChannel channel: String, message: Data?) {
    if let message { sentMessages.append(message) }
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    if let message { sentMessages.append(message) }
    callback?(nil)
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    FlutterBinaryMessengerConnection(0)
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

/// Stands in for the reader view: owns the disposal flag the reporter reads.
private final class ReaderOwner {
  var isDisposed = false
}

/// Captures what the reporter asked of its collaborators.
private final class Collaborators {
  var resolverCalls: [(json: String, isScrollMode: Bool)] = []
  var resolverReply: Locator?
  /// Runs inside the resolver, so a test can tear the reader down mid-flight.
  var onResolve: (() -> Void)?
  var textLocators: [String?] = []
}

@MainActor
final class EpubLocatorReporterTests: XCTestCase {

  // MARK: - Fixtures

  private func makeReporter(
    _ collaborators: Collaborators, owner: ReaderOwner, messenger: MockBinaryMessenger
  ) -> EpubLocatorReporter {
    EpubLocatorReporter(
      channel: ReadiumReaderChannel(name: "reader", binaryMessenger: messenger),
      resolveFragments: { json, isScrollMode in
        collaborators.resolverCalls.append((json: json, isScrollMode: isScrollMode))
        collaborators.onResolve?()
        return collaborators.resolverReply
      },
      sendTextLocator: { collaborators.textLocators.append($0) },
      isDisposed: { [weak owner] in owner?.isDisposed ?? true })
  }

  private func locator(_ href: String) -> Locator {
    Locator(href: URL(string: href)!, mediaType: .html)
  }

  /// Polls rather than sleeping a fixed amount, so a loaded machine costs time
  /// instead of a failure.
  private func poll(until condition: () -> Bool) async {
    for _ in 0..<200 {
      if condition() { return }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
  }

  private func invocations(_ messenger: MockBinaryMessenger) -> [FlutterMethodCall] {
    let codec = FlutterStandardMethodCodec.sharedInstance()
    return messenger.sentMessages.map { codec.decodeMethodCall($0) }
  }

  // MARK: - Publishing

  func testReportPublishesResolvedLocatorOnBothChannels() async {
    let collaborators = Collaborators()
    let owner = ReaderOwner()
    let messenger = MockBinaryMessenger()
    collaborators.resolverReply = locator("resolved.xhtml")
    let reporter = makeReporter(collaborators, owner: owner, messenger: messenger)

    reporter.report(locator("input.xhtml"), isScrollMode: false)
    await poll { !messenger.sentMessages.isEmpty }

    let calls = invocations(messenger)
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.method, "onPageChanged")
    XCTAssertEqual(calls.first?.arguments as? String, collaborators.resolverReply?.jsonString)
    XCTAssertEqual(collaborators.textLocators, [collaborators.resolverReply?.jsonString])
  }

  /// Pins the fragment-resolution contract: the WebView's answer is what Dart
  /// persists, not the locator Readium reported.
  func testReportPublishesTheResolvedLocatorNotTheInputLocator() async {
    let collaborators = Collaborators()
    let owner = ReaderOwner()
    let messenger = MockBinaryMessenger()
    collaborators.resolverReply = locator("resolved.xhtml")
    let reporter = makeReporter(collaborators, owner: owner, messenger: messenger)

    reporter.report(locator("input.xhtml"), isScrollMode: false)
    await poll { !messenger.sentMessages.isEmpty }

    let published = invocations(messenger).compactMap { $0.arguments as? String }
    XCTAssertTrue(published.allSatisfy { $0.contains("resolved.xhtml") })
    XCTAssertFalse(published.contains { $0.contains("input.xhtml") })
    XCTAssertTrue(collaborators.textLocators.allSatisfy { $0?.contains("resolved.xhtml") == true })
  }

  func testReportForwardsScrollModeToTheResolver() async {
    let collaborators = Collaborators()
    let owner = ReaderOwner()
    let messenger = MockBinaryMessenger()
    collaborators.resolverReply = locator("resolved.xhtml")
    let reporter = makeReporter(collaborators, owner: owner, messenger: messenger)

    reporter.report(locator("input.xhtml"), isScrollMode: true)
    await poll { !collaborators.resolverCalls.isEmpty }

    XCTAssertEqual(collaborators.resolverCalls.count, 1)
    XCTAssertEqual(collaborators.resolverCalls.first?.isScrollMode, true)
    XCTAssertEqual(collaborators.resolverCalls.first?.json.contains("input.xhtml"), true)
  }

  // MARK: - Dispose race

  func testDisposedReporterPublishesNothing() async {
    let collaborators = Collaborators()
    let messenger = MockBinaryMessenger()
    collaborators.resolverReply = locator("resolved.xhtml")

    let liveOwner = ReaderOwner()
    let live = makeReporter(collaborators, owner: liveOwner, messenger: messenger)
    let disposedOwner = ReaderOwner()
    disposedOwner.isDisposed = true
    let disposed = makeReporter(collaborators, owner: disposedOwner, messenger: messenger)

    // Control: the pipeline is turning.
    live.report(locator("first.xhtml"), isScrollMode: false)
    await poll { messenger.sentMessages.count >= 1 }

    disposed.report(locator("dropped.xhtml"), isScrollMode: false)

    // Second control: another live report completes, so the disposed one had a
    // full round trip in which to appear.
    live.report(locator("second.xhtml"), isScrollMode: false)
    await poll { messenger.sentMessages.count >= 2 }

    XCTAssertEqual(messenger.sentMessages.count, 2)
    XCTAssertFalse(collaborators.resolverCalls.contains { $0.json.contains("dropped.xhtml") })
  }

  /// The documented crash: `dispose` lands while the WebView round trip is in
  /// flight. The guard after the hop has to drop the resolved locator.
  func testDisposeDuringFragmentResolutionPublishesNothing() async {
    let collaborators = Collaborators()
    let messenger = MockBinaryMessenger()
    collaborators.resolverReply = locator("resolved.xhtml")

    let owner = ReaderOwner()
    let reporter = makeReporter(collaborators, owner: owner, messenger: messenger)
    collaborators.onResolve = { owner.isDisposed = true }

    reporter.report(locator("input.xhtml"), isScrollMode: false)
    await poll { !collaborators.resolverCalls.isEmpty }

    // Control: a live reporter on the same messenger does publish, so an empty
    // channel below means "dropped", not "the pipeline stopped emitting".
    collaborators.onResolve = nil
    let liveOwner = ReaderOwner()
    let live = makeReporter(collaborators, owner: liveOwner, messenger: messenger)
    live.report(locator("control.xhtml"), isScrollMode: false)
    await poll { !messenger.sentMessages.isEmpty }

    XCTAssertEqual(messenger.sentMessages.count, 1)
    XCTAssertEqual(collaborators.textLocators.count, 1)
  }

  // MARK: - Resolution failure and supersession

  /// Resolution fails whenever a spread is mid-swap, which is whenever a page
  /// turn is in flight. Dropping the report leaves Dart believing the reader
  /// never moved, so the reported locator is published instead — what Android
  /// has always done (`ReadiumReaderWidget.kt:401-411`).
  func testUnresolvedLocatorPublishesTheReportedLocator() async {
    let collaborators = Collaborators()
    let messenger = MockBinaryMessenger()
    collaborators.resolverReply = nil

    let owner = ReaderOwner()
    let reporter = makeReporter(collaborators, owner: owner, messenger: messenger)

    reporter.report(locator("unresolvable.xhtml"), isScrollMode: false)
    await poll { !messenger.sentMessages.isEmpty }

    // Control: with a reply available the same reporter still publishes the
    // resolved locator, so the assertion below is about the nil branch only.
    collaborators.resolverReply = locator("resolved.xhtml")
    reporter.report(locator("control.xhtml"), isScrollMode: false)
    await poll { messenger.sentMessages.count >= 2 }

    let published = invocations(messenger).compactMap { $0.arguments as? String }
    XCTAssertEqual(published.count, 2)
    XCTAssertEqual(published.first?.contains("unresolvable.xhtml"), true)
    XCTAssertEqual(published.last?.contains("resolved.xhtml"), true)
    XCTAssertEqual(collaborators.textLocators.count, 2)
    XCTAssertEqual(collaborators.textLocators.first??.contains("unresolvable.xhtml"), true)
  }

  /// Two reports overlap: the second arrives while the first is still resolving.
  /// The first resolution is stale by the time it lands and must publish
  /// nothing; the newest one publishes.
  func testResolutionSupersededByANewerReportPublishesNothing() async {
    let collaborators = Collaborators()
    let messenger = MockBinaryMessenger()
    collaborators.resolverReply = locator("first-resolved.xhtml")

    let owner = ReaderOwner()
    let reporter = makeReporter(collaborators, owner: owner, messenger: messenger)
    let second = locator("second.xhtml")
    let secondResolved = locator("second-resolved.xhtml")

    // Runs inside the first resolution, on the main actor, before it returns —
    // so the newer report's sequence bump is already visible to the check.
    collaborators.onResolve = {
      collaborators.onResolve = nil  // the newer report must not recurse
      collaborators.resolverReply = secondResolved
      reporter.report(second, isScrollMode: false)
    }

    reporter.report(locator("first.xhtml"), isScrollMode: false)
    await poll { collaborators.resolverCalls.count >= 2 }
    await poll { !messenger.sentMessages.isEmpty }

    let published = invocations(messenger).compactMap { $0.arguments as? String }
    XCTAssertEqual(published.count, 1)
    XCTAssertEqual(published.first?.contains("second-resolved.xhtml"), true)
    XCTAssertFalse(published.contains { $0.contains("first-resolved.xhtml") })
    XCTAssertEqual(collaborators.textLocators.count, 1)
  }

  // MARK: - Reader lifetime

  /// The `isDisposed` closure is the only back-reference to the view, and it
  /// reports disposed once the view is gone (`?? true`).
  func testReporterDoesNotRetainTheView() async {
    let collaborators = Collaborators()
    let messenger = MockBinaryMessenger()
    collaborators.resolverReply = locator("resolved.xhtml")

    var owner: ReaderOwner? = ReaderOwner()
    let reporter = makeReporter(collaborators, owner: owner!, messenger: messenger)

    // Control: while the view is alive, a report publishes.
    reporter.report(locator("alive.xhtml"), isScrollMode: false)
    await poll { messenger.sentMessages.count >= 1 }

    owner = nil
    reporter.report(locator("orphan.xhtml"), isScrollMode: false)

    // Second control, from a reporter whose owner is alive.
    let liveOwner = ReaderOwner()
    let live = makeReporter(collaborators, owner: liveOwner, messenger: messenger)
    live.report(locator("second.xhtml"), isScrollMode: false)
    await poll { messenger.sentMessages.count >= 2 }

    XCTAssertEqual(messenger.sentMessages.count, 2)
    XCTAssertFalse(collaborators.resolverCalls.contains { $0.json.contains("orphan.xhtml") })
  }

  // MARK: - External links

  func testReportExternalLinkPublishesTheUrl() async {
    let collaborators = Collaborators()
    let owner = ReaderOwner()
    let messenger = MockBinaryMessenger()
    let reporter = makeReporter(collaborators, owner: owner, messenger: messenger)

    reporter.reportExternalLink(URL(string: "https://example.com/page?ref=1")!)
    await poll { !messenger.sentMessages.isEmpty }

    let call = invocations(messenger).first
    XCTAssertEqual(call?.method, "onExternalLinkActivated")
    XCTAssertEqual(call?.arguments as? String, "https://example.com/page?ref=1")
  }
}
