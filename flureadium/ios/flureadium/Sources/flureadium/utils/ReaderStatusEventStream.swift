import Flutter
import Foundation

/// Reader-status stream that replays the latest status to a late subscriber.
///
/// A reader view reports "loading" — and an audio-only host also reports
/// "ready" — from its `init`, while the platform view is still being created.
/// That runs before Flutter replies to Dart, so before a host app can subscribe
/// from `ReadiumReaderWidget.onReady`. `EventStreamHandler` sends straight into
/// its sink, so at that point the whole first status sequence would be dropped
/// and a host waiting for "ready" would wait forever.
///
/// Only the latest status is kept: status is a state, not a log, and nothing
/// may accumulate while no one listens. Mirrors Android's
/// `events/ReaderStatusEventChannel.kt`.
final class ReaderStatusEventStream: EventStreamHandler {

  private var pendingStatus: Any?

  override func sendEvent(_ event: Any?) {
    guard eventSink != nil else {
      pendingStatus = event
      return
    }
    super.sendEvent(event)
  }

  override func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    let error = super.onListen(withArguments: arguments, eventSink: events)
    if let pending = pendingStatus {
      pendingStatus = nil
      super.sendEvent(pending)
    }
    return error
  }

  // onCancel is deliberately not overridden: the superclass clears `eventSink`,
  // so a status sent while Dart is between subscriptions — a publication swap —
  // buffers again on its own and reaches the next subscriber.

  override func dispose() {
    // The view is going away; a status buffered for a subscriber that never
    // arrived is stale and must not surface on the next view's subscription.
    pendingStatus = nil
    super.dispose()
  }
}
