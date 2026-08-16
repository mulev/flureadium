//
//  ReaderEdgeNavigationStateTests.swift
//  RunnerTests
//
//  One edge-navigation owner for EPUB, PDF and CBZ: the gate matrix that decides
//  which overlay callbacks exist, and where a fired callback lands on the
//  navigator.
//

import XCTest
import ReadiumNavigator
import ReadiumShared
import UIKit
@testable import flureadium

/// Minimal `VisualNavigator` that records page turns. `VisualNavigator`'s
/// protocol extension supplies `goLeft`/`goRight` from the reading progression,
/// so this records in them directly instead of going through `goForward`.
private final class RecordingVisualNavigator: VisualNavigator {

  enum Direction { case left, right }

  struct Turn: Equatable {
    let direction: Direction
    let animated: Bool
  }

  private(set) var turns: [Turn] = []

  var view: UIView! = UIView()
  var presentation = VisualNavigatorPresentation(
    readingProgression: .ltr, scroll: false, axis: .horizontal)
  var publication = Publication(manifest: Manifest(metadata: Metadata(title: "Edge Navigation")))
  var currentLocation: Locator?

  func goLeft(options: NavigatorGoOptions) async -> Bool {
    turns.append(Turn(direction: .left, animated: options.animated))
    return true
  }

  func goRight(options: NavigatorGoOptions) async -> Bool {
    turns.append(Turn(direction: .right, animated: options.animated))
    return true
  }

  func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool { true }
  func go(to link: Link, options: NavigatorGoOptions) async -> Bool { true }
  func goForward(options: NavigatorGoOptions) async -> Bool { true }
  func goBackward(options: NavigatorGoOptions) async -> Bool { true }
  func addObserver(_ observer: InputObserving) -> InputObservableToken { InputObservableToken() }
  func removeObserver(_ token: InputObservableToken) {}
}

@MainActor
final class ReaderEdgeNavigationStateTests: XCTestCase {

  private func makeView() -> EdgeTapInterceptView {
    EdgeTapInterceptView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
  }

