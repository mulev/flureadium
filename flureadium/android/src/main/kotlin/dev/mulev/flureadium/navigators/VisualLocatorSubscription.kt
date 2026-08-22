package dev.mulev.flureadium.navigators

import dev.mulev.flureadium.throttleLatest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import org.readium.r2.shared.publication.Locator
import kotlin.time.Duration.Companion.milliseconds

/**
 * A reader emits a locator per scroll frame. Hosts want reading positions, not
 * frames, so emissions are throttled to one per window: a scroll that leaves a
 * position and returns to it inside one window reports nothing new.
 *
 * The subscription is replaceable because the reader fragments drop their
 * Readium navigator in onPause() and build a new one in onResume(): the flow the
 * old navigator exposed stops emitting, so a caller that notices the swap has to
 * cancel and subscribe again or it reports nothing for the rest of the session.
 * Deciding when that happened is the caller's job — EpubNavigator tracks the
 * fragment identity, PDF and image have no such swap to notice.
 */
internal class VisualLocatorSubscription {
    private var job: Job? = null

    /**
     * Subscribes to [locators], replacing any previous subscription. Returns the
     * job so the caller can track it for disposal, or null when the navigator
     * has no locator flow yet.
     */
    fun subscribe(
        locators: StateFlow<Locator>?,
        scope: CoroutineScope,
        onLocator: (Locator) -> Unit,
    ): Job? {
        cancel()
        if (locators == null) return null

        return locators
            // No distinctUntilChanged: a StateFlow only resumes its collector
            // when the slot differs from the value last delivered, so the
            // throttle can never hand the same locator downstream twice.
            .throttleLatest(THROTTLE)
            .onEach(onLocator)
            .launchIn(scope)
            .also { job = it }
    }

    /** Cancels the current subscription, if any. */
    fun cancel() {
        job?.cancel()
        job = null
    }

    private companion object {
        val THROTTLE = 100.milliseconds
    }
}
