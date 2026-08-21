package dev.mulev.flureadium.navigators

import com.github.barteksc.pdfviewer.PDFView
import dev.mulev.flureadium.FlutterNavigationConfig
import dev.mulev.flureadium.FlutterPdfPreferences
import dev.mulev.flureadium.fragments.PdfReaderFragment
import dev.mulev.flureadium.models.PdfReaderViewModel
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockConstruction
import org.mockito.Mockito.verify
import org.readium.adapter.pdfium.navigator.PdfiumEngineProvider
import org.readium.r2.navigator.pdf.PdfNavigatorFactory
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Regression test for PdfNavigator.initNavigator() scope resolution.
 *
 * Bare `engineProvider!!` inside `PdfReaderViewModel.apply {}` resolved to
 * PdfReaderViewModel.engineProvider (null) instead of PdfNavigator.engineProvider.
 * The fix qualifies it as `this@PdfNavigator.engineProvider!!`.
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class PdfNavigatorInitTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createNavigator(): PdfNavigator {
        return PdfNavigator(
            mock(Publication::class.java),
            null,
            mock(PdfNavigator.VisualListener::class.java),
            FlutterPdfPreferences()
        )
    }

    private fun PdfNavigator.getField(name: String): Any? {
        val field = PdfNavigator::class.java.getDeclaredField(name)
        field.isAccessible = true
        return field.get(this)
    }

    /**
     * Without the fix, initNavigator() throws NPE because PdfReaderViewModel.engineProvider
     * is null at construction time. With the fix, the outer PdfNavigator.engineProvider is
     * used instead.
     */
    @Test
    fun initNavigator_resolves_engineProvider_from_outer_scope() = runTest {
        val navigator = createNavigator()

        mockConstruction(PdfiumEngineProvider::class.java).use {
            mockConstruction(PdfNavigatorFactory::class.java).use {
                navigator.initNavigator()
            }
        }

        val fragment = navigator.getField("pdfNavigator") as? PdfReaderFragment
        assertNotNull(fragment, "pdfNavigator fragment should be initialized")

        val vm = fragment.vm as PdfReaderViewModel
        assertNotNull(vm.navigatorFactory, "navigatorFactory must be set")
        assertNotNull(vm.engineProvider, "VM engineProvider must be set from outer PdfNavigator scope")
    }

    /**
     * Builds a navigator, delivers [config] if given — after initNavigator(),
     * the way Flutter does — then runs the listener the pdfium provider was
     * constructed with against a fresh Configurator and returns it.
     */
    private suspend fun configureNewPdfView(
        config: FlutterNavigationConfig? = null,
    ): PDFView.Configurator {
        val navigator = createNavigator()
        val captured = mutableListOf<PdfiumEngineProvider.Listener>()
        mockConstruction(PdfiumEngineProvider::class.java) { _, context ->
            captured += context.arguments().filterIsInstance<PdfiumEngineProvider.Listener>()
        }.use {
            mockConstruction(PdfNavigatorFactory::class.java).use {
                navigator.initNavigator()
            }
        }
        if (config != null) navigator.setNavigationConfig(config)

        val configurator = mock(PDFView.Configurator::class.java)
        captured.single().onConfigurePdfView(configurator)
        return configurator
    }

    /**
     * The listener re-reads the stored config every time the pdfium adapter builds
     * a PDFView, so a config that arrives after initNavigator() still applies.
     */
    @Test
    fun pdfViewConfigurator_disablesSwipe_whenFlagFalse() = runTest {
        val configurator = configureNewPdfView(
            FlutterNavigationConfig(enableSwipeNavigation = false)
        )

        verify(configurator).enableSwipe(false)
    }

    @Test
    fun pdfViewConfigurator_keepsSwipe_whenFlagTrue() = runTest {
        val configurator = configureNewPdfView(
            FlutterNavigationConfig(enableSwipeNavigation = true)
        )

        verify(configurator).enableSwipe(true)
    }

    @Test
    fun pdfViewConfigurator_keepsSwipe_whenNoConfigArrived() = runTest {
        val configurator = configureNewPdfView()

        verify(configurator).enableSwipe(true)
    }
}
