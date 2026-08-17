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
/// Mirrors Android's `events/TextLocatorEventChannel.kt`.
final class TextLocatorEventStream: EventStreamHandler {

  private let currentLocatorJson: () -> String?

  init(
    withName streamName: String,
    messenger: FlutterBinaryMessenger,
    currentLocatorJson: @escaping () -> String?
  ) {
    self.currentLocatorJson = currentLocatorJson
    super.init(withName: streamName, messenger: messenger)
  }

  override func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    let error = super.onListen(withArguments: arguments, eventSink: events)
    if let json = currentLocatorJson() {
      sendEvent(json)
    }
    return error
  }
}
