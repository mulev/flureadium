//
//  PdfGestureSuppressionTests.swift
//  RunnerTests
//
//  The PDF gesture suppression walks, against synthetic view trees. Every
//  predicate production uses — recognizer class, tap count, and the runtime
//  type-name substrings — is matched here by test doubles named the way the
//  real UIKit and PDFKit types are named.
//

import XCTest
import UIKit
@testable import flureadium

/// Base for the interaction doubles. `UIInteraction` hands the view over in
/// `didMove(to:)`; nothing under test reads it, but conformance needs it.
private class FakeInteraction: NSObject, UIInteraction {
  private(set) weak var attachedView: UIView?
  var view: UIView? { attachedView }
  func willMove(to view: UIView?) {}
  func didMove(to view: UIView?) { attachedView = view }
}

private final class FakeEditMenuInteraction: FakeInteraction {}
private final class FakeContextMenuInteraction: FakeInteraction {}
private final class FakeTextInteraction: FakeInteraction {}
private final class PlainInteraction: FakeInteraction {}
private final class UITextNonEditableInteraction: FakeInteraction {}
private final class UITextRefinementInteraction: FakeInteraction {}

/// Name contains "Drag", which is the whole predicate production matches on.
private final class FakeDragGestureRecognizer: UIGestureRecognizer {}

/// Exact-name match for the node the double-tap word-selection walk looks for.
private final class PDFTextInputView: UIView {}

@MainActor
final class PdfGestureSuppressionTests: XCTestCase {

  // MARK: - Helpers

  private func doubleTap() -> UITapGestureRecognizer {
    let recognizer = UITapGestureRecognizer()
    recognizer.numberOfTapsRequired = 2
    return recognizer
  }

  private func singleTap() -> UITapGestureRecognizer {
    let recognizer = UITapGestureRecognizer()
    recognizer.numberOfTapsRequired = 1
    return recognizer
  }

  /// Returns the deepest view of a `depth`-level chain rooted at `root`.
  private func nest(under root: UIView, depth: Int) -> UIView {
    var current = root
    for _ in 0..<depth {
      let child = UIView()
      current.addSubview(child)
      current = child
    }
    return current
  }

  // MARK: - Test double naming

  /// The suite's precondition: the doubles report the names production matches
  /// on. If Swift ever stops reporting bare names here, every name-matched
  /// expectation below would silently pass for the wrong reason.
  func testTestDoublesReportTheNamesProductionMatchesOn() {
    XCTAssertEqual(String(describing: type(of: FakeDragGestureRecognizer())), "FakeDragGestureRecognizer")
    XCTAssertEqual(String(describing: type(of: FakeEditMenuInteraction())), "FakeEditMenuInteraction")
    XCTAssertEqual(String(describing: type(of: FakeContextMenuInteraction())), "FakeContextMenuInteraction")
    XCTAssertEqual(String(describing: type(of: FakeTextInteraction())), "FakeTextInteraction")
    XCTAssertEqual(String(describing: type(of: PlainInteraction())), "PlainInteraction")
    XCTAssertEqual(
      String(describing: type(of: UITextNonEditableInteraction())), "UITextNonEditableInteraction")
    XCTAssertEqual(
      String(describing: type(of: UITextRefinementInteraction())), "UITextRefinementInteraction")
    XCTAssertEqual(String(describing: type(of: PDFTextInputView())), "PDFTextInputView")
  }

  // MARK: - Double-tap zoom

  func testDoubleTapZoomDisablesOnlyDoubleTapRecognizers() {
    let view = UIView()
    let zoom = doubleTap()
    let tap = singleTap()
    let longPress = UILongPressGestureRecognizer()
    view.addGestureRecognizer(zoom)
    view.addGestureRecognizer(tap)
    view.addGestureRecognizer(longPress)

    PdfGestureSuppression.disableDoubleTapZoomGesture(in: view)

    XCTAssertFalse(zoom.isEnabled)
    XCTAssertTrue(tap.isEnabled)
    XCTAssertTrue(longPress.isEnabled)
  }

  func testDoubleTapZoomWalksTheWholeSubtree() {
    let root = UIView()
    let deep = nest(under: root, depth: 3)
    let zoom = doubleTap()
    deep.addGestureRecognizer(zoom)

    PdfGestureSuppression.disableDoubleTapZoomGesture(in: root)

    XCTAssertFalse(zoom.isEnabled)
  }

  // MARK: - Text selection

  func testTextSelectionDisablesLongPressAndSingleTap() {
    let view = UIView()
    let longPress = UILongPressGestureRecognizer()
    let tap = singleTap()
    let zoom = doubleTap()
    view.addGestureRecognizer(longPress)
    view.addGestureRecognizer(tap)
    view.addGestureRecognizer(zoom)

    PdfGestureSuppression.disableTextSelectionGesture(in: view)

    XCTAssertFalse(longPress.isEnabled)
    XCTAssertFalse(tap.isEnabled)
    XCTAssertTrue(zoom.isEnabled)
  }

