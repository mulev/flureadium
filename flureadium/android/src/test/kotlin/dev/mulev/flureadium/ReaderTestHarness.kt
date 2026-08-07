package dev.mulev.flureadium

import android.content.ContextWrapper
import androidx.fragment.app.FragmentActivity
import dev.mulev.flureadium.events.ErrorEventChannel
import dev.mulev.flureadium.events.ReaderStatusEventChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.Robolectric

/**
 * Builds and observes a Robolectric-mounted reader for the JVM suite.
 *
 * Every reader test needs the same three things: a clean singleton, a way to
 * hear what the reader reports, and a widget mounted on a real FragmentActivity.
 * They used to be private copies inside each test class, which stopped scaling
 * once more than two classes needed them. Seeding and clearing the singleton's
 * private fields goes through ReadiumReaderFields.kt, which stays the one place
 * that knows the reflection.
 */

/**
 * Clears everything a reader test can seed on the singleton.
 *
 * ReadiumReader outlives each test class, so a field left behind leaks into the
 * next one. Call this in both setUp and tearDown.
 */
internal fun resetReaderState() {
    setReaderField("_currentPublication", null)
    setReaderField("epubNavigator", null)
    setReaderField("imageNavigator", null)
    setReaderField("pdfNavigator", null)
    setReaderField("isReadyEventChannel", null)
    setReaderField("readerStatusEventChannel", null)
    setReaderField("errorEventChannel", null)
    ReadiumReader.currentReaderWidget = null
}

/** Attaches a listener to the reader-status channel and records what it receives. */
internal fun subscribeToReaderStatus(): List<String> {
    val received = mutableListOf<String>()
    val channel = ReaderStatusEventChannel(mock(BinaryMessenger::class.java))
    setReaderField("readerStatusEventChannel", channel)
    channel.onListen(
        null,
        object : EventChannel.EventSink {
            override fun success(event: Any?) {
                received.add(event as String)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

            override fun endOfStream() = Unit
        }
    )
    return received
}

/** Attaches a listener to the error channel and records the payloads it receives. */
internal fun subscribeToErrorEvents(): List<Map<String, Any?>> {
    val received = mutableListOf<Map<String, Any?>>()
    val channel = ErrorEventChannel(mock(BinaryMessenger::class.java))
    setReaderField("errorEventChannel", channel)
    channel.onListen(
        null,
        object : EventChannel.EventSink {
            @Suppress("UNCHECKED_CAST")
            override fun success(event: Any?) {
                received.add(event as Map<String, Any?>)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

            override fun endOfStream() = Unit
        }
    )
    return received
}

/**
 * Mounts the reader widget on a Robolectric FragmentActivity.
 *
 * What kind of reader it becomes is decided by the publication seeded on the
 * singleton before the call: an audiobook makes it an audio host, no
 * publication at all makes it an EPUB reader whose enable fails.
 */
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
internal fun buildReaderWidget(): ReadiumReaderWidget {
    val activity = Robolectric.buildActivity(FragmentActivity::class.java).setup().get()
    return ReadiumReaderWidget(
        ContextWrapper(activity),
        1,
        emptyMap(),
        mock(BinaryMessenger::class.java)
    )
}

/** A publication that reports itself as conforming to one profile and nothing else. */
internal fun publicationConformingTo(profile: Publication.Profile): Publication {
    val publication = mock(Publication::class.java)
    `when`(publication.conformsTo(profile)).thenReturn(true)
    return publication
}
