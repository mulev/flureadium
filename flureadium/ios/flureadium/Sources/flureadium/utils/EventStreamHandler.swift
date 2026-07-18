import Flutter

/// A minimal seam over `EventStreamHandler` so event routing (e.g. the plugin's
/// error channel) can be unit-tested without constructing a real Flutter event
/// channel, which requires a binary messenger.
protocol EventStreamSink: AnyObject {
  func sendEvent(_ event: Any?)
  func dispose()
}

class EventStreamHandler: NSObject, FlutterStreamHandler, EventStreamSink {

  private let TAG: String
  private let streamName: String
  private var channel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  public func sendEvent(_ event: Any?) {
    print(TAG, "sendEvent")
    eventSink?(event)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    print(TAG, "onListen: \(streamName)")
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    print(TAG, "onCancel: \(streamName)")
    eventSink = nil
    return nil
  }

  func dispose() {
    print(TAG, "dispose")
    // Send end-of-stream so Flutter closes its subscription, then clear the
    // local sink so further sendEvent calls are no-ops.
    // Do NOT call channel.setStreamHandler(nil) here: that unregisters the
    // handler synchronously, but Flutter still needs to complete the "cancel"
    // round-trip. Removing the handler before that arrives causes a
    // MissingPluginException on the Dart side.
    eventSink?(FlutterEndOfEventStream)
    eventSink = nil
  }

  init(withName streamName: String, messenger: FlutterBinaryMessenger) {
    self.streamName = streamName
    TAG = "EventStreamHandler[\(streamName)]"
    channel = FlutterEventChannel(name: "dev.mulev.flureadium/\(streamName)", binaryMessenger: messenger)
    super.init()

    channel.setStreamHandler(self)
  }
}
