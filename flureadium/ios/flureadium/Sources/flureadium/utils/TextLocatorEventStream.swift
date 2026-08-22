import Flutter
import Foundation

/// Text-locator stream that answers a new subscriber with the reader's current
/// position.
///
/// Nothing is buffered: a page turn sent while no one is listening is dropped,
/// and a delivered locator is never replayed. What a new subscriber gets is a
/// live read from whichever reader view is mounted — so a host that subscribes
/// from `ReadiumReaderWidget.onReady` knows the position without waiting for
/// the next page turn. An image publication emits one locator per page, which
/// is why waiting was not good enough.
///
/// The answer arrives on the next main-actor turn, not inside `onListen`: the
/// provider reads a `VisualNavigatorDelegate` conformer, which SE-0316 isolates
/// to the main actor, while `onListen` is nonisolated and synchronous.
///
/// Mirrors Android's `events/TextLocatorEventChannel.kt`, which answers
/// synchronously instead — Kotlin has no actor isolation to hop across.
final class TextLocatorEventStream: EventStreamHandler {

  private let currentLocatorJson: @MainActor () -> String?

  init(
    withName streamName: String,
    messenger: FlutterBinaryMessenger,
    currentLocatorJson: @MainActor @escaping () -> String?
  ) {
    self.currentLocatorJson = currentLocatorJson
    super.init(withName: streamName, messenger: messenger)
  }

  override func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    let error = super.onListen(withArguments: arguments, eventSink: events)
    // The provider reads a VisualNavigatorDelegate conformer, which SE-0316
    // isolates to the main actor; onListen is nonisolated, so the read hops.
    // MainActor.assumeIsolated would avoid the hop but is iOS 17+ (target 13.4).
    // Nothing is buffered by the delay: the closure reads the live navigator at
    // delivery time, and a subscriber that cancelled in between has no sink, so
    // sendEvent is a no-op.
    Task { @MainActor in
      if let json = self.currentLocatorJson() {
        self.sendEvent(json)
      }
    }
    return error
  }
}
