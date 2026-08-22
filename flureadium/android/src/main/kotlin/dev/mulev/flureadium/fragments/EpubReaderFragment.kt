package dev.mulev.flureadium.fragments

import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import dev.mulev.flureadium.EdgeTapInterceptView
import dev.mulev.flureadium.FlutterNavigationConfig
import dev.mulev.flureadium.R
import dev.mulev.flureadium.ReadiumReader
import dev.mulev.flureadium.models.EpubReaderViewModel
import dev.mulev.flureadium.readerCoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.plus
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl


private const val TAG = "EpubReaderFragment"

private var instanceNo = 0

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class EpubReaderFragment : VisualReaderFragment(), EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener,
    CoroutineScope by (MainScope() + readerCoroutineExceptionHandler(TAG)) {

    interface Listener {
        /**
         * Called when a page has finished loading.
         */
        fun onPageLoaded()

        /**
         * Called when this fragment has let go of its Readium navigator, so
         * anything registered on that navigator has to be released too.
         *
         * onPause removes the navigator fragment and its WebViews. Without this,
         * a listener registered on it stays registered and keeps it alive until
         * the next page load rebinds — a retention window nobody owned.
         */
        fun onNavigatorReleased()

        /**
         * Called when the current page has changed.
         */
        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)

        /**
         * Called when an external link is activated.
         */
        fun onExternalLinkActivated(url: AbsoluteUrl)
    }

    var listener: Listener? = null

    val started = MutableStateFlow(false)

    private var edgeTapInterceptView: EdgeTapInterceptView? = null
    private var storedNavigationConfig: FlutterNavigationConfig? = null
    private var storedIsScrollMode: Boolean? = null

    private val instance = ++instanceNo

    private var epubNavigator
        get() = navigator as? EpubNavigatorFragment
        set(value) {
            navigator = value
        }

    private val epubVm
        get() = vm as EpubReaderViewModel?

    @ExperimentalReadiumApi
    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        listener?.onExternalLinkActivated(url)
    }

    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
        Log.d(
            TAG,
            "::onPageChanged $pageIndex/$totalPages ${locator.href} ${locator.locations.progression}"
        )
        listener?.onPageChanged(pageIndex, totalPages, locator)
    }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")
        listener?.onPageLoaded()
    }

    suspend fun firstVisibleElementLocator(): Locator? {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::firstVisibleElementLocator. Navigator not ready.")
            return null
        }

        return navigator.firstVisibleElementLocator()
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String,
    ) {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::applyDecorations. Navigator not ready.")
            return
        }

        navigator.applyDecorations(decorations, group)
    }

    /**
     * Evaluate JavaScript in the context of the navigator's WebView.
     * NOTE: Returns null on error and if script returns null/undefined.
     */
    suspend fun evaluateJavascript(script: String): String? {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::evaluateJavascript. Navigator not ready.")
            return null
        }

        return navigator.evaluateJavascript(script)
    }

    /**
     * Check if the reader is ready.
     */
    suspend fun isReaderReady(): Boolean {
        return started.value && evaluateJavascript("window.epubPage.isReaderReady();") == "true"
    }

    /**
     * Update the reader preferences.
     */
    fun updatePreferences(preferences: EpubPreferences) {
        Log.d(TAG, "::updatePreferences")
        epubNavigator?.submitPreferences(preferences)
    }

    /**
     * Apply a navigation config received from Flutter. Stored so it can be
     * re-applied when the overlay is re-created after a lifecycle pause/resume.
     */
    fun setNavigationConfig(config: FlutterNavigationConfig) {
        storedNavigationConfig = config
        edgeTapInterceptView?.applyConfig(config)
    }

    /**
     * Enable or disable all overlay gestures when the EPUB reader enters/exits
     * vertical scroll mode. In scroll mode Readium's WebView handles scrolling.
     *
     * Stored for the same reason the navigation config is: onPause drops the
     * overlay and onResume builds a new one, which starts paginated. Without
     * this, a background/foreground cycle in scroll mode left the fresh overlay
     * claiming both edge strips again — swallowing scroll touches there and
     * stopping `onTap` from firing, until the next setPreferences round trip.
     */
    fun setScrollMode(isScrollMode: Boolean) {
        storedIsScrollMode = isScrollMode
        edgeTapInterceptView?.setScrollMode(isScrollMode)
    }

    /**
     * Navigate left (previous page).
     */
    fun goLeft(animated: Boolean) {
        Log.d(TAG, "::goLeft")
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::goLeft. Navigator not ready.")
            return
        }

        if (navigator.goBackward(animated)) {
            Log.d(TAG, "::goLeft: Went back.")
        } else {
            Log.d(TAG, "::goLeft: Couldn't go back.")
        }
    }

    /**
     * Navigate right (next page).
     */
    fun goRight(animated: Boolean) {
        Log.d(TAG, "::goRight")
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::goRight. Navigator not ready.")
            return
        }

        if (navigator.goForward(animated)) {
            Log.d(TAG, "::goRight: Went forward.")
        } else {
            Log.d(TAG, "::goRight: Couldn't go forward.")
        }
    }

    /**
     * Android lifecycle resume method, reattaches the navigator if needed.
     */
    override fun onResume() {
        try {
            Log.d(TAG, "::onResume - $instance - $attachingNavigatorFragment")

            if (epubVm == null) {
                Log.d(TAG, "::onResume - $instance - missing view model")
                return
            }

            if (attachingNavigatorFragment) {
                Log.d(TAG, "::onResume - $instance - don't attach navigator")
                return
            }

            // Recreate/attach the navigator after soft suspend.
            attachNavigator()
        } finally {
            super.onResume()
            Log.d(TAG, "::onResume - $instance - ended")
        }
    }

    /**
     * Android lifecycle view created method, creates and attaches the navigator.
     */
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        try {
            super.onViewCreated(view, savedInstanceState)

            Log.d(TAG, "::onViewCreated - $instance $view, $savedInstanceState")

            val model = epubVm
            if (model == null) {
                Log.d(TAG, "::onViewCreated - $instance - missing reader data")
                return
            }

            // Prevent onResume from attempting to add the navigator while we work.
            attachingNavigatorFragment = true

            lifecycleScope.launch {
                if (ReadiumReader.currentPublication != null) {
                    Log.d(TAG, "::onViewCreated - $instance - attach navigator")
                    attachNavigator()
                } else {
                    Log.d(TAG, "::onViewCreated - $instance - publication is missing")
                }

                attachingNavigatorFragment = false
            }
        } finally {
            Log.d(TAG, "::onViewCreated - $instance - ended")
        }
    }

    /**
     * Android lifecycle pause method, detaches the navigator to save resources and prevent caches.
     */
    override fun onPause() {
        try {
            Log.d(TAG, "::onPause - $instance")

            val savedLocator = currentLocator?.value
            epubVm?.locator = savedLocator
            Log.d(TAG, "::onPause - saved locator: href=${savedLocator?.href} prog=${savedLocator?.locations?.progression}")

            epubNavigator?.let { fragment ->
                childFragmentManager.commitNow {
                    remove(fragment)
                }
            }

            epubNavigator = null
            started.value = false

            attachingNavigatorFragment = false

            edgeTapInterceptView?.let { (view as? FrameLayout)?.removeView(it) }
            edgeTapInterceptView = null

            // After the navigator is gone, not before: the listener releases what
            // it registered on it, and holding that registration through a pause
            // would keep the removed fragment and its WebViews alive.
            listener?.onNavigatorReleased()

            super.onPause()
        } finally {
            Log.d(TAG, "::onPause - $instance - ended")
        }
    }

    private var attachingNavigatorFragment = false

    /**
     * Attach the navigator fragment to this reader fragment.
     */
    private fun attachNavigator() {
        Log.d(TAG, "::attachNavigator() - $instance")
        if (navigator != null) {
            Log.d(TAG, "::attachNavigator() - $instance - already attached")
            return
        }

        val model = epubVm
        if (model == null) {
            Log.e(TAG, "::attachNavigator() - $instance - missing view model")
            return
        }

        if (ReadiumReader.currentPublication == null) {
            Log.e(TAG, "::attachNavigator() - $instance - missing publication")
            return
        }

        val preferences = model.preferences ?: EpubPreferences()
        model.preferences = preferences


        // The overlay a resume rebuilds starts paginated, so its scroll state has
        // to be handed to it again. What Flutter last said wins; the navigator's
        // own preference covers a reader opened straight into scroll mode, which
        // never gets a setPreferences round trip at all.
        val isScrollMode = seedScrollMode(storedIsScrollMode, preferences.scroll)
        val navigatorFactory = model.navigatorFactory!!
        val fragmentFactory = navigatorFactory.createFragmentFactory(
            configuration = EpubNavigatorFragment.Configuration(
                shouldApplyInsetsPadding = false,

                // DFG: This will be relative to your app's src/main/assets/ folder.
                // To reference assets from other flutter packages use 'flutter_assets/packages/<package>/assets/.*'
                // Readium uses WebViewAssetLoader.AssetsPathHandler under the surface.
                servedAssets = listOf(
                    "flutter_assets/packages/flureadium/assets/.*",
                )
            ),
            initialLocator = model.locator,
            listener = this,
            paginationListener = this,
            initialPreferences = preferences,
        )

        val epubNavigator = fragmentFactory.instantiate(
            requireActivity().classLoader,
            EpubNavigatorFragment::class.java.name
        ) as EpubNavigatorFragment

        Log.d(TAG, "::attachNavigator - $instance - add fragment")
        childFragmentManager.commitNow {
            add(
                R.id.fragment_reader_container,
                epubNavigator,
                NAVIGATOR_FRAGMENT_TAG,
            )
        }

        navigator = epubNavigator
        Log.d(TAG, "::attachNavigator() - $instance - got navigator = $navigator")

        started.value = true

        // Add edge tap overlay on top of the navigator
        val rootView = view as? FrameLayout
        if (rootView != null) {
            val overlay = EdgeTapInterceptView(requireContext())
            overlay.layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            overlay.wireCallbacks(
                onLeft = { goLeft(animated = true) },
                onRight = { goRight(animated = true) },
                onSwipeLeft = { goRight(animated = true) },
                onSwipeRight = { goLeft(animated = true) },
            )
            configureOverlay(overlay, storedNavigationConfig, isScrollMode)
            rootView.addView(overlay)
            edgeTapInterceptView = overlay
        }
    }

    companion object {
        private const val NAVIGATOR_FRAGMENT_TAG = "READIUM_EPUB_READER_FRAGMENT"
    }
}
