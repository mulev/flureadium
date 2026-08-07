package dev.mulev.flureadium.events

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.launch

class ErrorEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<Map<String, Any?>>(messenger, "dev.mulev.flureadium/error") {

    // A reader failure is reported from ReadiumReaderWidget.init, which runs
    // inside the platform-view create call — before Flutter replies to Dart and
    // therefore before a host app can subscribe from onReady. Sending straight
    // into a null sink would drop exactly the errors that explain why the reader
    // never came up. Unlike reader status, an error is an event and not a state,
    // so pending errors keep their order; the cap stops them accumulating while
    // nobody listens, and it keeps the oldest because the first failure explains
    // the ones that follow.
    private val pendingErrors = ArrayDeque<Map<String, Any?>>()

    override fun sendEvent(data: Map<String, Any?>) {
        mainScope.launch {
            val sink = eventSink
            if (sink == null) {
                if (pendingErrors.size < MAX_PENDING_ERRORS) pendingErrors.addLast(data)
            } else {
                sink.success(data)
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        super.onListen(arguments, events)
        if (events == null) return
        while (pendingErrors.isNotEmpty()) {
            events.success(pendingErrors.removeFirst())
        }
    }

    override fun dispose() {
        // The channel is going away; errors buffered for a subscriber that
        // never arrived belong to the reader session that is ending and must
        // not surface on a later subscription. Same rule ReaderStatusEventChannel
        // follows for its held status.
        pendingErrors.clear()
        super.dispose()
    }

    private companion object {
        const val MAX_PENDING_ERRORS = 8
    }
}
