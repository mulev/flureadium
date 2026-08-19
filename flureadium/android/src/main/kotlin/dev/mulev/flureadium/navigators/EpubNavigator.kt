package dev.mulev.flureadium.navigators

import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commitNow
import dev.mulev.flureadium.FlutterNavigationConfig
import dev.mulev.flureadium.ReadiumReaderWidget.Companion.NAVIGATOR_FRAGMENT_TAG
import dev.mulev.flureadium.canScroll
import dev.mulev.flureadium.fragments.EpubReaderFragment
import dev.mulev.flureadium.models.EpubReaderViewModel
import dev.mulev.flureadium.throttleLatest
import dev.mulev.flureadium.withScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubPreferencesEditor
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "EpubNavigator"
private const val currentVisualCurrentLocatorKey = "currentVisualCurrentLocator"
private const val epubPreferencesKey = "epubPreferences"

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

        this.state[currentVisualCurrentLocatorKey] = initialLocator
        this.state[epubPreferencesKey] = initialPreferences
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
     * Pending scroll target to be applied when the page is loaded.
     */
    var pendingScrollToLocations: Locator.Locations? = null

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

    override suspend fun initNavigator() {
        pendingScrollToLocations =
            initialLocator?.locations?.let { locations ->
                if (canScroll(locations)) locations else null
            }

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
                state[epubPreferencesKey] = preferences
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

        val currentLocator = navigator.currentLocator
        if (currentLocator != null) {
            currentLocator.throttleLatest(100.milliseconds)
                .distinctUntilChanged()
                .onEach { locator ->
                    Log.d(TAG, "::locator - href=${locator.href} prog=${locator.locations.progression}")
                    onCurrentLocatorChanges(locator)
                    state[currentVisualCurrentLocatorKey] = locator
                }
                .launchIn(mainScope)
                .let { jobs.add(it) }

            subscribedFragmentInstance = navigator
        } else {
            Log.d(TAG, "::setupNavigatorListeners - currentLocator is null - navigator not ready?")
        }
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentVisualCurrentLocatorKey,
                (state[currentVisualCurrentLocatorKey] as? Locator)?.toJSON()?.toString()
            )

            preferences?.let { prefs ->
                putString(
                    epubPreferencesKey,
                    Json.encodeToString(EpubPreferences.serializer(), prefs)
                )
            }
        }
    }

    override fun onPageLoaded() {
        val currentFragment = epubNavigator
        Log.d(
            TAG,
            "::onPageLoaded - href=${currentFragment?.currentLocator?.value?.href} " +
                "pendingScroll=${pendingScrollToLocations != null}",
        )

        // The fragment drops its Readium navigator on pause and builds a new one
        // on resume, and hasNotifiedIsReady stops setupNavigatorListeners from
        // running again — so the tap registration follows the page load instead.
        tapForwarder.bindTo(currentFragment?.visualNavigator)

        visualListener.onPageLoaded()

        pendingScrollToLocations?.let { locations ->
            mainScope.async {
                // Keep follow-up scrolling consistent with explicit goToLocator behavior.
                pageScript.scrollTo(locations, toStart = false)
            }
            pendingScrollToLocations = null
        }

        // If fragment recreated (pause/resume), re-subscribe
        if (currentFragment != null && currentFragment !== subscribedFragmentInstance) {
            Log.d(TAG, "::onPageLoaded - fragment recreated, resubscribing")
            hasNotifiedIsReady = false
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
        mainScope.async {
            val locations = locator.locations
            val shouldScroll = canScroll(locations)
            val locatorHref = locator.href
            val currentHref = currentLocator?.value?.href
            val shouldGo = currentHref?.isEquivalent(locatorHref) == false

            // TODO: Figure out why we can't just use rely on Readium's own go-function to scroll
            // the locator.
            if (shouldGo) {
                Log.d(TAG, "::goToLocator - go $currentHref -> $locatorHref")
                pendingScrollToLocations = locations
                go(locator, animated)
            } else if (!shouldScroll) {
                Log.d(TAG, "::goToLocator - stay at $locatorHref, no scroll data")
            } else {
                // Check if we're already at the correct progression to avoid unnecessary scroll
                // that would recalculate position from bounding rect and introduce drift.
                // This matches iOS behavior which doesn't re-scroll during restore.
                val currentProgression = currentLocator?.value?.locations?.progression
                val targetProgression = locations.progression

                if (currentProgression != null && targetProgression != null) {
                    val progressionDelta = kotlin.math.abs(currentProgression - targetProgression)
                    if (progressionDelta < 0.01) {  // Within 1% - already positioned correctly
                        Log.d(TAG, "::goToLocator - stay at $locatorHref, delta=$progressionDelta")
                        return@async
                    }
                }

                Log.d(TAG, "::goToLocator - scroll $currentProgression -> $targetProgression")

                pageScript.scrollTo(locations, toStart = false)
            }
        }.await()
    }

    /**
     * Clears any deferred scroll that was queued before an explicit external restore/navigation call.
     */
    fun clearPendingScrollTarget() {
        if (pendingScrollToLocations != null) {
            Log.d(TAG, "::clearPendingScrollTarget")
        }
        pendingScrollToLocations = null
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: VisualListener,
            state: Bundle
        ): EpubNavigator {
            val locator = state.getString(currentVisualCurrentLocatorKey)
                ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences = state.getString(epubPreferencesKey)
                ?.let { string -> Json.decodeFromString<EpubPreferences>(string) }
                ?: EpubPreferences()

            Log.d(TAG, "::restoreState - locator: $locator, preferences: $preferences")

            return EpubNavigator(publication, locator, listener, preferences)
        }
    }
}
