import ReadiumNavigator
import UIKit

/// Whether the overlay swallows touches in its edge zones.
///
/// Only when it will act on them. Readium's adapter no longer claims pointers,
/// so intercepting while edge tap is off would starve the WebView — and with it
/// the tap observer — of every touch within `edgeTapAreaPoints` of an edge.
func shouldInterceptEdgeTaps(isScrollMode: Bool, edgeTapEnabled: Bool) -> Bool {
  !isScrollMode && edgeTapEnabled
}

/// Host-configured edge tap and swipe navigation, applied to the
/// `EdgeTapInterceptView` layered over a Readium visual navigator.
///
/// One type for all three visual readers. EPUB passes its live scroll mode; PDF
/// and CBZ have no scroll mode on their view path and leave it `false`.
struct ReaderEdgeNavigationState {
  var enableEdgeTapNavigation = true
  var enableSwipeNavigation = true
  var edgeTapAreaPoints: CGFloat?

  mutating func apply(_ navConfig: FlutterNavigationConfig) {
    if let value = navConfig.enableEdgeTapNavigation {
      enableEdgeTapNavigation = value
    }
    if let value = navConfig.enableSwipeNavigation {
      enableSwipeNavigation = value
    }
    if let points = navConfig.edgeTapAreaPoints {
      edgeTapAreaPoints = Self.clampEdgeTapPoints(points)
    }
  }

  /// Points the overlay's callbacks at `navigator`, or clears them where the
  /// host disabled the gesture or the reader is scrolling.
  ///
  /// Interception and acting are one condition: the overlay only swallows an
  /// edge touch when it has a page turn to run on it. Swipes are ours only in
  /// paginated mode — the WebView handles them natively while scrolling.
  func configure(
    edgeTapView: EdgeTapInterceptView,
    navigator: VisualNavigator,
    isScrollMode: Bool = false,
    animated: Bool
  ) {
    let edgeTapsActive = shouldInterceptEdgeTaps(
      isScrollMode: isScrollMode, edgeTapEnabled: enableEdgeTapNavigation)
    edgeTapView.interceptEdgeTaps = edgeTapsActive

    if edgeTapsActive {
      if let points = edgeTapAreaPoints {
        edgeTapView.edgeThresholdPoints = points
      }
      edgeTapView.onLeftEdgeTap = Self.turnPage(left: true, on: navigator, animated: animated)
      edgeTapView.onRightEdgeTap = Self.turnPage(left: false, on: navigator, animated: animated)
    } else {
      edgeTapView.onLeftEdgeTap = nil
      edgeTapView.onRightEdgeTap = nil
    }

    if !isScrollMode && enableSwipeNavigation {
      edgeTapView.onSwipeLeft = Self.turnPage(left: false, on: navigator, animated: animated)
      edgeTapView.onSwipeRight = Self.turnPage(left: true, on: navigator, animated: animated)
    } else {
      edgeTapView.onSwipeLeft = nil
      edgeTapView.onSwipeRight = nil
    }
  }

  /// Weak on the navigator: a callback the overlay still holds after teardown
  /// must not keep a dead navigator alive.
  private static func turnPage(
    left: Bool, on navigator: VisualNavigator, animated: Bool
  ) -> () -> Void {
    { [weak navigator] in
      Task { @MainActor in
        guard let navigator else { return }
        let options = NavigatorGoOptions(animated: animated)
        _ = left
          ? await navigator.goLeft(options: options)
          : await navigator.goRight(options: options)
      }
    }
  }

  /// 44 pt is the iOS HIG minimum tap target; 120 pt keeps the two zones from
  /// meeting on a narrow device.
  static func clampEdgeTapPoints(_ points: Double) -> CGFloat {
    CGFloat(clamp(points, minValue: 44.0, maxValue: 120.0))
  }
}
