import Foundation
import ReadiumNavigator

/// Observes taps on `observable` and reports each one to `channel`.
///
/// In EPUB, Readium drops a pointer event that landed on an interactive element
/// (link, footnote) before any observer runs — `EPUBSpreadView`
/// `didReceivePointerEvent` checks `interactiveElement`. So what arrives here is
/// a tap nothing else claimed. PDF and CBZ have no such filter: a tap on a PDF
/// link annotation both follows the link and reports a tap.
///
/// The observer never consumes the event. Consuming would starve every observer
/// registered behind this one, the edge-tap page turner included, so register
/// after `DirectionalNavigationAdapter.bind(to:)`.
///
/// - Parameter isDisposed: Checked before reporting. A pointer event already in
///   flight when the view tore down must not reach a dead channel.
/// - Returns: The navigator's token. Pass it to `removeObserver` on teardown.
@MainActor
func observeTaps(
  on observable: InputObservable,
  reportingTo channel: ReadiumReaderChannel,
  isDisposed: @MainActor @escaping () -> Bool = { false }
) -> InputObservableToken {
  observable.addObserver(
    .tap { event in
      if !isDisposed() { channel.onTap(position: event.location) }
      return false
    }
  )
}