  /// The callbacks hop to the main actor before touching the navigator, so the
  /// turn lands after a suspension. Polling keeps a loaded machine costing time
  /// rather than a failure.
  private func firstTurn(
    on navigator: RecordingVisualNavigator, after fire: () -> Void
  ) async -> RecordingVisualNavigator.Turn? {
    fire()
    for _ in 0..<100 {
      if let turn = navigator.turns.first { return turn }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return nil
  }

  // MARK: - Host config

  func testDefaultsEnableBothGesturesWithNoThresholdOverride() {
    let state = ReaderEdgeNavigationState()

    XCTAssertTrue(state.enableEdgeTapNavigation)
    XCTAssertTrue(state.enableSwipeNavigation)
    XCTAssertNil(state.edgeTapAreaPoints)
  }

  func testApplyUpdatesFlagsAndClampsThreshold() {
    var state = ReaderEdgeNavigationState()

    state.apply(
      FlutterNavigationConfig(
        enableEdgeTapNavigation: false,
        enableSwipeNavigation: false,
        edgeTapAreaPoints: 12.0
      )
    )

    XCTAssertFalse(state.enableEdgeTapNavigation)
    XCTAssertFalse(state.enableSwipeNavigation)
    XCTAssertEqual(state.edgeTapAreaPoints, 44.0)
  }

  func testApplyPreservesExistingValuesWhenFieldsAreNil() {
    var state = ReaderEdgeNavigationState()
    state.edgeTapAreaPoints = 88.0

    state.apply(FlutterNavigationConfig(enableSwipeNavigation: false))

    XCTAssertTrue(state.enableEdgeTapNavigation)
    XCTAssertFalse(state.enableSwipeNavigation)
    XCTAssertEqual(state.edgeTapAreaPoints, 88.0)
  }

  func testClampEdgeTapPointsHoldsBothBounds() {
    XCTAssertEqual(ReaderEdgeNavigationState.clampEdgeTapPoints(240.0), 120.0)
    XCTAssertEqual(ReaderEdgeNavigationState.clampEdgeTapPoints(10.0), 44.0)
    XCTAssertEqual(ReaderEdgeNavigationState.clampEdgeTapPoints(72.0), 72.0)
  }

  // MARK: - Gate matrix

  func testPaginatedAndEdgeTapEnabledWiresBothEdges() {
    let view = makeView()
    let navigator = RecordingVisualNavigator()

    ReaderEdgeNavigationState().configure(
      edgeTapView: view, navigator: navigator, isScrollMode: false, animated: true)

    XCTAssertTrue(view.interceptEdgeTaps)
    XCTAssertNotNil(view.onLeftEdgeTap)
    XCTAssertNotNil(view.onRightEdgeTap)
  }

  func testEdgeTapDisabledClearsEdgeCallbacks() {
    let view = makeView()
    view.onLeftEdgeTap = {}
    view.onRightEdgeTap = {}
    let navigator = RecordingVisualNavigator()
    let state = ReaderEdgeNavigationState(enableEdgeTapNavigation: false)

    state.configure(
      edgeTapView: view, navigator: navigator, isScrollMode: false, animated: true)

    XCTAssertFalse(
      view.interceptEdgeTaps, "intercepting without a callback is a dead band for onTap")
    XCTAssertNil(view.onLeftEdgeTap)
    XCTAssertNil(view.onRightEdgeTap)
  }

  func testScrollModeClearsEdgeAndSwipeCallbacks() {
    let view = makeView()
    let navigator = RecordingVisualNavigator()

    ReaderEdgeNavigationState().configure(
      edgeTapView: view, navigator: navigator, isScrollMode: true, animated: true)

    XCTAssertFalse(view.interceptEdgeTaps)
    XCTAssertNil(view.onLeftEdgeTap)
    XCTAssertNil(view.onRightEdgeTap)
    XCTAssertNil(view.onSwipeLeft, "WKWebView owns vertical scrolling")
    XCTAssertNil(view.onSwipeRight)
  }

  func testScrollModeFalseKeepsSwipesForPdfAndCbz() {
    let view = makeView()
    let navigator = RecordingVisualNavigator()

    // PDF and CBZ have no scroll mode on their view path and omit the argument.
    ReaderEdgeNavigationState().configure(
      edgeTapView: view, navigator: navigator, animated: false)

    XCTAssertNotNil(view.onSwipeLeft)
    XCTAssertNotNil(view.onSwipeRight)
  }

  func testSwipeDisabledClearsSwipeCallbacksOnly() {
    let view = makeView()
    view.onSwipeLeft = {}
    view.onSwipeRight = {}
    let navigator = RecordingVisualNavigator()
    let state = ReaderEdgeNavigationState(enableSwipeNavigation: false)

    state.configure(
      edgeTapView: view, navigator: navigator, isScrollMode: false, animated: true)

    XCTAssertNil(view.onSwipeLeft)
    XCTAssertNil(view.onSwipeRight)
    XCTAssertNotNil(view.onLeftEdgeTap)
    XCTAssertNotNil(view.onRightEdgeTap)
  }

  func testThresholdOverrideAppliesOnlyWhenEdgeTapsActive() {
    let navigator = RecordingVisualNavigator()
    var state = ReaderEdgeNavigationState()
    state.edgeTapAreaPoints = 72.0

    let scrolling = makeView()
    state.configure(
      edgeTapView: scrolling, navigator: navigator, isScrollMode: true, animated: true)
    XCTAssertEqual(scrolling.edgeThresholdPoints, 44.0, "no zone to widen with the gate off")

    let paginated = makeView()
    state.configure(
      edgeTapView: paginated, navigator: navigator, isScrollMode: false, animated: true)
    XCTAssertEqual(paginated.edgeThresholdPoints, 72.0)
  }

  // MARK: - Where a fired callback lands

  func testLeftEdgeCallbackTurnsPageLeft() async {
    let view = makeView()
    let navigator = RecordingVisualNavigator()
    ReaderEdgeNavigationState().configure(
      edgeTapView: view, navigator: navigator, isScrollMode: false, animated: true)

    let turn = await firstTurn(on: navigator) { view.onLeftEdgeTap?() }

    XCTAssertEqual(turn?.direction, .left)
  }

  func testRightEdgeCallbackTurnsPageRight() async {
    let view = makeView()
    let navigator = RecordingVisualNavigator()
    ReaderEdgeNavigationState().configure(
      edgeTapView: view, navigator: navigator, isScrollMode: false, animated: true)

    let turn = await firstTurn(on: navigator) { view.onRightEdgeTap?() }

    XCTAssertEqual(turn?.direction, .right)
  }

  func testSwipeLeftTurnsPageRight() async {
    let view = makeView()
    let navigator = RecordingVisualNavigator()
    ReaderEdgeNavigationState().configure(
      edgeTapView: view, navigator: navigator, isScrollMode: false, animated: true)

    // Swiping left drags the page leftwards, which advances — the inversion is
    // intentional and easy to flip by accident.
    let turn = await firstTurn(on: navigator) { view.onSwipeLeft?() }

    XCTAssertEqual(turn?.direction, .right)
  }

  func testSwipeRightTurnsPageLeft() async {
    let view = makeView()
    let navigator = RecordingVisualNavigator()
    ReaderEdgeNavigationState().configure(
      edgeTapView: view, navigator: navigator, isScrollMode: false, animated: true)

    let turn = await firstTurn(on: navigator) { view.onSwipeRight?() }

    XCTAssertEqual(turn?.direction, .left)
  }

  func testAnimatedFlagIsForwarded() async {
    let animatedView = makeView()
    let animatedNavigator = RecordingVisualNavigator()
    ReaderEdgeNavigationState().configure(
      edgeTapView: animatedView, navigator: animatedNavigator, isScrollMode: false, animated: true)

    let animated = await firstTurn(on: animatedNavigator) { animatedView.onLeftEdgeTap?() }
    XCTAssertEqual(animated?.animated, true)

    // CBZ/DiViNa turn pages without animation.
    let instantView = makeView()
    let instantNavigator = RecordingVisualNavigator()
    ReaderEdgeNavigationState().configure(
      edgeTapView: instantView, navigator: instantNavigator, animated: false)

    let instant = await firstTurn(on: instantNavigator) { instantView.onLeftEdgeTap?() }
    XCTAssertEqual(instant?.animated, false)
  }

  func testConfigureDoesNotRetainTheNavigator() {
    let view = makeView()
    weak var weakNavigator: RecordingVisualNavigator?

    do {
      let navigator = RecordingVisualNavigator()
      weakNavigator = navigator
      ReaderEdgeNavigationState().configure(
        edgeTapView: view, navigator: navigator, isScrollMode: false, animated: true)
    }

    XCTAssertNil(
      weakNavigator, "a callback the overlay still holds must not keep a dead navigator alive")
  }
}
