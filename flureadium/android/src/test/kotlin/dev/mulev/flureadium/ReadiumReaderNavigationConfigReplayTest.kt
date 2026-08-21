package dev.mulev.flureadium

import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import dev.mulev.flureadium.navigators.EpubNavigator
import dev.mulev.flureadium.navigators.ImageNavigator
import dev.mulev.flureadium.navigators.PdfNavigator
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.any
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockConstruction
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test

/**
 * Pins what happens to a navigation config that arrives before a navigator
 * exists: it is kept and handed to the navigator the next enable builds, once.
 *
 * The three *SetNavigationConfig entry points are `navigator?.set…`, so before
 * an enable has built its navigator they used to be silent no-ops and the
 * config was lost with no error anywhere. Counting the deliveries is the whole
 * point of these cases: the overlay applies a config idempotently, so a double
 * delivery is invisible downstream and observable only here.
 *
 * The scope swap and its reasoning come from ReadiumReaderDetachOrderingTest:
 * ReadiumReader resolves its mainScope once and outlives every test class in
 * the run, so seeding the scope is what makes these cases say the same thing
 * whichever class ran first.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
internal class ReadiumReaderNavigationConfigReplayTest {

    private val dispatcher = UnconfinedTestDispatcher()
    private lateinit var originalScope: CoroutineScope

    private val configA = FlutterNavigationConfig(enableEdgeTapNavigation = false)
    private val configB = FlutterNavigationConfig(enableSwipeNavigation = false)

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        originalScope = getReaderField("mainScope") as CoroutineScope
        setReaderField("mainScope", CoroutineScope(SupervisorJob() + dispatcher))
        resetReaderState()
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        setReaderField("mainScope", originalScope)
        resetReaderState()
    }

    @Test
    fun configSentBeforeEnableReachesTheNavigatorItBuilds() = runTest {
        ReadiumReader.epubSetNavigationConfig(configA)

        val navigator = enableEpub()

        verify(navigator, times(1)).setNavigationConfig(configA)
    }

    @Test
    fun nothingStoredMeansNothingReplayed() = runTest {
        val navigator = enableEpub()

        verify(navigator, never()).setNavigationConfig(anyConfig())
    }

    @Test
    fun aLaterConfigWinsAndTheEarlierOneIsNotDeliveredTwice() = runTest {
        ReadiumReader.epubSetNavigationConfig(configA)
        val navigator = enableEpub()

        ReadiumReader.epubSetNavigationConfig(configB)

        verify(navigator, times(1)).setNavigationConfig(configA)
        verify(navigator, times(1)).setNavigationConfig(configB)
    }

    @Test
    fun pdfEnableReplaysTheStoredConfig() = runTest {
        ReadiumReader.pdfSetNavigationConfig(configA)
        setReaderField("_currentPublication", publicationConformingTo(Publication.Profile.PDF))

        mockConstruction(PdfNavigator::class.java).use { built ->
            ReadiumReader.pdfEnable(
                initialLocator = null,
                initialPreferences = FlutterPdfPreferences(),
                messenger = mock(BinaryMessenger::class.java),
                fragmentManager = mock(FragmentManager::class.java),
                viewGroup = mock(ViewGroup::class.java),
                readerWidget = mock(ReadiumReaderWidget::class.java),
            )

            verify(built.constructed().single(), times(1)).setNavigationConfig(configA)
        }
    }

    /**
     * ImageNavigator.setNavigationConfig is an empty body today, so this case
     * pins the delivery rather than an effect — which is what keeps the third
     * branch from rotting once the image reader grows an overlay.
     */
    @Test
    fun imageEnableReplaysTheStoredConfig() = runTest {
        ReadiumReader.imageSetNavigationConfig(configA)
        // readerKind() calls a DIVINA publication image-based, which is the
        // cheapest publication imageEnable's guard accepts.
        setReaderField("_currentPublication", publicationConformingTo(Publication.Profile.DIVINA))

        mockConstruction(ImageNavigator::class.java).use { built ->
            ReadiumReader.imageEnable(
                initialLocator = null,
                messenger = mock(BinaryMessenger::class.java),
                fragmentManager = mock(FragmentManager::class.java),
                viewGroup = mock(ViewGroup::class.java),
                readerWidget = mock(ReadiumReaderWidget::class.java),
            )

            verify(built.constructed().single(), times(1)).setNavigationConfig(configA)
        }
    }

    /**
     * Runs a real epubEnable with the navigator's constructor intercepted, so
     * the mock that lands in ReadiumReader.epubNavigator is the one a replay
     * has to reach.
     */
    private suspend fun enableEpub(): EpubNavigator {
        setReaderField("_currentPublication", publicationConformingTo(Publication.Profile.EPUB))
        mockConstruction(EpubNavigator::class.java).use { built ->
            ReadiumReader.epubEnable(
                initialLocator = null,
                initialPreferences = EpubPreferences(),
                messenger = mock(BinaryMessenger::class.java),
                fragmentManager = mock(FragmentManager::class.java),
                viewGroup = mock(ViewGroup::class.java),
                readerWidget = mock(ReadiumReaderWidget::class.java),
            )
            return built.constructed().single()
        }
    }

    /**
     * Mockito's any() returns null, which a Kotlin non-null parameter rejects
     * before the matcher is ever used; the elvis hands the call a real value
     * while the matcher stays registered.
     */
    private fun anyConfig(): FlutterNavigationConfig =
        any(FlutterNavigationConfig::class.java) ?: configA
}
