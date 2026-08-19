package dev.mulev.flureadium.models

import org.readium.adapter.pdfium.navigator.PdfiumEngineProvider
import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.adapter.pdfium.navigator.PdfiumPreferencesEditor
import org.readium.adapter.pdfium.navigator.PdfiumSettings
import org.readium.r2.navigator.pdf.PdfNavigatorFactory
import org.readium.r2.shared.ExperimentalReadiumApi

open class PdfReaderViewModel : ReaderViewModel() {
    var fit: org.readium.r2.navigator.preferences.Fit? = null
    var scroll: Boolean? = null
    var spread: org.readium.r2.navigator.preferences.Spread? = null
    var offsetFirstPage: Boolean? = null

    @OptIn(ExperimentalReadiumApi::class)
    var navigatorFactory: PdfNavigatorFactory<PdfiumSettings, PdfiumPreferences, PdfiumPreferencesEditor>? = null

    @OptIn(ExperimentalReadiumApi::class)
    var engineProvider: PdfiumEngineProvider? = null
}
