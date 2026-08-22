package dev.mulev.flureadium.navigators

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Pins how a restore reaches its target locator: the branch chosen for every
 * combination of current and target position, including the one percent skip that
 * shipped as the fix for Android position drift, and the arm/flush/clear ordering
 * that defers a scroll until a page can accept it.
 *
 * The collaborator is a real [EpubPageScript] over a recording evaluator, so the
 * assertions read the script text that would reach the page.
 *
 * Robolectric is required because Locator.fromJSON builds a Readium Url, which
 * calls android.net.Uri.parse.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class EpubScrollRestoreTest {

    private class Recorder {
        val scripts = mutableListOf<String>()
        val navigated = mutableListOf<Locator>()

        suspend fun evaluate(script: String): String? {
            scripts += script
            return null
        }

        suspend fun go(locator: Locator, animated: Boolean): Boolean {
            navigated += locator
            return true
        }
    }

    private fun restoreWith(recorder: Recorder, current: Locator? = null) = EpubScrollRestore(
        page = EpubPageScript(evaluate = recorder::evaluate, verticalScroll = { false }),
        currentLocator = { current },
        go = recorder::go,
    )

    private fun locatorWithLocations(href: String, locations: String): Locator =
        Locator.fromJSON(
            JSONObject(
                """
                {
                  "href": "$href",
                  "type": "application/xhtml+xml",
                  "locations": { $locations }
                }
                """.trimIndent()
            )
        )!!

    private fun locator(href: String = CHAPTER_1, progression: Double? = null): Locator =
        locatorWithLocations(href, progression?.let { "\"progression\": $it" } ?: "")

    private fun scrollScript(locator: Locator): String =
        "window.epubPage.scrollToLocations(${locator.locations.toJSON()},false,false);"

    @Test
    fun restoreDecision_navigatesToADifferentResource() {
        assertEquals(
            RestoreDecision.Go,
            restoreDecision(locator(CHAPTER_1, 0.1), locator(CHAPTER_2, 0.5))
        )
    }

    @Test
    fun restoreDecision_scrollsWhenThereIsNoCurrentLocator() {
        assertEquals(RestoreDecision.Scroll, restoreDecision(null, locator(CHAPTER_1, 0.5)))
    }

    @Test
    fun restoreDecision_staysWhenTheTargetHasNothingToScrollTo() {
        assertEquals(
            RestoreDecision.Stay,
            restoreDecision(locator(CHAPTER_1, 0.1), locatorWithLocations(CHAPTER_1, ""))
        )
    }

    @Test
    fun restoreDecision_staysWithinOnePercentOfTheCurrentPosition() {
        assertEquals(
            RestoreDecision.Stay,
            restoreDecision(locator(CHAPTER_1, 0.3170654), locator(CHAPTER_1, 0.3150764))
        )
    }

    @Test
    fun restoreDecision_scrollsBeyondOnePercentOfTheCurrentPosition() {
        assertEquals(
            RestoreDecision.Scroll,
            restoreDecision(locator(CHAPTER_1, 0.317), locator(CHAPTER_1, 0.5))
        )
    }

    @Test
    fun restoreDecision_scrollsAtExactlyOnePercent() {
        assertEquals(
            RestoreDecision.Scroll,
            restoreDecision(locator(CHAPTER_1, 0.30), locator(CHAPTER_1, 0.31))
        )
    }

    @Test
    fun restoreDecision_scrollsWhenEitherSideHasNoProgression() {
        val domRangeTarget = locatorWithLocations(
            CHAPTER_1,
            """"domRange": { "start": { "cssSelector": "p:nth-child(2)", "textNodeIndex": 0 } }"""
        )

        assertEquals(
            RestoreDecision.Scroll,
            restoreDecision(locator(CHAPTER_1, 0.5), domRangeTarget)
        )
        assertEquals(
            RestoreDecision.Scroll,
            restoreDecision(locatorWithLocations(CHAPTER_1, ""), locator(CHAPTER_1, 0.5))
        )
    }

    @Test
    fun restoreDecision_honoursTheStartAndTheEndOfAResource() {
        assertEquals(
            RestoreDecision.Stay,
            restoreDecision(locator(CHAPTER_1, 0.0), locator(CHAPTER_1, 0.0))
        )
        assertEquals(
            RestoreDecision.Scroll,
            restoreDecision(locator(CHAPTER_1, 1.0), locator(CHAPTER_1, 0.0))
        )
    }

    @Test
    fun arm_defersTheScrollTheLocatorAsksFor() = runTest {
        val recorder = Recorder()
        val target = locator(CHAPTER_1, 0.42)

        restoreWith(recorder).apply {
            arm(target)
            flush()
        }

        assertEquals(scrollScript(target), recorder.scripts.single())
    }

    @Test
    fun arm_ignoresALocatorWithNothingToScrollTo() = runTest {
        val recorder = Recorder()

        restoreWith(recorder).apply {
            arm(locatorWithLocations(CHAPTER_1, ""))
            flush()
        }

        assertTrue(recorder.scripts.isEmpty())
    }

    @Test
    fun arm_ignoresAMissingLocator() = runTest {
        val recorder = Recorder()

        restoreWith(recorder).apply {
            arm(null)
            flush()
        }

        assertTrue(recorder.scripts.isEmpty())
    }

    @Test
    fun flush_scrollsAtMostOncePerArming() = runTest {
        val recorder = Recorder()

        restoreWith(recorder).apply {
            arm(locator(CHAPTER_1, 0.42))
            flush()
            flush()
        }

        assertEquals(1, recorder.scripts.size)
    }

    @Test
    fun clear_dropsTheArmedScroll() = runTest {
        val recorder = Recorder()

        restoreWith(recorder).apply {
            arm(locator(CHAPTER_1, 0.42))
            clear()
            flush()
        }

        assertTrue(recorder.scripts.isEmpty())
    }

    @Test
    fun goTo_armsTheFollowUpScrollWhenItNavigates() = runTest {
        val recorder = Recorder()
        val restore = restoreWith(recorder, current = locator(CHAPTER_1, 0.1))
        val target = locator(CHAPTER_2, 0.5)

        restore.goTo(target, animated = true)

        assertEquals(listOf(target), recorder.navigated)
        assertTrue(recorder.scripts.isEmpty())

        restore.flush()

        assertEquals(scrollScript(target), recorder.scripts.single())
    }

    @Test
    fun goTo_doesNothingWhenTheReaderAlreadyHoldsThePosition() = runTest {
        val recorder = Recorder()

        restoreWith(recorder, current = locator(CHAPTER_1, 0.3170654))
            .goTo(locator(CHAPTER_1, 0.3150764), animated = false)

        assertTrue(recorder.scripts.isEmpty())
        assertTrue(recorder.navigated.isEmpty())
    }

    @Test
    fun goTo_scrollsWithinTheResourceWithoutNavigating() = runTest {
        val recorder = Recorder()
        val target = locator(CHAPTER_1, 0.5)

        restoreWith(recorder, current = locator(CHAPTER_1, 0.317)).goTo(target, animated = false)

        assertEquals(scrollScript(target), recorder.scripts.single())
        assertTrue(recorder.navigated.isEmpty())
    }

    private companion object {
        const val CHAPTER_1 = "OEBPS/chapter01.xhtml"
        const val CHAPTER_2 = "OEBPS/chapter02.xhtml"
    }
}
