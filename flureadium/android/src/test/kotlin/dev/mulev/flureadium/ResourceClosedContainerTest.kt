package dev.mulev.flureadium

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.runner.RunWith
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.shared.util.file.FileSystemError
import org.readium.r2.shared.util.resource.Resource
import org.robolectric.RobolectricTestRunner

/**
 * Guards against the crash that killed the Android integration suite roughly one
 * run in fifteen between March and August 2026, tracked as `flureadium-pbc`.
 *
 * Closing a publication while readium's CBZ page fragment is still loading a page
 * closes the backing `ZipFile` underneath the in-flight read. The read reaches
 * `java.util.zip.ZipFile.ensureOpen`, which throws
 * `IllegalStateException("zip file closed")`. readium 3.1.2's
 * `FileZipContainer.Entry.read()` catches only `ZipException` and `IOException`, so
 * that one escapes its `Try<ByteArray, ReadError>` contract. It surfaces inside
 * `R2CbzPageFragment`, which reads from a parentless root coroutine
 * (`coroutineContext = Dispatchers.Main`, no `Job`), so there is no handler anywhere
 * in the chain and Android kills the process: `FATAL EXCEPTION: main`.
 *
 * The guard is deliberately narrow. Every other runtime failure belongs to our own
 * transformers or to a navigator and has to stay loud, or a real bug turns into a
 * silently blank page.
 */
@RunWith(RobolectricTestRunner::class)
internal class ResourceClosedContainerTest {

    /** The literal message `ZipFile.ensureOpen` throws with. */
    private fun zipClosed() = IllegalStateException("zip file closed")

    private class FakeResource(
        override val sourceUrl: AbsoluteUrl? = AbsoluteUrl("file:///tmp/comic.cbz"),
        val onRead: () -> Try<ByteArray, ReadError> = { Try.success(ByteArray(0)) },
        val onLength: () -> Try<Long, ReadError> = { Try.success(0L) },
        val onProperties: () -> Try<Resource.Properties, ReadError> = {
            Try.success(Resource.Properties())
        },
    ) : Resource {
        var closed = false

        override suspend fun read(range: LongRange?): Try<ByteArray, ReadError> = onRead()
        override suspend fun length(): Try<Long, ReadError> = onLength()
        override suspend fun properties(): Try<Resource.Properties, ReadError> = onProperties()
        override fun close() {
            closed = true
        }
    }

    @Test
    fun read_againstClosedContainer_isReportedAsReadError() = runTest {
        val guarded = FakeResource(onRead = { throw zipClosed() }).catchingClosedContainer()

        val error = assertIs<Try.Failure<ByteArray, ReadError>>(guarded.read()).value

        val access = assertIs<ReadError.Access>(error)
        assertIs<FileSystemError.IO>(access.cause)
    }

    @Test
    fun read_cancellation_stillPropagates() = runTest {
        // CancellationException extends IllegalStateException, so a careless guard
        // would swallow it and break structured concurrency.
        val guarded = FakeResource(
            onRead = { throw CancellationException("torn down") }
        ).catchingClosedContainer()

        assertFailsWith<CancellationException> { guarded.read() }
    }

    @Test
    fun read_unrelatedIllegalState_stillPropagates() = runTest {
        val guarded = FakeResource(
            onRead = { throw IllegalStateException("navigator not attached") }
        ).catchingClosedContainer()

        val thrown = assertFailsWith<IllegalStateException> { guarded.read() }
        assertEquals("navigator not attached", thrown.message)
    }

    @Test
    fun read_otherRuntimeFailure_stillPropagates() = runTest {
        val guarded = FakeResource(
            onRead = { throw NullPointerException("bug in a transformer") }
        ).catchingClosedContainer()

        assertFailsWith<NullPointerException> { guarded.read() }
    }

    @Test
    fun read_success_isUnchanged() = runTest {
        val bytes = byteArrayOf(1, 2, 3)
        val guarded = FakeResource(onRead = { Try.success(bytes) }).catchingClosedContainer()

        val read = assertIs<Try.Success<ByteArray, ReadError>>(guarded.read()).value
        assertContentEquals(bytes, read)
    }

    @Test
    fun read_existingReadError_isUnchanged() = runTest {
        val failure = ReadError.Decoding(org.readium.r2.shared.util.DebugError("broken"))
        val guarded = FakeResource(onRead = { Try.failure(failure) }).catchingClosedContainer()

        val error = assertIs<Try.Failure<ByteArray, ReadError>>(guarded.read()).value
        assertTrue(error === failure)
    }

    @Test
    fun length_againstClosedContainer_isReportedAsReadError() = runTest {
        val guarded = FakeResource(onLength = { throw zipClosed() }).catchingClosedContainer()

        val error = assertIs<Try.Failure<Long, ReadError>>(guarded.length()).value
        assertIs<ReadError.Access>(error)
    }

    @Test
    fun properties_againstClosedContainer_isReportedAsReadError() = runTest {
        val guarded = FakeResource(onProperties = { throw zipClosed() }).catchingClosedContainer()

        val error =
            assertIs<Try.Failure<Resource.Properties, ReadError>>(guarded.properties()).value
        assertIs<ReadError.Access>(error)
    }

    @Test
    fun close_andSourceUrl_areDelegated() = runTest {
        val underlying = FakeResource()
        val guarded = underlying.catchingClosedContainer()

        assertEquals(underlying.sourceUrl, guarded.sourceUrl)

        guarded.close()
        assertTrue(underlying.closed)
    }

    @Test
    fun composedAsAtTheCallSite_containsTheThrow() = runTest {
        // Mirrors ReadiumReader.assetToPublication exactly. TransformingResource sits
        // between the guard and the container and calls through on both read() and
        // properties(), so the composition is what has to hold, not the guard alone.
        val guarded = FakeResource(onRead = { throw zipClosed() })
            .injectScriptsAndStyles()
            .catchingClosedContainer()

        val error = assertIs<Try.Failure<ByteArray, ReadError>>(guarded.read()).value
        assertIs<ReadError.Access>(error)
    }

    @Test
    fun composedAsAtTheCallSite_propertiesThrow_isContained() = runTest {
        // injectScriptsAndStyles reads properties() to find the filename, so a
        // container closing mid-transform surfaces there first.
        val guarded = FakeResource(onProperties = { throw zipClosed() })
            .injectScriptsAndStyles()
            .catchingClosedContainer()

        assertIs<Try.Failure<ByteArray, ReadError>>(guarded.read())
    }

    @Test
    fun sourceUrl_null_isDelegated() = runTest {
        assertNull(FakeResource(sourceUrl = null).catchingClosedContainer().sourceUrl)
    }
}
