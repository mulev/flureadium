package dev.mulev.flureadium.events

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.Locator

/**
 * Event channel for sending text locator updates to Flutter.
 *
 * Nothing is buffered: a page turn sent while no one listens is dropped, and a
 * delivered locator is never replayed. A new subscriber is still told where the
 * reader is, read live at subscribe time.
 *
 * @param currentLocator where the reader is right now, asked at subscribe time.
 */
class TextLocatorEventChannel(
    messenger: BinaryMessenger,
    private val currentLocator: () -> Locator? = { null },
) : EventChannelWrapper<Locator>(messenger, "dev.mulev.flureadium/text-locator") {
    override fun sendEvent(data: Locator) {
        mainScope.launch {
            eventSink?.success(data.toJSON().toString())
        }
    }

    // An image publication emits one locator per page and its first one lands
    // before Dart can subscribe (ReadiumReaderWidget registers the platform
    // view, and onReady fires after), so without this a CBZ reader looks
    // position-less until the first page turn.
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        super.onListen(arguments, events)
        currentLocator()?.let { sendEvent(it) }
    }
}
