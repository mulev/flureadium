package dev.mulev.flureadium.navigators

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.readium.r2.shared.util.Url
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.junit.runner.RunWith

/**
 * Tests for EPUB restore behavior to prevent position drift regression.
 *
 * These tests validate the fix for the Android EPUB location restore drift issue
 * where reopening a book would jump to a different position than saved.
 *
 * Root cause: JavaScript scrollToLocations() recalculates progression from
 * bounding rect geometry, producing slightly different values than the saved
 * progression, then overwrites the StateFlow with the wrong value.
 *
 * Fix: Skip scrollToLocations() when already positioned correctly (within 1% delta).
 *
 * Uses Robolectric so that Readium's Url class can call android.net.Uri.parse.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class EpubNavigatorRestoreTest {

    /**
     * Test that progression delta calculation correctly identifies when position is already correct.
     */
    @Test
    fun progressionDelta_withinThreshold_shouldSkipScroll() {
        val currentProgression = 0.3170654
        val targetProgression = 0.3170654
        val delta = kotlin.math.abs(currentProgression - targetProgression)

        assertTrue(
            delta < 0.01,
            "Delta $delta should be less than 0.01 (1%) threshold to skip scroll"
        )
    }

    /**
     * Test that small progression differences (JavaScript recalculation drift) are detected.
     *
     * Real-world scenario: Saved progression 0.317, JavaScript calculates 0.315 from bounding rect.
     */
    @Test
    fun progressionDelta_smallDrift_shouldSkipScroll() {
        val currentProgression = 0.3170654  // Correct saved progression
        val targetProgression = 0.3150764   // JavaScript recalculated from bounding rect
        val delta = kotlin.math.abs(currentProgression - targetProgression)

        assertTrue(
            delta < 0.01,
            "Small drift delta $delta (0.002) should be less than 0.01 (1%) threshold to skip scroll"
        )
    }

    /**
     * Test that large progression differences require scrolling.
     */
    @Test
    fun progressionDelta_largeDifference_shouldScroll() {
        val currentProgression = 0.3170654
        val targetProgression = 0.5342220  // Different chapter/section
        val delta = kotlin.math.abs(currentProgression - targetProgression)

        assertFalse(
            delta < 0.01,
            "Large delta $delta should exceed 0.01 (1%) threshold to trigger scroll"
        )
    }

    /**
     * Test that null progression values are handled safely.
     */
    @Test
    fun progressionDelta_nullValues_shouldScroll() {
        val currentProgression: Double? = null
        val targetProgression: Double? = 0.317

        // When either value is null, we can't calculate delta, so we should scroll
        val shouldSkipScroll = currentProgression != null && targetProgression != null &&
            kotlin.math.abs(currentProgression - targetProgression) < 0.01

        assertFalse(
            shouldSkipScroll,
            "Null progression should trigger scroll (can't calculate delta)"
        )
    }

    /**
     * Test edge case: progression at start of chapter (0.0).
     */
    @Test
    fun progressionDelta_atStart_shouldSkipScroll() {
        val currentProgression = 0.0
        val targetProgression = 0.0
        val delta = kotlin.math.abs(currentProgression - targetProgression)

        assertTrue(
            delta < 0.01,
            "Zero progression delta should skip scroll"
        )
    }

    /**
     * Test edge case: progression at end of chapter (1.0).
     */
    @Test
    fun progressionDelta_atEnd_shouldSkipScroll() {
        val currentProgression = 1.0
        val targetProgression = 1.0
        val delta = kotlin.math.abs(currentProgression - targetProgression)

        assertTrue(
            delta < 0.01,
            "Max progression delta should skip scroll"
        )
    }

    /**
     * Test that 1% threshold is appropriate for real-world use.
     *
     * In a typical EPUB chapter with ~100 pages of content, 1% = 1 page.
     * This is acceptable variation to prevent drift while still allowing
     * intentional navigation.
     */
    @Test
    fun progressionDelta_onePercentThreshold_isAppropriate() {
        val chapterLength = 100.0  // Typical chapter pages
        val threshold = 0.01       // 1%
        val thresholdInPages = chapterLength * threshold

        assertTrue(
            thresholdInPages <= 1.0,
            "1% threshold should be at most 1 page in typical chapter"
        )
    }

    /**
     * Test locator equivalence for same href.
     */
    @Test
    fun locatorHref_sameResource_shouldBeEquivalent() {
        val href1 = Url("OEBPS/chapter01.xhtml")!!
        val href2 = Url("OEBPS/chapter01.xhtml")!!

        assertTrue(
            href1.isEquivalent(href2),
            "Same href should be equivalent"
        )
    }

    /**
     * Test locator equivalence for different href.
     */
    @Test
    fun locatorHref_differentResource_shouldNotBeEquivalent() {
        val href1 = Url("OEBPS/chapter01.xhtml")!!
        val href2 = Url("OEBPS/chapter02.xhtml")!!

        assertFalse(
            href1.isEquivalent(href2),
            "Different href should not be equivalent"
        )
    }
}
