package dev.mulev.flureadium.navigators

import dev.mulev.flureadium.fragments.EpubReaderFragment
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.json.JSONObject
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.readium.r2.navigator.VisualNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Pins the locator subscription EpubNavigator keeps on its reader fragment.
 *
 * The fragment drops its Readium navigator in onPause() and builds a new one in
 * onResume(), which leaves the old locator StateFlow behind. hasNotifiedIsReady
 * stops setupNavigatorListeners from running a second time, so onPageLoaded has
 * to notice the swapped fragment instance and resubscribe — otherwise the reader
 * comes back from a resume reporting no position at all, and the host's saved
 * progress freezes at wherever the book was when it was paused.
 *
 * Emissions are asserted through virtual time because the subscription throttles
 * at 100ms: the flow value is set, the scheduler advanced past the window, and
 * only then is the listener verified.
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class EpubNavigatorLocatorSubscriptionTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `forwards a throttled locator emission to the listener`() = runTest {
        val locators = MutableStateFlow(locator(progression = 0.10))
        val listener = mockListener()
        val navigator = navigatorOf(epubFragment(locators), listener)

        navigator.onPageLoaded()
        val moved = locator(progression = 0.40)
        locators.value = moved
        testDispatcher.scheduler.advanceTimeBy(150)

        verify(listener).onVisualCurrentLocationChanged(moved)
    }

    @Test
    fun `resubscribes to the locator flow of a fragment recreated on resume`() = runTest {
        val paused = MutableStateFlow(locator(progression = 0.10))
        val listener = mockListener()
        val navigator = navigatorOf(epubFragment(paused), listener)
        navigator.onPageLoaded()

        val resumed = MutableStateFlow(locator(progression = 0.50))
        navigator.setFragmentForTest("epubNavigator", epubFragment(resumed))
        navigator.onPageLoaded()

        val afterResume = locator(progression = 0.60)
        resumed.value = afterResume
        val onTheDeadFlow = locator(progression = 0.20)
        paused.value = onTheDeadFlow
        testDispatcher.scheduler.advanceTimeBy(150)

        verify(listener).onVisualCurrentLocationChanged(afterResume)
        verify(listener, never()).onVisualCurrentLocationChanged(onTheDeadFlow)
    }

    @Test
    fun `notifies readiness once across repeated page loads`() {
        val listener = mockListener()
        val navigator = navigatorOf(epubFragment(MutableStateFlow(locator())), listener)

        navigator.onPageLoaded()
        navigator.onPageLoaded()
        navigator.onPageLoaded()

        verify(listener, times(1)).onVisualReaderIsReady()
    }

    // MARK: - Harness

    private fun epubFragment(locators: MutableStateFlow<Locator>): EpubReaderFragment {
        val fragment = mock(EpubReaderFragment::class.java)
        `when`(fragment.currentLocator).thenReturn(locators)
        `when`(fragment.visualNavigator).thenReturn(mock(VisualNavigator::class.java))
        return fragment
    }

    private fun navigatorOf(
        fragment: EpubReaderFragment,
        listener: EpubNavigator.VisualListener,
    ): EpubNavigator {
        val navigator = EpubNavigator(
            publication = mock(Publication::class.java),
            initialLocator = null,
            visualListener = listener,
        )
        navigator.setFragmentForTest("epubNavigator", fragment)
        return navigator
    }

    private fun mockListener(): EpubNavigator.VisualListener =
        mock(EpubNavigator.VisualListener::class.java)

    private fun locator(
        href: String = "OEBPS/chapter01.xhtml",
        progression: Double = 0.25,
    ): Locator =
        Locator.fromJSON(
            JSONObject(
                """
                {
                  "href": "$href",
                  "type": "application/xhtml+xml",
                  "locations": { "progression": $progression }
                }
                """.trimIndent()
            )
        )!!

    /** Seeds the fragment a navigator only gets from a real attach. */
    private fun BaseNavigator.setFragmentForTest(name: String, fragment: Any?) {
        javaClass.getDeclaredField(name).apply { isAccessible = true }.set(this, fragment)
    }
}
