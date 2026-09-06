package dev.mulev.flureadium.navigators

import android.media.MediaMetadataRetriever
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import org.mockito.Mockito.`when`
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.resource.FailureResource
import org.readium.r2.shared.util.resource.Resource
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowMediaMetadataRetriever
import org.robolectric.shadows.util.DataSource
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * Behaviour of [resolveTrackDurations] and the [ResourceMediaDataSource] bridge it
 * probes through. No test here builds a navigator, and none touches a network: the
 * resource is a hand-written fake and the retriever is Robolectric's shadow.
 *
 * The load-bearing assertion is that a failed probe leaves the duration `null` and
 * never `0.0` — Readium reads `0.0` as "missing" and refuses to open a publication
 * whose reading order declares it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class TrackDurationProbeTest {

    @AfterTest
    fun tearDown() {
        // The shadow's metadata and exception maps are static.
        ShadowMediaMetadataRetriever.reset()
    }

    @Test
    fun declaredDurationPassesThroughWithoutProbe() = runBlocking {
        val publication = mock(Publication::class.java)
        val link = trackLink("t1.mp3", duration = 300.0)

        val result = resolveTrackDurations(publication, listOf(link))

        assertSame(link, result[0])
        assertEquals(300.0, result[0].duration)
        verifyNoInteractions(publication)
    }

    @Test
    fun missingDurationIsProbedAndFilled() = runBlocking {
        stubDuration("90000")
        val publication = mock(Publication::class.java)
        val link = trackLink("t1.mp3")
        `when`(publication.get(link)).thenReturn(FakeResource())

        val result = resolveTrackDurations(publication, listOf(link))

        assertEquals(90.0, result[0].duration)
    }

    @Test
    fun zeroDeclaredDurationIsTreatedAsMissing() = runBlocking {
        stubDuration("90000")
        val publication = mock(Publication::class.java)
        val link = trackLink("t1.mp3", duration = 0.0)
        `when`(publication.get(link)).thenReturn(FakeResource())

        val result = resolveTrackDurations(publication, listOf(link))

        verify(publication).get(link)
        assertEquals(90.0, result[0].duration)
    }

    @Test
    fun failedProbeLeavesDurationNull() = runBlocking {
        stubDuration("90000")
        armProbeFailure()
        val publication = mock(Publication::class.java)
        val link = trackLink("t1.mp3")
        `when`(publication.get(link)).thenReturn(FakeResource())

        val result = resolveTrackDurations(publication, listOf(link))

        assertNull(result[0].duration)
        assertNotEquals(0.0, result[0].duration)
    }

    @Test
    fun unreadableDurationLeavesDurationNull() = runBlocking {
        val publication = mock(Publication::class.java)
        val link = trackLink("t1.mp3")
        `when`(publication.get(link)).thenReturn(FakeResource())

        val noMetadata = resolveTrackDurations(publication, listOf(link))
        assertNull(noMetadata[0].duration)

        stubDuration("0")
        val zeroMetadata = resolveTrackDurations(publication, listOf(link))
        assertNull(zeroMetadata[0].duration)
        assertNotEquals(0.0, zeroMetadata[0].duration)
    }

    @Test
    fun missingResourceLeavesDurationNull() = runBlocking {
        stubDuration("90000")
        val publication = mock(Publication::class.java)
        val link = trackLink("t1.mp3")
        `when`(publication.get(link)).thenReturn(null)

        val result = resolveTrackDurations(publication, listOf(link))

        assertNull(result[0].duration)
    }

    @Test
    fun inputOrderIsPreserved() = runBlocking {
        stubDuration("90000")
        val publication = mock(Publication::class.java)
        val links = (1..5).map { trackLink("t$it.mp3", duration = if (it % 2 == 1) 120.0 else null) }
        links.forEach { `when`(publication.get(it)).thenReturn(FakeResource()) }

        val result = resolveTrackDurations(publication, links)

        assertEquals(links.map { it.href.toString() }, result.map { it.href.toString() })
        assertEquals(listOf(120.0, 90.0, 120.0, 90.0, 120.0), result.map { it.duration })
    }

    @Test
    fun concurrencyIsBounded() = runBlocking(Dispatchers.IO) {
        stubDuration("90000")
        val publication = mock(Publication::class.java)
        val links = (1..10).map { trackLink("t$it.mp3") }
        val inFlight = AtomicInteger()
        val peak = AtomicInteger()
        val threeInFlight = CountDownLatch(3)
        val release = CountDownLatch(1)
        links.forEach { link ->
            `when`(publication.get(link)).thenAnswer {
                val live = inFlight.incrementAndGet()
                peak.updateAndGet { maxOf(it, live) }
                threeInFlight.countDown()
                release.await(5, TimeUnit.SECONDS)
                inFlight.decrementAndGet()
                FakeResource()
            }
        }

        val resolution = async { resolveTrackDurations(publication, links, concurrency = 3) }

        assertTrue(threeInFlight.await(5, TimeUnit.SECONDS), "three probes never overlapped")
        assertEquals(3, peak.get(), "a fourth probe got past the semaphore")
        release.countDown()

        assertEquals(10, resolution.await().size)
        assertEquals(3, peak.get(), "more than three probes overlapped while draining")
    }

    @Test
    fun resourceIsClosedForEveryProbe() = runBlocking {
        stubDuration("90000")
        val publication = mock(Publication::class.java)
        val links = (1..3).map { trackLink("t$it.mp3") }

        val onSuccess = stubResourcesFor(publication, links)
        resolveTrackDurations(publication, links)
        assertTrue(onSuccess.all { it.closed }, "a successful probe leaked its resource")

        armProbeFailure()
        val onFailure = stubResourcesFor(publication, links)
        val result = resolveTrackDurations(publication, links)

        assertTrue(onFailure.all { it.closed }, "a failed probe leaked its resource")
        assertTrue(result.all { it.duration == null })
    }

    @Test
    fun resourceMediaDataSourceBridgesReadsToTheResource() {
        val resource = FakeResource("abcdefgh".toByteArray())
        val source = ResourceMediaDataSource(resource)
        val buffer = ByteArray(8)

        assertEquals(8L, source.getSize())
        assertEquals(3, source.readAt(2, buffer, 0, 3))
        assertEquals("cde", String(buffer, 0, 3))
        assertEquals(0, source.readAt(0, buffer, 0, 0))
        assertEquals(1, resource.reads, "a zero-size read must not touch the resource")
        assertEquals(-1, source.readAt(8, buffer, 0, 3))

        source.close()
        assertFalse(resource.closed, "the bridge must not own the resource's lifetime")

        val failing = ResourceMediaDataSource(FailureResource(ReadError.Decoding("boom")))
        assertFailsWith<IOException> { failing.getSize() }
        assertFailsWith<IOException> { failing.readAt(0, buffer, 0, 3) }
    }

    private fun trackLink(name: String, duration: Double? = null) =
        Link(href = Href(Url(name)!!), mediaType = MediaType.MP3, duration = duration)

    private fun stubResourcesFor(publication: Publication, links: List<Link>): List<FakeResource> =
        links.map { link ->
            FakeResource().also { `when`(publication.get(link)).thenReturn(it) }
        }

    /**
     * Robolectric collapses every [android.media.MediaDataSource] to the constant key
     * `"MediaDataSource"` (`shadows/util/DataSource.java`), so one registration arms
     * every probe in a test.
     */
    private fun probeDataSource(): DataSource =
        DataSource.toDataSource(ResourceMediaDataSource(FakeResource()))

    private fun stubDuration(millis: String) =
        ShadowMediaMetadataRetriever.addMetadata(
            probeDataSource(),
            MediaMetadataRetriever.METADATA_KEY_DURATION,
            millis,
        )

    private fun armProbeFailure() =
        ShadowMediaMetadataRetriever.addException(
            probeDataSource(),
            IllegalStateException("setDataSource failed"),
        )

    /** A [Resource] over in-memory bytes that records its reads and its close. */
    private class FakeResource(private val bytes: ByteArray = ByteArray(0)) : Resource {
        var closed = false
            private set

        var reads = 0
            private set

        override val sourceUrl: AbsoluteUrl? = null

        override suspend fun properties(): Try<Resource.Properties, ReadError> =
            Try.success(Resource.Properties())

        override suspend fun length(): Try<Long, ReadError> = Try.success(bytes.size.toLong())

        override suspend fun read(range: LongRange?): Try<ByteArray, ReadError> {
            reads++
            if (range == null) return Try.success(bytes)
            val from = range.first.toInt().coerceIn(0, bytes.size)
            val until = (range.last.toInt() + 1).coerceIn(from, bytes.size)
            return Try.success(bytes.copyOfRange(from, until))
        }

        override fun close() {
            closed = true
        }
    }
}
