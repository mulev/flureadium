package dev.mulev.flureadium.navigators

import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commitNow
import dev.mulev.flureadium.FlutterNavigationConfig
import dev.mulev.flureadium.ReadiumReaderWidget.Companion.NAVIGATOR_FRAGMENT_TAG
import dev.mulev.flureadium.fragments.EpubReaderFragment
import dev.mulev.flureadium.models.EpubReaderViewModel
import dev.mulev.flureadium.withScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubPreferencesEditor
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl

private const val TAG = "EpubNavigator"

/**
 * EpubNavigator is a wrapper around the EpubReaderFragment and provides methods to interact with it.
 * It also listens to events from the fragment and forwards them to the VisualListener.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class EpubNavigator : BaseNavigator, EpubReaderFragment.Listener {
    private val initialPreferences: EpubPreferences

    constructor(
        publication: Publication,
        initialLocator: Locator?,
        visualListener: VisualListener,
        initialPreferences: EpubPreferences = EpubPreferences()
    ) : super(publication, initialLocator) {
        this.initialPreferences = initialPreferences
        this.visualListener = visualListener

        this.state[EpubNavigatorState.LOCATOR_KEY] = initialLocator
        this.state[EpubNavigatorState.PREFERENCES_KEY] = initialPreferences
    }

    /**
     * A VisualListener is used to listen to events from the Visual navigators like EpubNavigator.
     */
    interface VisualListener {
        /**
         * Called when a page has loaded. Note: not necessarily the visible content, since
         * the Readium Navigator preloads neighboring charters.
         */
        fun onPageLoaded()

        /**
         * Called when the current page has changed. Can be a new file or a new page in the
         * same file.
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
     * EpubReaderFragment instance used as navigator.
     */
    private var epubNavigator: EpubReaderFragment? = null

    /**
     * Tracks which fragment instance we've subscribed to, to detect fragment recreation.
     */
    private var subscribedFragmentInstance: EpubReaderFragment? = null

    /**
     * Forwards content taps from whichever Readium navigator the fragment holds.
     */
    private val tapForwarder = NavigatorTapForwarder { x, y -> visualListener.onTap(x, y) }

    /**
     * Editor to modify EPUB preferences.
     */
    private var editor: EpubPreferencesEditor? = null

    /**
     * Current EPUB preferences.
     */
    val preferences: EpubPreferences?
        get() = editor?.preferences

    /**
     * Current locator in the EPUB navigator.
     */
    val currentLocator
        get() = epubNavigator?.currentLocator

    /**
     * Checks when the fragment starts and is safe to use.
     */
    private val navigatorStarted
        get() = epubNavigator!!.started

    /**
     * The Kotlin side of the `window.epubPage` JavaScript contract.
     */
    private val pageScript = EpubPageScript(
        evaluate = { script -> evaluateJavascript(script) },
        verticalScroll = { editor?.preferences?.scroll ?: false },
    )

    /**
     * Holds a restore scroll until a page load can perform it.
     */
    private val scrollRestore = EpubScrollRestore(
        page = pageScript,
        currentLocator = { epubNavigator?.currentLocator?.value },
        go = { locator, animated -> go(locator, animated) },
    )

    /**
     * Reports throttled locator changes. [onPageLoaded] cancels it when the
     * fragment swaps in a new Readium navigator, so [setupNavigatorListeners]
     * can subscribe to the replacement.
     */
    private val locatorSubscription = VisualLocatorSubscription()

    override suspend fun initNavigator() {
        scrollRestore.arm(initialLocator)

        epubNavigator = EpubReaderFragment().apply {
            vm = EpubReaderViewModel().apply {
                navigatorFactory = EpubNavigatorFactory(publication)
                locator = this@EpubNavigator.initialLocator
                preferences = this@EpubNavigator.initialPreferences

                editor =
                    navigatorFactory!!.createPreferencesEditor(initialPreferences)
            }
            listener = this@EpubNavigator
        }
    }

    /**
     * Attach the EPUB navigator fragment to the given FragmentManager and ViewGroup.
     */
    fun attachNavigator(fragmentManager: FragmentManager, viewGroup: ViewGroup) {
        val navigator = epubNavigator ?: return
        mainScope.launch {
            fragmentManager.commitNow {
                add(viewGroup, navigator, NAVIGATOR_FRAGMENT_TAG)
            }
        }
    }

    /**
     * Go to a specific locator in the EPUB navigator, this does not scroll to the locator position.
     */
    suspend fun go(locator: Locator, animated: Boolean): Boolean {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::go - epubNavigator is null!")
            return false
        }

        return withScope(mainScope) {
            afterFragmentStarted()
            if (!navigator.go(locator, animated)) {
                Log.w(TAG, "::go -  FAILED!")
                return@withScope false
            }

            return@withScope true
        }
    }

    /**
     * Update EPUB navigator preferences.
     */
    fun updatePreferences(preferences: EpubPreferences) {
        Log.d(TAG, "::updatePreferences - $preferences")

        try {
            editor?.apply {
                fontFamily.set(preferences.fontFamily)
                fontSize.set(preferences.fontSize)
                fontWeight.set(preferences.fontWeight)
                scroll.set(preferences.scroll)
                backgroundColor.set(preferences.backgroundColor)
                textColor.set(preferences.textColor)

                mainScope.launch {
                    epubNavigator?.updatePreferences(preferences)
                }
                state[EpubNavigatorState.PREFERENCES_KEY] = preferences
            }
        } catch (ex: Exception) {
            Log.e(TAG, "Error applying EpubPreferences: $ex")
        }
    }

    override fun setupNavigatorListeners() {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::setupNavigatorListeners - epubNavigator is null this should never happen")
            return
        }

        val job = locatorSubscription.subscribe(navigator.currentLocator, mainScope) { locator ->
            Log.d(TAG, "::locator - href=${locator.href} prog=${locator.locations.progression}")
            onCurrentLocatorChanges(locator)
            state[EpubNavigatorState.LOCATOR_KEY] = locator
        }

        if (job == null) {
            Log.d(TAG, "::setupNavigatorListeners - currentLocator is null - navigator not ready?")
            return
        }

        jobs.add(job)
        subscribedFragmentInstance = navigator
    }

    override fun storeState(): Bundle =
        EpubNavigatorState.toBundle(state[EpubNavigatorState.LOCATOR_KEY] as? Locator, preferences)

    override fun onPageLoaded() {
        val currentFragment = epubNavigator
        Log.d(TAG, "::onPageLoaded - href=${currentFragment?.currentLocator?.value?.href}")

        // The fragment drops its Readium navigator on pause and builds a new one
        // on resume, and hasNotifiedIsReady stops setupNavigatorListeners from
        // running again — so the tap registration follows the page load instead.
        tapForwarder.bindTo(currentFragment?.visualNavigator)

        visualListener.onPageLoaded()

        mainScope.async { scrollRestore.flush() }

        // If fragment recreated (pause/resume), re-subscribe
        if (currentFragment != null && currentFragment !== subscribedFragmentInstance) {
            Log.d(TAG, "::onPageLoaded - fragment recreated, resubscribing")
            hasNotifiedIsReady = false
            locatorSubscription.cancel()
            jobs.forEach { it.cancel() }
            jobs.clear()
        }

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
        state[EpubNavigatorState.LOCATOR_KEY] = locator
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

        epubNavigator?.let { fragment ->
            withContext(Dispatchers.Main) {
                fragment.parentFragmentManager.commitNow { remove(fragment) }
            }
        }
        epubNavigator = null
        state.clear()
    }

    override fun dispose() {
        tapForwarder.unbind()
        super.dispose()

        mainScope.launch {
            epubNavigator?.let { fragment ->
                fragment.parentFragmentManager.commitNow { remove(fragment) }
            }

            mainScope.coroutineContext.cancelChildren()
            epubNavigator = null
        }

        state.clear()
    }

    suspend fun evaluateJavascript(script: String): String? {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::evaluateJavascript - epubNavigator is null!")
            return null
        }

        afterFragmentStarted()
        return withScope(mainScope) {
            navigator.evaluateJavascript(script)
        }
    }

    fun setNavigationConfig(config: FlutterNavigationConfig) {
        epubNavigator?.setNavigationConfig(config)
    }

    fun setScrollMode(isScrollMode: Boolean) {
        epubNavigator?.setScrollMode(isScrollMode)
    }

    fun goLeft(animated: Boolean) {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::goLeft - epubNavigator is null!")
            return
        }

        Log.d(TAG, "::goLeft")
        navigator.goLeft(animated)
    }

    fun goRight(animated: Boolean) {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::goRight - epubNavigator is null!")
            return
        }

        Log.d(TAG, "::goRight")
        navigator.goRight(animated)
    }

    private suspend fun afterFragmentStarted() {
        if (navigatorStarted.value) return

        navigatorStarted.first { it }
    }

    suspend fun isReaderReady(): Boolean {
        return withScope(mainScope) {
            epubNavigator?.isReaderReady() ?: false
        }
    }

    suspend fun getLocatorFragments(locator: Locator): Locator? =
        pageScript.locatorFragments(locator)

    suspend fun firstVisibleElementLocator(): Locator? {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::firstVisibleElementLocator - epubNavigator is null!")
            return null
        }

        return withScope(mainScope) {
            navigator.firstVisibleElementLocator()
        }
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String
    ) {
        mainScope.async {
            epubNavigator?.applyDecorations(decorations, group)
        }.await()
    }

    /**
     * Go to a specific locator in the EPUB navigator, this scrolls to the locator position if needed.
     */
    suspend fun goToLocator(locator: Locator, animated: Boolean) {
        mainScope.async { scrollRestore.goTo(locator, animated) }.await()
    }

    /**
     * Clears any deferred scroll that was queued before an explicit external restore/navigation call.
     */
    fun clearPendingScrollTarget() {
        scrollRestore.clear()
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: VisualListener,
            state: Bundle
        ): EpubNavigator {
            val restored = EpubNavigatorState.fromBundle(state)

            return EpubNavigator(publication, restored.locator, listener, restored.preferences)
        }
    }
}
