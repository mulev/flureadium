package dev.mulev.flureadium.navigators

import android.util.Log
import dev.mulev.flureadium.canScroll
import kotlin.math.abs
import org.readium.r2.shared.publication.Locator

private const val TAG = "EpubScrollRestore"

/**
 * Progression is recalculated from bounding-rect geometry on every scroll, so a
 * restore to the position the reader already holds would write a slightly
 * different value back and drift the saved position. Anything under one percent
 * of the resource is treated as "already there".
 */
private const val PROGRESSION_SKIP_THRESHOLD = 0.01

/** How to reach a target locator from where the reader currently is. */
internal enum class RestoreDecision {
    /** A different resource: navigate, and let the page load do the scrolling. */
    Go,

    /** Same resource, close enough or nothing to scroll to: do nothing. */
    Stay,

    /** Same resource, a real distance away: scroll within the page. */
    Scroll,
}

internal fun restoreDecision(current: Locator?, target: Locator): RestoreDecision {
    // Null-safe by intent, not by accident: with no current locator there is
    // nothing to compare, and the reader is already on whatever page it opened,
    // so this scrolls rather than navigates.
    if (current?.href?.isEquivalent(target.href) == false) return RestoreDecision.Go
    if (!canScroll(target.locations)) return RestoreDecision.Stay

    val from = current?.locations?.progression
    val to = target.locations.progression
    if (from != null && to != null && abs(from - to) < PROGRESSION_SKIP_THRESHOLD) {
        return RestoreDecision.Stay
    }

    return RestoreDecision.Scroll
}

/**
 * Holds the scroll a page has not been able to perform yet.
 *
 * A locator names a position inside a resource, but the resource has to be
 * loaded before anything can scroll to it. Navigation therefore splits in two:
 * [goTo] decides and may navigate, [flush] performs the scroll once the page
 * load reports in.
 */
internal class EpubScrollRestore(
    private val page: EpubPageScript,
    private val currentLocator: () -> Locator?,
    private val go: suspend (Locator, Boolean) -> Boolean,
) {
    private var pending: Locator.Locations? = null

    /** Arms the scroll the initially requested locator asks for, if any. */
    fun arm(locator: Locator?) {
        pending = locator?.locations?.takeIf { canScroll(it) }
    }

    /** Drops the armed scroll, so an explicit navigation is not overridden by it. */
    fun clear() {
        pending = null
    }

    /** Performs the armed scroll, at most once per arming. */
    suspend fun flush() {
        val locations = pending ?: return
        pending = null
        page.scrollTo(locations, toStart = false)
    }

    /** Reaches [locator], by navigating, by scrolling, or by leaving things alone. */
    suspend fun goTo(locator: Locator, animated: Boolean) {
        val current = currentLocator()
        val decision = restoreDecision(current, locator)
        Log.d(
            TAG,
            "::goTo - $decision ${current?.href} -> ${locator.href} " +
                "prog=${current?.locations?.progression} -> ${locator.locations.progression}"
        )

        when (decision) {
            RestoreDecision.Go -> {
                pending = locator.locations
                go(locator, animated)
            }

            RestoreDecision.Stay -> Unit
            RestoreDecision.Scroll -> page.scrollTo(locator.locations, toStart = false)
        }
    }
}
