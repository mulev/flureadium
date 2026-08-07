package dev.mulev.flureadium

import dev.mulev.flureadium.navigators.BaseNavigator
import dev.mulev.flureadium.navigators.ImageNavigator
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/**
 * Checks that the two reader-owned scopes outside the widget carry a reporting
 * handler.
 *
 * Holding the element is only half the claim — an inert handler would satisfy
 * it while a failure still went unreported — so each case invokes the handler
 * it found and asserts the host app hears about the failure.
 */
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class ReadiumReaderScopeHandlerTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        resetReaderState()
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        resetReaderState()
    }

    @Test
    fun readerScopeReportsAnUncaughtFailure() {
        val statuses = subscribeToReaderStatus()
        val errors = subscribeToErrorEvents()

        handlerOf(getReaderField("mainScope") as CoroutineScope)
            .handleException(EmptyCoroutineContext, Exception("boom"))

        assertReported(statuses, errors)
    }

    @Test
    fun navigatorScopeReportsAnUncaughtFailure() {
        val statuses = subscribeToReaderStatus()
        val errors = subscribeToErrorEvents()
        val navigator = ImageNavigator(
            publication = mock(Publication::class.java),
            initialLocator = null,
            visualListener = mock(ImageNavigator.VisualListener::class.java),
        )

        handlerOf(navigator.mainScopeForTest())
            .handleException(EmptyCoroutineContext, Exception("boom"))

        assertReported(statuses, errors)
    }

    private fun assertReported(statuses: List<String>, errors: List<Map<String, Any?>>) {
        assertEquals(listOf("error"), statuses)
        val errorEvent = errors.single()
        assertEquals("boom", errorEvent["message"])
        assertEquals(readerFailureErrorCode, errorEvent["code"])
    }

    private fun handlerOf(scope: CoroutineScope): CoroutineExceptionHandler =
        assertNotNull(
            scope.coroutineContext[CoroutineExceptionHandler],
            "a scope with no handler hands its failures to Android's kill handler"
        )

    private fun BaseNavigator.mainScopeForTest(): CoroutineScope {
        val field = BaseNavigator::class.java.getDeclaredField("mainScope")
        field.isAccessible = true
        return field.get(this) as CoroutineScope
    }
}
