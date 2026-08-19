package dev.mulev.flureadium.navigators

import androidx.fragment.app.FragmentManager
import dev.mulev.flureadium.ReadiumReaderWidget
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.json.JSONObject
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import org.readium.r2.navigator.image.ImageNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.data.ReadError
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class ImageNavigatorTest {

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
    fun `storeState round trips locator through restoreState`() {
        val navigator = createNavigator()
        val locator = locator(href = "images/page-2.jpg", progression = 0.5)

        navigator.onJumpToLocator(locator)
        val restored = ImageNavigator.restoreState(mock(Publication::class.java), mockListener(), navigator.storeState())

        assertEquals(locator.toJSON().toString(), restored.getInitialLocatorForTest()?.toJSON()?.toString())
    }

    @Test
    fun `storeState is empty after dispose clears state`() {
        val navigator = createNavigator()
        navigator.onJumpToLocator(locator(href = "images/page-3.jpg", progression = 0.75))

        navigator.dispose()

        assertNull(navigator.storeState().getString("currentVisualCurrentLocator"))
    }

    @Test
    fun `go returns false when fragment is missing`() = runTest {
        val navigator = createNavigator()

        val success = navigator.go(locator(), animated = true)

        assertFalse(success)
    }

    @Test
    fun `goLeft and goRight forward to fragment`() {
        val navigator = createNavigator()
        val fragment = mock(ImageNavigatorFragment::class.java)
        navigator.setImageNavigatorForTest(fragment)

        navigator.goLeft(animated = true)
        navigator.goRight(animated = false)

        verify(fragment).goBackward(true)
        verify(fragment).goForward(false)
    }

    @Test
    fun `onCurrentLocatorChanges forwards locator to visual listener`() {
        val listener = mockListener()
        val navigator = createNavigator(listener)
        val locator = locator()

        navigator.onCurrentLocatorChanges(locator)

        verify(listener).onVisualCurrentLocationChanged(locator)
    }

    @Test
    fun `onResourceLoadFailed does not notify the visual listener`() {
        val listener = mockListener()
        val navigator = createNavigator(listener)

        navigator.onResourceLoadFailed(
            href = Url("images/page-1.jpg")!!,
            error = mock(ReadError::class.java),
        )

        verifyNoInteractions(listener)
    }

    @Test
    fun `notifyIsReady only emits once`() {
        val listener = mockListener()
        val navigator = createNavigator(listener)

        navigator.invokeNotifyIsReadyForTest()
        navigator.invokeNotifyIsReadyForTest()

        verify(listener).onPageLoaded()
        verify(listener).onVisualReaderIsReady()
    }

    @Test
    fun `attachNavigator is no-op when fragment is missing`() {
        val navigator = createNavigator()
        val fragmentManager = mock(FragmentManager::class.java)
        val container = mock(android.view.ViewGroup::class.java)

        navigator.attachNavigator(fragmentManager, container)

        verify(fragmentManager, never()).findFragmentByTag(ReadiumReaderWidget.NAVIGATOR_FRAGMENT_TAG)
    }

    private fun createNavigator(
        listener: ImageNavigator.VisualListener = mockListener(),
    ): ImageNavigator {
        return ImageNavigator(
            publication = mock(Publication::class.java),
            initialLocator = null,
            visualListener = listener,
        )
    }

    private fun mockListener(): ImageNavigator.VisualListener =
        mock(ImageNavigator.VisualListener::class.java)

    private fun locator(
        href: String = "images/page-1.jpg",
        progression: Double = 0.25,
    ): Locator =
        Locator.fromJSON(
            JSONObject(
                """
                {
                  "href": "$href",
                  "type": "image/jpeg",
                  "locations": {
                    "progression": $progression,
                    "position": 1
                  }
                }
                """.trimIndent()
            )
        )!!

    private fun ImageNavigator.getInitialLocatorForTest(): Locator? {
        val field = BaseNavigator::class.java.getDeclaredField("initialLocator")
        field.isAccessible = true
        return field.get(this) as Locator?
    }

    private fun ImageNavigator.setImageNavigatorForTest(fragment: ImageNavigatorFragment) {
        val field = ImageNavigator::class.java.getDeclaredField("imageNavigator")
        field.isAccessible = true
        field.set(this, fragment)
    }

    private fun ImageNavigator.invokeNotifyIsReadyForTest() {
        val method = ImageNavigator::class.java.getDeclaredMethod("notifyIsReady")
        method.isAccessible = true
        method.invoke(this)
    }
}