  func testTextSelectionWalksTheWholeSubtree() {
    let root = UIView()
    let deep = nest(under: root, depth: 3)
    let longPress = UILongPressGestureRecognizer()
    deep.addGestureRecognizer(longPress)

    PdfGestureSuppression.disableTextSelectionGesture(in: root)

    XCTAssertFalse(longPress.isEnabled)
  }

  // MARK: - Drag gestures

  func testDragSuppressionMatchesRecognizersByTypeName() {
    let root = UIView()
    let drag = FakeDragGestureRecognizer()
    let pan = UIPanGestureRecognizer()
    root.addGestureRecognizer(pan)
    let deep = nest(under: root, depth: 2)
    deep.addGestureRecognizer(drag)

    PdfGestureSuppression.disableDragGestureRecognizers(in: root)

    XCTAssertFalse(drag.isEnabled)
    XCTAssertTrue(pan.isEnabled)
  }

  // MARK: - Edit menu interactions

  func testEditMenuSuppressionRemovesMenuAndTextInteractions() {
    let root = UIView()
    let editMenu = FakeEditMenuInteraction()
    let contextMenu = FakeContextMenuInteraction()
    let textInteraction = FakeTextInteraction()
    let plain = PlainInteraction()
    root.addInteraction(editMenu)
    root.addInteraction(plain)
    let deep = nest(under: root, depth: 2)
    deep.addInteraction(contextMenu)
    deep.addInteraction(textInteraction)

    PdfGestureSuppression.removeEditMenuInteractions(in: root)

    XCTAssertFalse(root.interactions.contains { $0 === editMenu })
    XCTAssertTrue(root.interactions.contains { $0 === plain })
    XCTAssertFalse(deep.interactions.contains { $0 === contextMenu })
    XCTAssertFalse(deep.interactions.contains { $0 === textInteraction })
  }

  /// `UITextNonEditableInteraction` is not an edit-menu match — it is removed
  /// only by the `PDFTextInputView` walk, and only when the host asked for it.
  func testEditMenuSuppressionLeavesNonEditableAndRefinementInteractions() {
    let view = UIView()
    let nonEditable = UITextNonEditableInteraction()
    let refinement = UITextRefinementInteraction()
    view.addInteraction(nonEditable)
    view.addInteraction(refinement)

    PdfGestureSuppression.removeEditMenuInteractions(in: view)

    XCTAssertTrue(view.interactions.contains { $0 === nonEditable })
    XCTAssertTrue(view.interactions.contains { $0 === refinement })
  }

  // MARK: - Double-tap word selection

  func testDoubleTapWordSelectionRemovesOnlyNonEditableInteractionOnPdfTextInputView() {
    let root = UIView()
    let textInput = PDFTextInputView()
    let onTextInput = UITextNonEditableInteraction()
    textInput.addInteraction(onTextInput)
    let sibling = UIView()
    let onSibling = UITextNonEditableInteraction()
    sibling.addInteraction(onSibling)
    root.addSubview(textInput)
    root.addSubview(sibling)

    PdfGestureSuppression.removeDoubleTapWordSelection(in: root)

    XCTAssertFalse(textInput.interactions.contains { $0 === onTextInput })
    XCTAssertTrue(sibling.interactions.contains { $0 === onSibling })
  }

  /// Long-press selection lives in `UITextRefinementInteraction` and stays.
  func testDoubleTapWordSelectionLeavesRefinementInteractionAlone() {
    let textInput = PDFTextInputView()
    let refinement = UITextRefinementInteraction()
    let nonEditable = UITextNonEditableInteraction()
    textInput.addInteraction(refinement)
    textInput.addInteraction(nonEditable)

    PdfGestureSuppression.removeDoubleTapWordSelection(in: textInput)

    XCTAssertTrue(textInput.interactions.contains { $0 === refinement })
    XCTAssertFalse(textInput.interactions.contains { $0 === nonEditable })
  }

  func testDoubleTapWordSelectionSearchesNestedSubviews() {
    let root = UIView()
    let deep = nest(under: root, depth: 3)
    let textInput = PDFTextInputView()
    let nonEditable = UITextNonEditableInteraction()
    textInput.addInteraction(nonEditable)
    deep.addSubview(textInput)

    PdfGestureSuppression.removeDoubleTapWordSelection(in: root)

    XCTAssertFalse(textInput.interactions.contains { $0 === nonEditable })
  }

  /// The walk returns at the matched node, so a `PDFTextInputView` nested
  /// inside another one is not visited.
  func testDoubleTapWordSelectionStopsAtTheFirstMatchOnABranch() {
    let outer = PDFTextInputView()
    let inner = PDFTextInputView()
    let onInner = UITextNonEditableInteraction()
    inner.addInteraction(onInner)
    outer.addSubview(inner)

    PdfGestureSuppression.removeDoubleTapWordSelection(in: outer)

    XCTAssertTrue(inner.interactions.contains { $0 === onInner })
  }

  // MARK: - apply

