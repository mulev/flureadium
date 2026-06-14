package dev.mulev.flureadium

import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertFailsWith
import org.junit.runner.RunWith
import org.mockito.Mockito
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.readium.r2.shared.util.Try
import org.robolectric.RobolectricTestRunner

/**
 * Guards the method-channel dispatcher against reporting coroutine cancellation
 * as a Flutter error.
 *
 * Regression: when a publication is torn down ([ReadiumReader.stop] /
 * closePublication) while a suspending call such as `play` is still in flight,
 * the in-flight [kotlinx.coroutines.Deferred] is cancelled. `JobCancellationException`
 * is a subclass of [Exception], so the dispatcher's generic `catch (e: Exception)`
 * swallowed it and pushed it back to Dart as `result.error(...)`, surfacing as a
 * `PlatformException(JobCancellationException ...)` "after the test had completed"
 * and intermittently failing the EPUB TTS integration tests.
 */
@RunWith(RobolectricTestRunner::class)
internal class PublicationChannelCancellationTest {

    @Test
    fun dispatchGuarded_cancellation_propagatesAndIsNotReported() = runTest {
        val result = Mockito.mock(MethodChannel.Result::class.java)

        // A cancellation must propagate (so the coroutine unwinds normally),
        // not be reported back to Dart.
        assertFailsWith<CancellationException> {
            result.dispatchGuarded("play") {
                throw CancellationException("torn down")
            }
        }

        verify(result, never()).error(Mockito.any(), Mockito.any(), Mockito.any())
        verify(result, never()).success(Mockito.any())
    }

    @Test
    fun dispatchGuarded_realException_isReportedAsError() = runTest {
        val result = Mockito.mock(MethodChannel.Result::class.java)

        result.dispatchGuarded("play") {
            throw RuntimeException("boom")
        }

        verify(result).error(
            Mockito.eq(RuntimeException::class.java.toString()),
            Mockito.contains("boom"),
            Mockito.any()
        )
    }

    @Test
    fun dispatchGuarded_unitResult_repliesSuccessNull() = runTest {
        val result = Mockito.mock(MethodChannel.Result::class.java)

        result.dispatchGuarded("play") { Try.success(Unit) }

        verify(result).success(null)
    }
}
