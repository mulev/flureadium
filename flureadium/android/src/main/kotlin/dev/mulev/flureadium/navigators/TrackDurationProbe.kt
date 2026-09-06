package dev.mulev.flureadium.navigators

import android.media.MediaDataSource
import android.media.MediaMetadataRetriever
import android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
import android.util.Log
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.resource.Resource
import java.io.IOException

private const val TAG = "TrackDurationProbe"

/**
 * Returns [links] with every missing duration probed from the track itself.
 *
 * Readium's own fallback (AudioNavigatorFactory.createNavigator -> MetadataRetriever)
 * does this from whatever thread calls it, and it blocks: MediaMetadataRetriever's
 * MediaDataSource callbacks are synchronous, so a streamed track parks the caller on
 * a socket read. This runs the same work up front, off the main thread, so the
 * factory's fallback never fires.
 *
 * MUST be called from a blocking-tolerant dispatcher — [kotlinx.coroutines.Dispatchers.IO].
 * A link that already declares a positive duration is returned untouched, with no
 * probe and no network request. A probe that fails leaves the duration `null`,
 * never `0.0`: Readium reads `0.0` as "missing" (`takeUnless { it == Duration.ZERO }`)
 * and would fall straight back into the blocking path, and
 * `AudioNavigatorFactory.invoke` rejects a publication outright when any
 * reading-order duration is `0.0`.
 *
 * @param concurrency how many tracks are probed at once, so an N-track book costs
 *   about N/[concurrency] round-trips instead of N.
 */
internal suspend fun resolveTrackDurations(
    publication: Publication,
    links: List<Link>,
    concurrency: Int = 4,
): List<Link> = coroutineScope {
    val gate = Semaphore(concurrency)

    links
        .map { link ->
            async {
                val declared = link.duration
                if (declared != null && declared > 0.0) {
                    link
                } else {
                    gate.withPermit { link.copy(duration = probeDuration(publication, link)) }
                }
            }
        }
        .awaitAll()
}

/** The track's duration in seconds, or `null` when it cannot be read. Never `0.0`. */
private fun probeDuration(publication: Publication, link: Link): Double? {
    val resource = publication.get(link) ?: return null
    val retriever = MediaMetadataRetriever()

    return try {
        retriever.setDataSource(ResourceMediaDataSource(resource))
        retriever.extractMetadata(METADATA_KEY_DURATION)
            ?.toIntOrNull()
            ?.takeIf { it > 0 }
            ?.let { it / 1000.0 }
    } catch (e: Exception) {
        Log.w(TAG, ":probeDuration - ${link.href} unavailable: ${e.message}")
        null
    } finally {
        // release(), not close(): close() is API 29 and this module's minSdk is 24.
        retriever.release()
        resource.close()
    }
}

/**
 * Bridges a Readium [Resource] to the synchronous [MediaDataSource] the platform
 * retriever demands. `runBlocking` here is deliberate: the whole probe runs on
 * Dispatchers.IO, where blocking a thread is what the thread is for.
 */
internal class ResourceMediaDataSource(
    private val resource: Resource,
) : MediaDataSource() {

    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (size == 0) return 0

        val data = runBlocking {
            resource.read(position until position + size)
                .getOrElse { throw IOException("Resource read failed: $it") }
        }

        if (data.isEmpty()) return -1

        data.copyInto(buffer, offset)
        return data.size
    }

    override fun getSize(): Long =
        runBlocking {
            resource.length()
                .getOrElse { throw IOException("Resource length failed: $it") }
        }

    /** No-op: [probeDuration]'s `finally` owns the resource's lifetime, so it closes exactly once. */
    override fun close() = Unit
}