  func testApplyWithNoFlagsSetChangesNothing() {
    let root = UIView()
    let zoom = doubleTap()
    let tap = singleTap()
    let longPress = UILongPressGestureRecognizer()
    let drag = FakeDragGestureRecognizer()
    let editMenu = FakeEditMenuInteraction()
    for recognizer in [zoom, tap, longPress, drag] as [UIGestureRecognizer] {
      root.addGestureRecognizer(recognizer)
    }
    root.addInteraction(editMenu)

    PdfGestureSuppression().apply(to: root)

    XCTAssertTrue(zoom.isEnabled)
    XCTAssertTrue(tap.isEnabled)
    XCTAssertTrue(longPress.isEnabled)
    XCTAssertTrue(drag.isEnabled)
    XCTAssertTrue(root.interactions.contains { $0 === editMenu })
  }

  func testApplyRunsEverySuppressionTheHostEnabled() {
    let root = UIView()
    let zoom = doubleTap()
    let tap = singleTap()
    let longPress = UILongPressGestureRecognizer()
    let drag = FakeDragGestureRecognizer()
    let editMenu = FakeEditMenuInteraction()
    for recognizer in [zoom, tap, longPress, drag] as [UIGestureRecognizer] {
      root.addGestureRecognizer(recognizer)
    }
    root.addInteraction(editMenu)

    var suppression = PdfGestureSuppression()
    suppression.disableDoubleTapZoom = true
    suppression.disableTextSelection = true
    suppression.disableDragGestures = true
    suppression.disableDoubleTapTextSelection = true
    suppression.apply(to: root)

    XCTAssertFalse(zoom.isEnabled)
    XCTAssertFalse(tap.isEnabled)
    XCTAssertFalse(longPress.isEnabled)
    XCTAssertFalse(drag.isEnabled)
    XCTAssertFalse(root.interactions.contains { $0 === editMenu })
  }

  func testApplyFlagsFromNavigationConfig() {
    var suppression = PdfGestureSuppression()

    suppression.apply(
      FlutterNavigationConfig(
        disableDoubleTapZoom: true,
        disableTextSelection: true,
        disableDragGestures: true,
        disableDoubleTapTextSelection: true))

    XCTAssertTrue(suppression.disableDoubleTapZoom)
    XCTAssertTrue(suppression.disableTextSelection)
    XCTAssertTrue(suppression.disableDragGestures)
    XCTAssertTrue(suppression.disableDoubleTapTextSelection)
  }

  func testApplyKeepsPriorValuesForNilConfigFields() {
    var suppression = PdfGestureSuppression()
    suppression.apply(FlutterNavigationConfig(disableTextSelection: true))

    suppression.apply(FlutterNavigationConfig(disableDoubleTapZoom: true))

    XCTAssertTrue(suppression.disableDoubleTapZoom)
    XCTAssertTrue(suppression.disableTextSelection, "nil field must not reset a set flag")
    XCTAssertFalse(suppression.disableDragGestures)
    XCTAssertFalse(suppression.disableDoubleTapTextSelection)
  }

  func testApplyDecodesFalseFromNavigationConfig() {
    var suppression = PdfGestureSuppression()
    suppression.disableTextSelection = true

    suppression.apply(FlutterNavigationConfig(disableTextSelection: false))

    XCTAssertFalse(suppression.disableTextSelection)
  }

  /// A `setNavigationConfig` call must only touch the live view for what it
  /// switched on: the retained state stays whole, but the returned value carries
  /// this call's flags alone.
  func testApplyReturnsOnlyTheFlagsThisCallSwitchedOn() {
    var suppression = PdfGestureSuppression()
    suppression.apply(FlutterNavigationConfig(disableDoubleTapZoom: true))

    let noGestureFlags = suppression.apply(
      FlutterNavigationConfig(enableEdgeTapNavigation: true, edgeTapAreaPoints: 80))

    XCTAssertFalse(noGestureFlags.disableDoubleTapZoom)
    XCTAssertFalse(noGestureFlags.disableTextSelection)
    XCTAssertFalse(noGestureFlags.disableDragGestures)
    XCTAssertFalse(noGestureFlags.disableDoubleTapTextSelection)
    XCTAssertTrue(suppression.disableDoubleTapZoom, "retained state survives a config without flags")

    let textSelectionOnly = suppression.apply(
      FlutterNavigationConfig(disableTextSelection: true))

    XCTAssertTrue(textSelectionOnly.disableTextSelection)
    XCTAssertFalse(textSelectionOnly.disableDoubleTapZoom, "already applied by the earlier call")
    XCTAssertFalse(textSelectionOnly.disableDragGestures)
    XCTAssertFalse(textSelectionOnly.disableDoubleTapTextSelection)
  }

  // MARK: - Retry schedule

  /// `PDFTextInputView` is attached asynchronously after a page renders, so the
  /// removal is retried rather than run once.
  func testRetryDelaysAreTenthHalfAndOneSecond() {
    XCTAssertEqual(PdfGestureSuppression.doubleTapRetryDelays, [0.1, 0.5, 1.0])
  }
}
