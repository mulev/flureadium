package dev.mulev.flureadium.navigators

import org.readium.r2.navigator.VisualNavigator
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.shared.ExperimentalReadiumApi

/**
 * Reports taps a Readium navigator did not handle itself, in logical pixels.
 *
 * Readium filters the event before it arrives: an internal link, a footnote or
 * any other interactive element is followed and never reaches [onTap]. What is
 * left is a tap on content, which is the only tap signal a reading host can act
 * on safely.
 *
 * Binding is keyed on the navigator instance because the reader fragments drop
 * their Readium navigator in onPause() and build a new one in onResume()
 * (EpubReaderFragment, PdfReaderFragment). Registering twice on the same
 * navigator would report every tap twice; leaving a recreated navigator
 * unregistered would report none. Both failures are invisible in a host that
 * toggles chrome on the callback, so the identity check is what makes them
 * impossible rather than merely unlikely.
 */
@OptIn(ExperimentalReadiumApi::class)
internal class NavigatorTapForwarder(
    private val forwardTap: (x: Double, y: Double) -> Unit,
) : InputListener {
    private var navigator: VisualNavigator? = null

    /** Registers on [navigator], moving the registration off the previous one. */
    fun bindTo(navigator: VisualNavigator?) {
        if (navigator == null || navigator === this.navigator) return

        this.navigator?.removeInputListener(this)
        navigator.addInputListener(this)
        this.navigator = navigator
    }

    /** Removes the registration, so a torn-down navigator holds no reference here. */
    fun unbind() {
        navigator?.removeInputListener(this)
        navigator = null
    }

    override fun onTap(event: TapEvent): Boolean {
        // publicationView is requireView() on every Readium navigator fragment, and
        // an EPUB tap arrives from the WebView's JavaScript bridge after a hop to
        // the main thread — late enough for onPause to have destroyed the view.
        // Throwing here would abort CompositeInputListener's `any { … }` before the
        // listeners behind this one run, and escape into the JS bridge.
        val view = runCatching { navigator?.publicationView }.getOrNull() ?: return false

        // TapEvent.point is in navigator-view pixels. Dart is given logical
        // pixels, matching what iOS sends, so the density divides it here.
        val density = view.resources.displayMetrics.density
        forwardTap((event.point.x / density).toDouble(), (event.point.y / density).toDouble())

        // false, not true: CompositeInputListener.onTap is `listeners.any { … }`,
        // which short-circuits, so consuming the event would starve every
        // listener registered after this one.
        return false
    }
}
