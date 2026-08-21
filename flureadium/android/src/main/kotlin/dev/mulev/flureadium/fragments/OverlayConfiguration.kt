package dev.mulev.flureadium.fragments

import dev.mulev.flureadium.EdgeTapInterceptView
import dev.mulev.flureadium.FlutterNavigationConfig

/**
 * Applies everything a freshly built [EdgeTapInterceptView] has to be told.
 *
 * The reader fragments drop their overlay in onPause() and build a new one in
 * onResume(), and a new overlay starts from its own defaults: gestures enabled,
 * paginated. Every piece of state the host set earlier has to be handed to it
 * again on that path, and the failure mode of forgetting one is silent — an
 * overlay that claims both edge strips over a scrolling WebView swallows the
 * touches and stops `onTap` from firing, with nothing logged.
 *
 * It lives here rather than inline in each fragment because both of them need
 * it, and because "what a rebuilt overlay is configured with" is then one thing
 * a test can drive without mounting a fragment.
 */
internal fun configureOverlay(
    overlay: EdgeTapInterceptView,
    config: FlutterNavigationConfig?,
    isScrollMode: Boolean,
) {
    config?.let { overlay.applyConfig(it) }
    overlay.setScrollMode(isScrollMode)
}

/**
 * The scroll state a rebuilt overlay should start from.
 *
 * [hostScroll] is what Flutter last said through `setNavigationConfig`'s sibling
 * path, `setPreferences` → `epubSetScrollMode`, and it wins whenever it exists:
 * `model.preferences` is only assigned when a navigator is built, so on a resume
 * it can still carry the value the reader was opened with and would otherwise
 * undo a later toggle.
 *
 * [preferenceScroll] is the navigator's own preference, which is all there is
 * before Flutter has said anything — a reader opened straight into scroll mode
 * never receives that round trip at all.
 */
internal fun seedScrollMode(hostScroll: Boolean?, preferenceScroll: Boolean?): Boolean =
    hostScroll ?: preferenceScroll ?: false
