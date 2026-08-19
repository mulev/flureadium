package dev.mulev.flureadium.navigators

import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commitNow
import dev.mulev.flureadium.FlutterNavigationConfig
import dev.mulev.flureadium.ReadiumReaderWidget.Companion.NAVIGATOR_FRAGMENT_TAG
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.r2.navigator.image.ImageNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.data.ReadError

private const val TAG = "ImageNavigator"
private const val currentVisualCurrentLocatorKey = "currentVisualCurrentLocator"

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class ImageNavigator(
    publication: Publication,
    initialLocator: Locator?,
    private val visualListener: VisualListener,
) : BaseNavigator(publication, initialLocator), ImageNavigatorFragment.Listener {

    interface VisualListener {
        fun onPageLoaded()

        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)

        fun onExternalLinkActivated(url: AbsoluteUrl)

        /**
         * Called when the user tapped the content and Readium handled nothing
         * internally. Coordinates are logical pixels relative to the view.
         */
        fun onTap(x: Double, y: Double)

        fun onVisualCurrentLocationChanged(locator: Locator)

        fun onVisualReaderIsReady()
    }

    private var imageNavigator: ImageNavigatorFragment? = null

    /** Forwards content taps from the Readium navigator this class hosts. */
    private val tapForwarder = NavigatorTapForwarder { x, y -> visualListener.onTap(x, y) }

    /** Reports throttled locator changes, subscribed once the fragment is attached. */
    private val locatorSubscription = VisualLocatorSubscription()

    val currentLocator
        get() = imageNavigator?.currentLocator

    override suspend fun initNavigator() {
        val factory = ImageNavigatorFragment.Companion.createFactory(
            publication,
            initialLocator,
            this,
        )
        imageNavigator =
            factory.instantiate(
                ImageNavigatorFragment::class.java.classLoader!!,
                ImageNavigatorFragment::class.java.name,
            ) as ImageNavigatorFragment
    }

    fun attachNavigator(fragmentManager: FragmentManager, viewGroup: ViewGroup) {
        val navigator = imageNavigator ?: return
        mainScope.launch {
            fragmentManager.commitNow {
                add(viewGroup, navigator, NAVIGATOR_FRAGMENT_TAG)
            }
            notifyIsReady()
        }
    }

    suspend fun go(locator: Locator, animated: Boolean): Boolean {
        val navigator = imageNavigator
        if (navigator == null) {
            Log.d(TAG, "::go - imageNavigator is null!")
            return false
        }

        return withContext(Dispatchers.Main.immediate) {
            navigator.go(locator, animated)
        }
    }

    override fun setupNavigatorListeners() {
        // Above the locator guard on purpose: a CBZ opened before its first
        // locator arrives would otherwise never report a tap.
        tapForwarder.bindTo(imageNavigator)

        val job = locatorSubscription.subscribe(currentLocator, mainScope) { locator ->
            onCurrentLocatorChanges(locator)
            state[currentVisualCurrentLocatorKey] = locator
        }

        if (job == null) {
            Log.d(TAG, "::setupNavigatorListeners - currentLocator is null")
            return
        }

        jobs.add(job)
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentVisualCurrentLocatorKey,
                (state[currentVisualCurrentLocatorKey] as? Locator)?.toJSON()?.toString(),
            )
        }
    }

    private var hasNotifiedIsReady = false

    private fun notifyIsReady() {
        if (hasNotifiedIsReady) {
            return
        }

        hasNotifiedIsReady = true
        visualListener.onPageLoaded()
        visualListener.onVisualReaderIsReady()
        setupNavigatorListeners()
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        visualListener.onVisualCurrentLocationChanged(locator)
    }

    override fun onResourceLoadFailed(href: Url, error: ReadError) {
        Log.e(TAG, "::onResourceLoadFailed $href $error")
    }

    override fun onJumpToLocator(locator: Locator) {
        state[currentVisualCurrentLocatorKey] = locator
    }

    override suspend fun release() {
        tapForwarder.unbind()
        super.dispose()

        imageNavigator?.let { fragment ->
            withContext(Dispatchers.Main) {
                fragment.parentFragmentManager.commitNow { remove(fragment) }
            }
        }
        imageNavigator = null
        state.clear()
    }

    override fun dispose() {
        tapForwarder.unbind()
        super.dispose()

        mainScope.launch {
            imageNavigator?.let { fragment ->
                fragment.parentFragmentManager.commitNow { remove(fragment) }
            }

            mainScope.coroutineContext.cancelChildren()
            imageNavigator = null
        }

        state.clear()
    }

    fun goLeft(animated: Boolean) {
        val navigator = imageNavigator
        if (navigator == null) {
            Log.e(TAG, "::goLeft - imageNavigator is null!")
            return
        }

        Log.d(TAG, "::goLeft")
        navigator.goBackward(animated)
    }

    fun goRight(animated: Boolean) {
        val navigator = imageNavigator
        if (navigator == null) {
            Log.e(TAG, "::goRight - imageNavigator is null!")
            return
        }

        Log.d(TAG, "::goRight")
        navigator.goForward(animated)
    }

    fun setNavigationConfig(@Suppress("UNUSED_PARAMETER") config: FlutterNavigationConfig) {
        // No image-specific overlay settings are applied yet.
    }

    suspend fun goToLocator(locator: Locator, animated: Boolean) {
        mainScope.async {
            go(locator, animated)
        }.await()
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: VisualListener,
            state: Bundle,
        ): ImageNavigator {
            val locator =
                state.getString(currentVisualCurrentLocatorKey)
                    ?.let { json -> Locator.fromJSON(JSONObject(json)) }

            Log.d(TAG, "::restoreState - locator: $locator")

            return ImageNavigator(publication, locator, listener)
        }
    }
}
