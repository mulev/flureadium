package dev.mulev.flureadium.models

import org.readium.adapter.pdfium.navigator.PdfiumEngineProvider
import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.adapter.pdfium.navigator.PdfiumPreferencesEditor
import org.readium.adapter.pdfium.navigator.PdfiumSettings
import org.readium.r2.navigator.pdf.PdfNavigatorFactory
import org.readium.r2.shared.ExperimentalReadiumApi

open class PdfReaderViewModel : ReaderViewModel() {
    /**
     * Preferences the next navigator is built with.
     *
     * The fragment drops its navigator in onPause and builds a new one in
     * onResume, so this has to hold what the host last asked for, not just what
     * the reader opened with.
     */
    var preferences: PdfiumPreferences = PdfiumPreferences()

    @OptIn(ExperimentalReadiumApi::class)
    var navigatorFactory: PdfNavigatorFactory<PdfiumSettings, PdfiumPreferences, PdfiumPreferencesEditor>? = null

    @OptIn(ExperimentalReadiumApi::class)
    var engineProvider: PdfiumEngineProvider? = null
}
