package dev.mulev.flureadium

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.preferences.Axis
import org.readium.r2.navigator.preferences.Fit

/**
 * Unit tests for the Flutter → pdfium preference mapping.
 *
 * This is the boundary the Android PDF navigator is built and updated through:
 * [FlutterPdfPreferences.toPdfiumPreferences] is called once when the navigator
 * fragment is created and again on every `setPreferences` round trip. Before it
 * existed, neither call carried anything and every Android PDF rendered
 * pdfium's resolver defaults.
 *
 * The mapping touches no Android framework class, so no Robolectric runner is
 * needed.
 */
internal class FlutterPdfPreferencesPdfiumMappingTest {

    @Test
    fun scrollModeMapsToAxis() {
        assertEquals(
            Axis.VERTICAL,
            FlutterPdfPreferences(scrollMode = FlutterPdfScrollMode.VERTICAL).toPdfiumPreferences().scrollAxis
        )
        assertEquals(
            Axis.HORIZONTAL,
            FlutterPdfPreferences(scrollMode = FlutterPdfScrollMode.HORIZONTAL).toPdfiumPreferences().scrollAxis
        )
        // Not an oversight: PdfiumSettingsResolver turns a null axis into
        // Axis.VERTICAL, and that default belongs to it, not to this mapper.
        assertNull(FlutterPdfPreferences(scrollMode = null).toPdfiumPreferences().scrollAxis)
    }

    @Test
    fun bothFitConstantsSurvivePdfiumsRequire() {
        // PdfiumPreferences.init requires fit in (null, CONTAIN, WIDTH) and
        // throws otherwise. Constructing through the mapper runs that check
        // here, so a constant added to FlutterPdfFit without a legal mapping
        // fails in this test rather than on a device.
        assertEquals(Fit.WIDTH, FlutterPdfPreferences(fit = FlutterPdfFit.WIDTH).toPdfiumPreferences().fit)
        assertEquals(Fit.CONTAIN, FlutterPdfPreferences(fit = FlutterPdfFit.CONTAIN).toPdfiumPreferences().fit)
        assertNull(FlutterPdfPreferences(fit = null).toPdfiumPreferences().fit)
    }

    @Test
    fun pageLayoutAndOffsetFirstPageReachNothing() {
        // pdfium has no spread component at all, so these two are dropped on
        // purpose. This case is what says the drop is deliberate.
        val prefs = FlutterPdfPreferences(
            pageLayout = FlutterPdfPageLayout.DOUBLE,
            offsetFirstPage = true,
        )

        assertEquals(PdfiumPreferences(), prefs.toPdfiumPreferences())
    }
}
