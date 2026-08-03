package dev.mulev.flureadium.events

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.launch

class ReaderStatusEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<String>(messenger, "dev.mulev.flureadium/reader-status") {

    // ReadiumReaderWidget.init reports "loading", and an audio-only host also
    // reports "ready", while the platform view is still being created — before
    // Flutter replies to Dart, so before a host app can subscribe from
    // ReadiumReaderWidget.onReady. Sending straight into a null sink would drop
    // the first widget's whole status sequence, leaving a host that waits for
    // "ready" waiting forever. Only the latest pending status is kept: status
    // is a state, not a log, and nothing may accumulate while no one listens.
    private var pendingStatus: String? = null

    override fun sendEvent(data: String) {
        mainScope.launch {
            val sink = eventSink
            if (sink == null) {
                pendingStatus = data
            } else {
                sink.success(data)
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        super.onListen(arguments, events)
        pendingStatus?.let { status ->
            pendingStatus = null
            events?.success(status)
        }
    }
}
