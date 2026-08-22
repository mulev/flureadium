//
//  PdfGestureSuppression.swift
//  flureadium
//
//  The PDF reader's built-in gestures the host asked to switch off.
//

import UIKit

private let TAG = "PdfGestureSuppression"

/// Removes the built-in PDF gestures and interactions the host disabled.
///
/// Readium's PDF navigator hands us UIKit's own recognizers and interactions, so
/// suppression is a walk of the live view tree matched on recognizer classes and
/// runtime type names. It runs when the navigator hands over its view, and again
/// whenever the host changes the config on an already-built view.
struct PdfGestureSuppression {
  var disableDoubleTapZoom = false
  var disableTextSelection = false
  var disableDragGestures = false
  var disableDoubleTapTextSelection = false

  /// Retry offsets for `PDFTextInputView`, which UIKit attaches asynchronously
  /// after a page renders — a single deferred attempt misses it.
  static let doubleTapRetryDelays: [Double] = [0.1, 0.5, 1.0]

  /// Folds `navConfig` into the retained flags and returns the suppression this
  /// call alone switched on, so a live view is only walked for the gestures the
  /// host just disabled rather than for everything it ever disabled.
  @discardableResult
  mutating func apply(_ navConfig: FlutterNavigationConfig) -> PdfGestureSuppression {
    if let value = navConfig.disableDoubleTapZoom { disableDoubleTapZoom = value }
    if let value = navConfig.disableTextSelection { disableTextSelection = value }
    if let value = navConfig.disableDragGestures { disableDragGestures = value }
    if let value = navConfig.disableDoubleTapTextSelection {
      disableDoubleTapTextSelection = value
    }
    return PdfGestureSuppression(
      disableDoubleTapZoom: navConfig.disableDoubleTapZoom ?? false,
      disableTextSelection: navConfig.disableTextSelection ?? false,
      disableDragGestures: navConfig.disableDragGestures ?? false,
      disableDoubleTapTextSelection: navConfig.disableDoubleTapTextSelection ?? false)
  }

  /// Applies every enabled suppression to `view` and its whole subtree.
  func apply(to view: UIView) {
    if disableDoubleTapZoom { Self.disableDoubleTapZoomGesture(in: view) }
    if disableTextSelection { Self.disableTextSelectionGesture(in: view) }
    if disableDoubleTapTextSelection { Self.removeEditMenuInteractions(in: view) }
    if disableDragGestures { Self.disableDragGestureRecognizers(in: view) }
  }

  static func disableDoubleTapZoomGesture(in view: UIView) {
    // Disable double-tap gesture recognizers on this view
    for gestureRecognizer in view.gestureRecognizers ?? [] {
      if let tapGesture = gestureRecognizer as? UITapGestureRecognizer,
         tapGesture.numberOfTapsRequired == 2 {
        tapGesture.isEnabled = false
      }
    }
    // Recursively disable on all subviews
    for subview in view.subviews {
      disableDoubleTapZoomGesture(in: subview)
    }
  }

  static func disableTextSelectionGesture(in view: UIView) {
    print(TAG, "disableTextSelectionGesture: Found \(view.gestureRecognizers?.count ?? 0) gesture(s) on \(type(of: view))")

    var disabledCount = 0

    if let gestureRecognizers = view.gestureRecognizers {
      for recognizer in gestureRecognizers {
        // UILongPressGestureRecognizer - for text selection
        if recognizer is UILongPressGestureRecognizer {
          recognizer.isEnabled = false
          disabledCount += 1
        }

        // UITapGestureRecognizer (single tap) - for showing text selection menu
        if let tapRecognizer = recognizer as? UITapGestureRecognizer {
          if tapRecognizer.numberOfTapsRequired == 1 {
            tapRecognizer.isEnabled = false
            disabledCount += 1
          }
        }
      }
    }

    if disabledCount > 0 {
      print(TAG, "disableTextSelectionGesture: Disabled \(disabledCount) gesture(s) on \(type(of: view))")
    }

    // Recursively disable on all subviews
    for subview in view.subviews {
      disableTextSelectionGesture(in: subview)
    }
  }

  static func disableDragGestureRecognizers(in view: UIView) {
    // Disable drag gesture recognizers that can trigger text selection/drag-and-drop
    var disabledCount = 0
    for gestureRecognizer in view.gestureRecognizers ?? [] {
      let gestureTypeName = String(describing: type(of: gestureRecognizer))

      // Disable drag gesture recognizers (for text selection/drag-and-drop)
      if gestureTypeName.contains("Drag") {
        print(TAG, "  → Disabling drag gesture: \(gestureTypeName)")
        gestureRecognizer.isEnabled = false
        disabledCount += 1
      }
    }

    if disabledCount > 0 {
      print(TAG, "disableDragGestureRecognizers: Disabled \(disabledCount) gesture(s) on \(type(of: view))")
    }

    // Recursively disable on all subviews
    for subview in view.subviews {
      disableDragGestureRecognizers(in: subview)
    }
  }

  static func removeEditMenuInteractions(in view: UIView) {
    print(TAG, "removeEditMenuInteractions: Checking interactions on \(type(of: view))")

    // Remove text selection and editing menu interactions
    var removedCount = 0
    for interaction in view.interactions {
      let interactionTypeName = String(describing: type(of: interaction))
      let isEditMenuInteraction = interactionTypeName.contains("EditMenu") ||
                                   interactionTypeName.contains("ContextMenu")
      let isTextInteraction = interactionTypeName.contains("TextInteraction")
      if isEditMenuInteraction || isTextInteraction {
        print(TAG, "  → Removing \(interactionTypeName)")
        view.removeInteraction(interaction)
        removedCount += 1
      }
    }
    if removedCount > 0 {
      print(TAG, "  Removed \(removedCount) edit menu interaction(s) from \(type(of: view))")
    }

    // Recursively disable on all subviews
    for subview in view.subviews {
      removeEditMenuInteractions(in: subview)
    }
  }

  /// Recursively searches the view tree for `PDFTextInputView` and removes
  /// `UITextNonEditableInteraction` — the interaction responsible for double-tap
  /// word selection. Long-press selection lives in `UITextRefinementInteraction`
  /// and is unaffected.
  static func removeDoubleTapWordSelection(in view: UIView) {
    let className = String(describing: type(of: view))
    if className == "PDFTextInputView" {
      var removed = 0
      for interaction in view.interactions {
        if String(describing: type(of: interaction)) == "UITextNonEditableInteraction" {
          view.removeInteraction(interaction)
          removed += 1
        }
      }
      if removed > 0 {
        print(TAG, "removeDoubleTapWordSelection: removed \(removed) UITextNonEditableInteraction(s) from PDFTextInputView")
      }
      return
    }
    for subview in view.subviews {
      removeDoubleTapWordSelection(in: subview)
    }
  }
}
