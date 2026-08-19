package dev.mulev.flureadium.navigators

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Pins the `window.epubPage` contract: the exact script text sent for both entry
 * points, and how each reply shape the page can produce is decoded.
 *
 * Robolectric is required because Locator.fromJSON builds a Readium Url, which
 * calls android.net.Uri.parse.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class EpubPageScriptTest {

    private class FakeEvaluator(private val reply: String? = null) {
        val scripts = mutableListOf<String>()

        suspend fun evaluate(script: String): String? {
            scripts += script
            return reply
        }
    }

    private val locator = Locator(
        href = Url("OEBPS/chapter01.xhtml")!!,
        mediaType = MediaType.XHTML,
        locations = Locator.Locations(progression = 0.25)
    )

    private fun scriptWith(
        evaluator: FakeEvaluator,
        verticalScroll: () -> Boolean = { false }
    ) = EpubPageScript(evaluate = evaluator::evaluate, verticalScroll = verticalScroll)

    @Test
    fun locatorFragments_sendsTheLocatorAndTheHorizontalScrollFlag() = runTest {
        val evaluator = FakeEvaluator("null")

        scriptWith(evaluator, verticalScroll = { false }).locatorFragments(locator)

        assertEquals(
            "window.epubPage.getLocatorFragments(${locator.toJSON()}, false)",
            evaluator.scripts.single()
        )
    }

    @Test
    fun locatorFragments_sendsTheVerticalScrollFlagWhenTheReadingModeIsVertical() = runTest {
        val evaluator = FakeEvaluator("null")

        scriptWith(evaluator, verticalScroll = { true }).locatorFragments(locator)

        assertEquals(
            "window.epubPage.getLocatorFragments(${locator.toJSON()}, true)",
            evaluator.scripts.single()
        )
    }

    @Test
    fun scrollTo_readsTheScrollFlagPerCall() = runTest {
        val evaluator = FakeEvaluator()
        val flags = listOf(false, true).iterator()
        val script = scriptWith(evaluator, verticalScroll = { flags.next() })
        val locations = locator.locations

        script.scrollTo(locations, toStart = false)
        script.scrollTo(locations, toStart = false)

        assertEquals(
            listOf(
                "window.epubPage.scrollToLocations(${locations.toJSON()},false,false);",
                "window.epubPage.scrollToLocations(${locations.toJSON()},true,false);"
            ),
            evaluator.scripts
        )
    }

    @Test
    fun locatorFragments_decodesALocatorAnswer() = runTest {
        val evaluator = FakeEvaluator(
            """{"href":"OEBPS/chapter01.xhtml","type":"application/xhtml+xml",""" +
                """"locations":{"progression":0.5},"text":{"highlight":"hello"}}"""
        )

        val answer = scriptWith(evaluator).locatorFragments(locator)

        assertEquals("OEBPS/chapter01.xhtml", answer?.href.toString())
        assertEquals(0.5, answer?.locations?.progression)
        assertEquals("hello", answer?.text?.highlight)
    }

    @Test
    fun locatorFragments_returnsNullForANullAnswer() = runTest {
        assertNull(scriptWith(FakeEvaluator(null)).locatorFragments(locator))
    }

    @Test
    fun locatorFragments_returnsNullForTheStringNull() = runTest {
        assertNull(scriptWith(FakeEvaluator("null")).locatorFragments(locator))
    }

    @Test
    fun locatorFragments_returnsNullForTheStringUndefined() = runTest {
        assertNull(scriptWith(FakeEvaluator("undefined")).locatorFragments(locator))
    }

    @Test
    fun locatorFragments_returnsNullForAnUnparseableAnswer() = runTest {
        assertNull(scriptWith(FakeEvaluator("{ not json")).locatorFragments(locator))
    }

    @Test
    fun scrollTo_sendsLocationsScrollFlagAndToStart() = runTest {
        val evaluator = FakeEvaluator()
        val locations = locator.locations

        scriptWith(evaluator, verticalScroll = { false }).scrollTo(locations, toStart = true)

        assertEquals(
            "window.epubPage.scrollToLocations(${locations.toJSON()},false,true);",
            evaluator.scripts.single()
        )
    }
}
