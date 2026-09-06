package dev.mulev.flureadium.navigators

import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withContext
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNotSame
import kotlin.test.assertTrue

private const val NAVIGATOR_PATH = "dev/mulev/flureadium/navigators/AudiobookNavigator.kt"

/**
 * `AudiobookNavigator.initNavigator` must resolve missing track durations before it
 * hops to `mainScope`, and hand the result to Readium's `createNavigator`. Otherwise
 * Readium's own duration fallback runs on the Android main thread and parks it on one
 * socket read per un-timed track — the ANR this phase fixes.
 *
 * The first case is behavioural. The other two read the source, because `initNavigator`
 * builds its `ExoPlayerNavigatorFactory` inline and there is no seam to observe the
 * call from a JVM test; adding an injection point only a test would use is the
 * speculative parameter YAGNI forbids. This repo already guards conventions that way —
 * see `CoroutineScopeHandlerConventionTest`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class AudiobookNavigatorDurationResolutionTest {

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun probingRunsOffTheMainDispatcher() {
        val publication = mock(Publication::class.java)
        val link = Link(href = Href(Url("t1.mp3")!!), mediaType = MediaType.MP3)
        val probeThread = AtomicReference<Thread>()
        `when`(publication.get(link)).thenAnswer {
            probeThread.set(Thread.currentThread())
            null
        }

        val callerThread = AtomicReference<Thread>()
        runBlocking(Dispatchers.Main) {
            callerThread.set(Thread.currentThread())
            withContext(Dispatchers.IO) { resolveTrackDurations(publication, listOf(link)) }
        }

        assertNotNull(probeThread.get(), "the probe never ran")
        assertNotSame(callerThread.get(), probeThread.get(), "the probe ran on the calling thread")
    }

    @Test
    fun initNavigatorResolvesDurationsBeforeTheMainThreadHop() {
        val body = initNavigatorBody()

        val ioHop = body.indexOfFirst { "withContext(Dispatchers.IO)" in it }
        val resolution = body.indexOfFirst { "resolveTrackDurations(" in it }
        val mainHop = body.indexOfFirst { "mainScope.async {" in it }

        assertTrue(ioHop >= 0, "initNavigator never switches to Dispatchers.IO")
        assertTrue(resolution >= 0, "initNavigator never calls resolveTrackDurations")
        assertTrue(mainHop >= 0, "initNavigator no longer hops to mainScope")
        assertTrue(ioHop < mainHop, "the IO hop must come before the main-thread hop")
        assertTrue(resolution < mainHop, "durations must be resolved before the main-thread hop")
    }

    @Test
    fun createNavigatorReceivesResolvedReadingOrder() {
        val body = initNavigatorBody()

        val call = body.indexOfFirst { "createNavigator(" in it }
        assertTrue(call >= 0, "initNavigator no longer calls createNavigator")
        val closerOffset = body.subList(call, body.size).indexOfFirst { ").getOrElse" in it }
        assertTrue(closerOffset > 0, "cannot find the end of the createNavigator call")

        assertTrue(
            body.subList(call, call + closerOffset).any { "resolvedReadingOrder" in it },
            "createNavigator is not given the resolved reading order",
        )
    }

    /** `initNavigator`'s source lines, from its signature to its closing brace. */
    private fun initNavigatorBody(): List<String> {
        val lines = File(mainSourceRoot(), NAVIGATOR_PATH).readLines()
        val start = lines.indexOfFirst { "override suspend fun initNavigator()" in it }
        assertTrue(start >= 0, "cannot find initNavigator in $NAVIGATOR_PATH")
        val closerOffset = lines.subList(start + 1, lines.size).indexOfFirst { it == "    }" }
        assertTrue(closerOffset >= 0, "cannot find the end of initNavigator")
        return lines.subList(start, start + closerOffset + 2)
    }

    /**
     * The same walk-up `CoroutineScopeHandlerConventionTest` uses. Duplicated on purpose:
     * a shared test-helper file for two unrelated convention tests would be the
     * catch-all-helpers anti-pattern, and widening that test's private is worse.
     */
    private fun mainSourceRoot(): File {
        val start = File("").absoluteFile
        return generateSequence(start) { it.parentFile }
            .map { File(it, "src/main/kotlin") }
            .firstOrNull { it.isDirectory }
            ?: error("cannot locate src/main/kotlin from $start")
    }
}
