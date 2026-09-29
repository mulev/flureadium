package dev.mulev.flureadium.fragments

import dev.mulev.flureadium.models.PdfReaderViewModel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.runner.RunWith
import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.preferences.Axis
import org.readium.r2.navigator.preferences.Fit
import org.readium.r2.shared.ExperimentalReadiumApi
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Pins the store half of [PdfReaderFragment.updatePreferences].
 *
 * This is the line the reported defect was made of: the method used to have an
 * empty body, so a preference change was accepted over the method channel and
 * dropped. Submitting to the live navigator is only half the repair — the
 * fragment drops its navigator in onPause and builds a new one in onResume from
 * `PdfReaderViewModel.preferences`, so a value handed only to the current
 * navigator is lost on the next bounce and the reader silently returns to
 * pdfium's defaults.
 *
 * No navigator and no overlay are attached here on purpose: both calls in
 * `updatePreferences` are null-safe, which leaves the view-model write as the
 * single observable effect and keeps the test free of Readium's fragment
 * machinery.
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class PdfReaderFragmentPreferencesTest {

    @Test
    fun updatePreferences_storesThemForTheNextNavigatorBuild() {
        val fragment = PdfReaderFragment()
        val model = PdfReaderViewModel()
        fragment.vm = model

        fragment.updatePreferences(
            PdfiumPreferences(fit = Fit.CONTAIN, scrollAxis = Axis.HORIZONTAL)
        )

        assertEquals(
            PdfiumPreferences(fit = Fit.CONTAIN, scrollAxis = Axis.HORIZONTAL),
            model.preferences,
            "attachNavigator builds the next navigator from this field"
        )
    }

    @Test
    fun updatePreferences_overwritesAnEarlierChoice() {
        val fragment = PdfReaderFragment()
        val model = PdfReaderViewModel().apply {
            preferences = PdfiumPreferences(scrollAxis = Axis.HORIZONTAL)
        }
        fragment.vm = model

        fragment.updatePreferences(PdfiumPreferences(scrollAxis = Axis.VERTICAL))

        assertEquals(Axis.VERTICAL, model.preferences.scrollAxis)
    }

    @Test
    fun updatePreferences_withoutAViewModel_doesNotThrow() {
        // The host can call setPreferences before the reader has been enabled.
        PdfReaderFragment().updatePreferences(PdfiumPreferences(scrollAxis = Axis.VERTICAL))
    }
}
