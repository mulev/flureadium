package dev.mulev.flureadium.navigators

import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commitNow
import com.github.barteksc.pdfviewer.PDFView
import dev.mulev.flureadium.EdgeTapInterceptView
import dev.mulev.flureadium.FlutterNavigationConfig
import dev.mulev.flureadium.FlutterPdfPreferences
import dev.mulev.flureadium.FlutterPdfScrollMode
import dev.mulev.flureadium.ReadiumReaderWidget.Companion.NAVIGATOR_FRAGMENT_TAG
import dev.mulev.flureadium.fragments.PdfReaderFragment
import dev.mulev.flureadium.models.PdfReaderViewModel
import dev.mulev.flureadium.withScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.adapter.pdfium.navigator.PdfiumEngineProvider
import org.readium.r2.navigator.pdf.PdfNavigatorFactory
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl

private const val TAG = "PdfNavigator"
private const val currentVisualCurrentLocatorKey = "currentVisualCurrentLocator"
private const val pdfPreferencesKey = "pdfPreferences"

/**
 * PdfNavigator wraps PdfReaderFragment and provides methods to interact with PDF reading.
 * It follows the same pattern as EpubNavigator for consistency.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class PdfNavigator : BaseNavigator, PdfReaderFragment.Listener {
    private var flutterPreferences: FlutterPdfPreferences

    constructor(
        publication: Publication,
        initialLocator: Locator?,
        visualListener: VisualListener,
        initialPreferences: FlutterPdfPreferences = FlutterPdfPreferences()
    ) : super(publication, initialLocator) {
        this.flutterPreferences = initialPreferences
        this.visualListener = visualListener

        this.state[currentVisualCurrentLocatorKey] = initialLocator
        this.state[pdfPreferencesKey] = initialPreferences
    }

    /**
     * VisualListener for PDF navigator events.
     * Mirrors the EpubNavigator.VisualListener interface.
     */
    interface VisualListener {
        /**
         * Called when a page has loaded.
         */
        fun onPageLoaded()

        /**
         * Called when the current page has changed.
         */
        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)

        /**
         * Called when an external link has been tapped.
         */
        fun onExternalLinkActivated(url: AbsoluteUrl)

        /**
         * Called when the user tapped the content and Readium handled nothing
         * internally — no internal link, no interactive element.
         *
         * Coordinates are logical pixels relative to the navigator view.
         */
        fun onTap(x: Double, y: Double)

        /**
         * Called when the current locator has changed.
         */
        fun onVisualCurrentLocationChanged(locator: Locator)

        /**
         * Called when the visual reader is ready.
         */
        fun onVisualReaderIsReady()
    }

    val visualListener: VisualListener

    /**
     * PdfReaderFragment instance used as navigator.
     */
    private var pdfNavigator: PdfReaderFragment? = null

    /**
     * Forwards content taps from whichever Readium navigator the fragment holds.
     */
    private val tapForwarder = NavigatorTapForwarder { x, y -> visualListener.onTap(x, y) }

    /**
     * Reports throttled locator changes. Subscribed once, when the first page
     * load marks the navigator ready.
     */
    private val locatorSubscription = VisualLocatorSubscription()

    /**
     * Engine provider for PDF rendering.
     */
    private var engineProvider: PdfiumEngineProvider? = null

    /**
     * Navigation config last received from Flutter.
     *
     * Read when the pdfium adapter builds its PDFView, not when it is stored:
     * the plugin holds no reference to that view, so a flag that arrives while
     * a PDF is on screen applies from the next rebuild (a pause/resume cycle
     * or a reopen), never mid-document.
     */
    private var navigationConfig: FlutterNavigationConfig? = null

    /**
     * Applied to every PDFView the pdfium adapter builds.
     *
     * Readium runs this before it registers its own listeners — see the
     * comment in PdfiumDocumentFragment.reset() — so switching drag paging off
     * cannot disturb the `.onTap` callback this epic depends on. In
     * AndroidPdfViewer the flag gates only drag and fling: DragPinchManager
     * checks isSwipeEnabled() in onFling and onScroll, while
     * onSingleTapConfirmed reports the tap unconditionally.
     *
     * This is the only format whose swipe navigation is reachable at all.
     * EPUB pages through the internal R2WebView and CBZ through an androidx
     * ViewPager; neither exposes a toggle in Readium 3.1.2.
     */
    private val pdfViewConfigurator = object : PdfiumEngineProvider.Listener {
        override fun onConfigurePdfView(configurator: PDFView.Configurator) {
            // "Page Flip" means one page per swipe. PdfiumDocumentFragment.reset()
            // sets swipeHorizontal but no snapping, so without these two a
            // horizontal document scrolls sideways continuously. An absent
            // scrollMode resolves to vertical, which is not paginated.
            val paginated = flutterPreferences.scrollMode == FlutterPdfScrollMode.HORIZONTAL
            configurator.pageSnap(paginated)
            configurator.pageFling(paginated)
            // isScrollMode stays false on purpose: this flag gates all drag and
            // fling on the document, so the real mode would freeze a scrolling PDF.
            configurator.enableSwipe(
                EdgeTapInterceptView.effectiveSwipeEnabled(navigationConfig, isScrollMode = false)
            )
        }
    }

    /**
     * Current locator in the PDF navigator.
     */
    val currentLocator
        get() = pdfNavigator?.currentLocator

    /**
     * Checks when the fragment starts and is safe to use.
     */
    private val navigatorStarted
        get() = pdfNavigator!!.started

    override suspend fun initNavigator() {
        engineProvider = PdfiumEngineProvider(listener = pdfViewConfigurator)

        pdfNavigator = PdfReaderFragment().apply {
            vm = PdfReaderViewModel().apply {
                navigatorFactory = PdfNavigatorFactory(
                    publication,
                    pdfEngineProvider = this@PdfNavigator.engineProvider!!
                )
                locator = this@PdfNavigator.initialLocator
                preferences = this@PdfNavigator.flutterPreferences.toPdfiumPreferences()
                this.engineProvider = this@PdfNavigator.engineProvider
            }
            listener = this@PdfNavigator
        }
    }

    /**
     * Attach the PDF navigator fragment to the given FragmentManager and ViewGroup.
     */
    fun attachNavigator(fragmentManager: FragmentManager, viewGroup: ViewGroup) {
        val navigator = pdfNavigator ?: return
        mainScope.launch {
            fragmentManager.commitNow {
                add(viewGroup, navigator, NAVIGATOR_FRAGMENT_TAG)
            }
        }
    }

    /**
     * Go to a specific locator in the PDF navigator.
     */
    suspend fun go(locator: Locator, animated: Boolean): Boolean {
        val navigator = pdfNavigator
        if (navigator == null) {
            Log.d(TAG, "::go - pdfNavigator is null!")
            return false
        }

        return withScope(mainScope) {
            afterFragmentStarted()
            if (!navigator.go(locator, animated)) {
                Log.w(TAG, "::go -  FAILED!")
                return@withScope false
            }

            Log.d(TAG, "::go - returned true")

            return@withScope true
        }
    }

    /**
     * Apply new PDF preferences to the running navigator.
     *
     * Readium 3.1.2 applies these live: submitPreferences → applySettings →
     * reset(), which rebuilds the PDFView and re-runs [pdfViewConfigurator].
     *
     * Both local records are written before the call into Readium, not after.
     * `submitPreferences` resolves the Readium fragment's `viewModels()`
     * delegate and throws from a detached fragment; with the state write behind
     * it, that swallowed exception would leave `flutterPreferences` new and
     * `state[pdfPreferencesKey]` old, so a save/restore would silently revert
     * the reader's choice.
     */
    fun updatePreferences(preferences: FlutterPdfPreferences) {
        Log.d(TAG, "::updatePreferences")

        flutterPreferences = preferences
        state[pdfPreferencesKey] = preferences

        try {
            pdfNavigator?.updatePreferences(preferences.toPdfiumPreferences())
        } catch (ex: Exception) {
            Log.e(TAG, "Error applying PdfPreferences: $ex")
        }
    }

    override fun setupNavigatorListeners() {
        val navigator = pdfNavigator
        if (navigator == null) {
            Log.e(TAG, "::setupNavigatorListeners - pdfNavigator is null this should never happen")
            return
        }

        val job = locatorSubscription.subscribe(navigator.currentLocator, mainScope) { locator ->
            onCurrentLocatorChanges(locator)
            state[currentVisualCurrentLocatorKey] = locator
        }

        if (job == null) {
            Log.d(TAG, "::setupNavigatorListeners - currentLocator is null - navigator not ready?")
            return
        }

        jobs.add(job)
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentVisualCurrentLocatorKey,
                (state[currentVisualCurrentLocatorKey] as? Locator)?.toJSON()?.toString()
            )

            (state[pdfPreferencesKey] as? FlutterPdfPreferences)?.let { prefs ->
                putString(
                    pdfPreferencesKey,
                    FlutterPdfPreferences.toJSON(prefs).toString()
                )
            }
        }
    }

    override fun onNavigatorReleased() {
        // Mirrors the bind in onPageLoaded: the fragment has let the navigator go,
        // so nothing should still be registered on it.
        tapForwarder.unbind()
    }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")
        // The fragment drops its Readium navigator on pause and builds a new one
        // on resume, and hasNotifiedIsReady stops setupNavigatorListeners from
        // running again — so the tap registration follows the page load instead.
        tapForwarder.bindTo(pdfNavigator?.visualNavigator)
        visualListener.onPageLoaded()

        notifyIsReady()
    }

    private var hasNotifiedIsReady = false

    /**
     * Notify that the navigator is ready only once.
     */
    private fun notifyIsReady() {
        if (hasNotifiedIsReady) return

        hasNotifiedIsReady = true
        visualListener.onVisualReaderIsReady()
        setupNavigatorListeners()
    }

    override fun onPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator
    ) {
        visualListener.onPageChanged(pageIndex, totalPages, locator)
        state[currentVisualCurrentLocatorKey] = locator
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        visualListener.onExternalLinkActivated(url)
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        visualListener.onVisualCurrentLocationChanged(locator)
    }

    override suspend fun release() {
        tapForwarder.unbind()
        super.dispose()

        pdfNavigator?.let { fragment ->
            withContext(Dispatchers.Main) {
                fragment.parentFragmentManager.commitNow { remove(fragment) }
            }
        }
        pdfNavigator = null
        state.clear()
    }

    override fun dispose() {
        tapForwarder.unbind()
        super.dispose()

        mainScope.launch {
            pdfNavigator?.let { fragment ->
                fragment.parentFragmentManager.commitNow { remove(fragment) }
            }

            mainScope.coroutineContext.cancelChildren()
            pdfNavigator = null
        }

        state.clear()
    }

    fun setNavigationConfig(config: FlutterNavigationConfig) {
        navigationConfig = config
        pdfNavigator?.setNavigationConfig(config)
    }

    fun goLeft(animated: Boolean) {
        val navigator = pdfNavigator
        if (navigator == null) {
            Log.e(TAG, "::goLeft - pdfNavigator is null!")
            return
        }

        Log.d(TAG, "::goLeft")
        navigator.goLeft(animated)
    }

    fun goRight(animated: Boolean) {
        val navigator = pdfNavigator
        if (navigator == null) {
            Log.e(TAG, "::goRight - pdfNavigator is null!")
            return
        }

        Log.d(TAG, "::goRight")
        navigator.goRight(animated)
    }

    private suspend fun afterFragmentStarted() {
        if (navigatorStarted.value) return

        navigatorStarted.first { it }
    }

    /**
     * Go to a specific locator in the PDF navigator.
     */
    suspend fun goToLocator(locator: Locator, animated: Boolean) {
        mainScope.async {
            go(locator, animated)
        }.await()
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: VisualListener,
            state: Bundle
        ): PdfNavigator {
            val locator = state.getString(currentVisualCurrentLocatorKey)
                ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences = state.getString(pdfPreferencesKey)
                ?.let { string -> FlutterPdfPreferences.fromJSON(string) }
                ?: FlutterPdfPreferences()

            Log.d(TAG, "::restoreState - locator: $locator, preferences: $preferences")

            return PdfNavigator(publication, locator, listener, preferences)
        }
    }
}
