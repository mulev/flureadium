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
import dev.mulev.flureadium.models.PdfReaderViewModel
import dev.mulev.flureadium.readerCoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.plus
import org.readium.r2.navigator.pdf.PdfNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl

private const val TAG = "PdfReaderFragment"

private var instanceNo = 0

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class PdfReaderFragment : VisualReaderFragment(), PdfNavigatorFragment.Listener,
    CoroutineScope by (MainScope() + readerCoroutineExceptionHandler(TAG)) {

    interface Listener {
        /**
         * Called when a page has finished loading.
         */
        fun onPageLoaded()

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

    private val instance = ++instanceNo

    private var pdfNavigator
        get() = navigator as? PdfNavigatorFragment<*, *>
        set(value) {
            navigator = value
        }

    private val pdfVm
        get() = vm as PdfReaderViewModel?

    @ExperimentalReadiumApi
    fun onExternalLinkActivated(url: AbsoluteUrl) {
        listener?.onExternalLinkActivated(url)
    }

    /**
     * Update the reader preferences.
     */
    fun updatePreferences(
        fit: org.readium.r2.navigator.preferences.Fit?,
        scroll: Boolean?,
        spread: org.readium.r2.navigator.preferences.Spread?,
        offsetFirstPage: Boolean?
    ) {
        Log.d(TAG, "::updatePreferences")
        // PDF preferences are set at navigator creation time
        // Readium's PdfNavigatorFragment doesn't support dynamic preference updates
        // like EpubNavigatorFragment does with submitPreferences()
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
     * Navigate left (previous page).
     */
    fun goLeft(animated: Boolean) {
        Log.d(TAG, "::goLeft")
        val navigator = pdfNavigator
        if (navigator == null) {
            Log.d(TAG, "::goLeft. Navigator not ready.")
            return
        }

        launch {
            if (navigator.goBackward(animated)) {
                Log.d(TAG, "::goLeft: Went back.")
            } else {
                Log.d(TAG, "::goLeft: Couldn't go back.")
            }
        }
    }

    /**
     * Navigate right (next page).
     */
    fun goRight(animated: Boolean) {
        Log.d(TAG, "::goRight")
        val navigator = pdfNavigator
        if (navigator == null) {
            Log.d(TAG, "::goRight. Navigator not ready.")
            return
        }

        launch {
            if (navigator.goForward(animated)) {
                Log.d(TAG, "::goRight: Went forward.")
            } else {
                Log.d(TAG, "::goRight: Couldn't go forward.")
            }
        }
    }

    /**
     * Android lifecycle resume method, reattaches the navigator if needed.
     */
    override fun onResume() {
        try {
            Log.d(TAG, "::onResume - $instance - $attachingNavigatorFragment")

            if (pdfVm == null) {
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

            val model = pdfVm
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
     * Android lifecycle pause method, detaches the navigator to save resources.
     */
    override fun onPause() {
        try {
            Log.d(TAG, "::onPause - $instance")

            pdfVm?.locator = currentLocator?.value

            pdfNavigator?.let { fragment ->
                childFragmentManager.commitNow {
                    remove(fragment)
                }
            }

            pdfNavigator = null
            started.value = false

            attachingNavigatorFragment = false

            edgeTapInterceptView?.let { (view as? FrameLayout)?.removeView(it) }
            edgeTapInterceptView = null

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

        val model = pdfVm
        if (model == null) {
            Log.e(TAG, "::attachNavigator() - $instance - missing view model")
            return
        }

        if (ReadiumReader.currentPublication == null) {
            Log.e(TAG, "::attachNavigator() - $instance - missing publication")
            return
        }

        val navigatorFactory = model.navigatorFactory
        if (navigatorFactory == null) {
            Log.e(TAG, "::attachNavigator() - $instance - missing navigator factory")
            return
        }

        val fragmentFactory = navigatorFactory.createFragmentFactory(
            initialLocator = model.locator,
            listener = this,
        )

        val pdfNavigatorFragment = fragmentFactory.instantiate(
            requireActivity().classLoader,
            PdfNavigatorFragment::class.java.name
        ) as? PdfNavigatorFragment<*, *>
        if (pdfNavigatorFragment == null) {
            Log.e(TAG, "::attachNavigator() - $instance - factory returned a non-PDF fragment")
            return
        }

        Log.d(TAG, "::attachNavigator - $instance - add fragment")
        childFragmentManager.commitNow {
            add(
                R.id.fragment_reader_container,
                pdfNavigatorFragment,
                NAVIGATOR_FRAGMENT_TAG,
            )
        }

        navigator = pdfNavigatorFragment
        Log.d(TAG, "::attachNavigator() - $instance - got navigator = $navigator")

        started.value = true

        // Add edge tap overlay on top of the navigator (PDF is always paginated)
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
            // PDF is always paginated, so scroll mode is never on here — passing it
            // explicitly keeps both readers on one configuration path.
            configureOverlay(overlay, storedNavigationConfig, isScrollMode = false)
            rootView.addView(overlay)
            edgeTapInterceptView = overlay
        }

        // Notify that page is loaded after navigator is attached
        listener?.onPageLoaded()
    }

    companion object {
        private const val NAVIGATOR_FRAGMENT_TAG = "READIUM_PDF_READER_FRAGMENT"
    }
}
