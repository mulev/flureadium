package dev.mulev.flureadium.navigators

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.runner.RunWith
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Pins the throttled locator subscription every visual navigator shares.
 *
 * A reader emits a locator per scroll frame, so the subscription reports one per
 * 100ms window: a position that is left and returned to inside one window
 * reports nothing new, because the window's latest value is the one already
 * reported. That is asserted through virtual time — the flow is written, the
 * scheduler advanced past the window, and only then are the reports checked.
 *
 * No navigator and no fragment take part — a MutableStateFlow stands in for the
 * Readium navigator's locator flow, and a recording lambda for the caller.
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class VisualLocatorSubscriptionTest {

    private val subscription = VisualLocatorSubscription()

    @Test
    fun `reports the locator the flow already carries`() = runTest {
        val reported = mutableListOf<Locator>()
        val opened = locator(progression = 0.10)

        subscription.subscribe(MutableStateFlow(opened), backgroundScope) { reported += it }
        advancePastWindow()

        assertEquals(listOf(opened), reported)
    }

    @Test
    fun `collapses a burst inside one window to its latest locator`() = runTest {
        val reported = mutableListOf<Locator>()
        val opened = locator(progression = 0.10)
        val locators = MutableStateFlow(opened)

        subscription.subscribe(locators, backgroundScope) { reported += it }
        advancePastWindow()

        val firstScrolled = locator(progression = 0.20)
        locators.value = firstScrolled
        advanceInsideWindow()
        // Written while the window firstScrolled opened has not elapsed yet.
        locators.value = locator(progression = 0.30)
        advanceInsideWindow()
        locators.value = locator(progression = 0.40)
        advanceInsideWindow()
        val lastScrolled = locator(progression = 0.50)
        locators.value = lastScrolled
        advancePastWindow()

        assertEquals(listOf(opened, firstScrolled, lastScrolled), reported)
    }

    @Test
    fun `drops a locator equal to the one it last reported`() = runTest {
        val reported = mutableListOf<Locator>()
        val opened = locator(progression = 0.10)
        val scrolled = locator(progression = 0.20)
        val locators = MutableStateFlow(opened)

        subscription.subscribe(locators, backgroundScope) { reported += it }
        advancePastWindow()
        locators.value = scrolled
        advanceInsideWindow()

        // A scroll that leaves and comes back inside one window: the window's
        // latest value is the position already reported, so nothing happened.
        locators.value = opened
        advanceInsideWindow()
        locators.value = scrolled
        advancePastWindow()

        assertEquals(listOf(opened, scrolled), reported)
    }

    @Test
    fun `reports nothing for a navigator with no locator flow`() = runTest {
        val reported = mutableListOf<Locator>()

        val job = subscription.subscribe(null, backgroundScope) { reported += it }
        advancePastWindow()

        assertNull(job)
        assertEquals(emptyList(), reported)
    }

    @Test
    fun `replaces a previous subscription instead of adding to it`() = runTest {
        val reported = mutableListOf<Locator>()
        val paused = MutableStateFlow(locator(progression = 0.10))
        val resumedSeed = locator(progression = 0.50)
        val resumed = MutableStateFlow(resumedSeed)

        val pausedJob = subscription.subscribe(paused, backgroundScope) { reported += it }
        subscription.subscribe(resumed, backgroundScope) { reported += it }
        advancePastWindow()

        val afterResume = locator(progression = 0.60)
        resumed.value = afterResume
        val onTheDeadFlow = locator(progression = 0.20)
        paused.value = onTheDeadFlow
        advancePastWindow()

        assertTrue(pausedJob!!.isCancelled)
        assertEquals(listOf(resumedSeed, afterResume), reported)
    }

    @Test
    fun `stops reporting once cancelled`() = runTest {
        val reported = mutableListOf<Locator>()
        val locators = MutableStateFlow(locator(progression = 0.10))

        val job = subscription.subscribe(locators, backgroundScope) { reported += it }
        subscription.cancel()
        locators.value = locator(progression = 0.20)
        advancePastWindow()

        assertTrue(job!!.isCancelled)
        assertEquals(emptyList(), reported)
    }

    // MARK: - Harness

    private fun locator(progression: Double): Locator =
        Locator.fromJSON(
            JSONObject(
                """
                {
                  "href": "OEBPS/chapter01.xhtml",
                  "type": "application/xhtml+xml",
                  "locations": { "progression": $progression }
                }
                """.trimIndent()
            )
        )!!

    /** Advances past the throttle window, then drains what it released. */
    private fun TestScope.advancePastWindow() {
        advanceTimeBy(WINDOW + 50)
        runCurrent()
    }

    /** Advances without leaving the throttle window that is currently open. */
    private fun TestScope.advanceInsideWindow() {
        advanceTimeBy(10)
        runCurrent()
    }

    private companion object {
        /** The component's own throttle window, in virtual milliseconds. */
        const val WINDOW = 100L
    }
}
