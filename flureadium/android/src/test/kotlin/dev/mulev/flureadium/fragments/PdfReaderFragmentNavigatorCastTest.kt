package dev.mulev.flureadium.fragments

import kotlin.test.Test
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.verifyNoInteractions
import org.readium.r2.navigator.Navigator
import org.readium.r2.navigator.pdf.PdfNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Pins the behaviour of PdfReaderFragment's private `pdfNavigator` accessor.
 *
 * The accessor casts the inherited `navigator` field to a PDF navigator fragment.
 * Generics are erased, so the cast checks the raw class only — star-projecting the
 * type arguments must leave both outcomes exactly as they are.
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class PdfReaderFragmentNavigatorCastTest {

    @Test
    fun pdfNavigator_returnsNull_whenNavigatorIsNotAPdfFragment() {
        val fragment = PdfReaderFragment()
        fragment.setNavigatorForTest(mock(Navigator::class.java))

        assertNull(fragment.readPdfNavigator(), "a non-PDF navigator must not be cast")
    }

    @Test
    fun pdfNavigator_returnsTheFragment_whenNavigatorIsAPdfFragment() {
        val fragment = PdfReaderFragment()
        val pdfFragment = mock(PdfNavigatorFragment::class.java)
        fragment.setNavigatorForTest(pdfFragment)

        assertSame(pdfFragment, fragment.readPdfNavigator())
    }

    @Test
    fun goLeft_isANoOp_whenNavigatorIsNotAPdfFragment() {
        val fragment = PdfReaderFragment()
        val navigator = mock(Navigator::class.java)
        fragment.setNavigatorForTest(navigator)

        fragment.goLeft(animated = true)

        verifyNoInteractions(navigator)
    }

    private fun PdfReaderFragment.setNavigatorForTest(value: Navigator?) {
        val field = BaseReaderFragment::class.java.getDeclaredField("navigator")
        field.isAccessible = true
        field.set(this, value)
    }

    private fun PdfReaderFragment.readPdfNavigator(): Any? {
        val getter = PdfReaderFragment::class.java.getDeclaredMethod("getPdfNavigator")
        getter.isAccessible = true
        return getter.invoke(this)
    }
}
