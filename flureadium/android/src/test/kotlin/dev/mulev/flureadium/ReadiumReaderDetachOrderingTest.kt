package dev.mulev.flureadium

import android.os.Build
import dev.mulev.flureadium.navigators.EpubNavigator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Pins the order of the two halves of detach(): cancel this session's
 * coroutines first, tear the engine down afterwards.
 *
 * detach() publishes the publication close with mainScope.launch. With a cancel
 * below that launch, the close is a child the cancel reaches, so on any
 * dispatcher that has to dispatch it dies before it can null the publication.
 * Cancelling first avoids that: cancelChildren() cancels the current children
 * and leaves the scope's SupervisorJob active, so a launch issued afterwards
 * still runs.
 *
 * The case only means something on a dispatcher that has to dispatch. On
 * Dispatchers.Main.immediate the launched body runs inline, before any cancel
 * below it is reached — and it stays inline only because detach() nulls the
 * epub, image and pdf navigators first, leaving no release() that suspends on a
 * plain withContext(Dispatchers.Main). That is why the inversion never showed
 * up in production, and UnconfinedTestDispatcher hides it the same way.
 *
 * Hence the scope swap rather than Dispatchers.setMain: mainScope resolves
 * Dispatchers.Main.immediate once, when the singleton initialises, and
 * ReadiumReader outlives every test class in this JVM. Whichever class touches
 * it first decides that dispatcher for the whole run, so setMain alone would be
 * a coin flip on test ordering — it left this case passing against the broken
 * ordering. Seeding the scope makes the case say the same thing whenever it
 * runs, and teardown puts the original scope back on the shared singleton.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
internal class ReadiumReaderDetachOrderingTest {

    private val dispatcher = StandardTestDispatcher()
    private lateinit var originalScope: CoroutineScope

    /**
     * setMain comes before the read on purpose. The read is what initialises
     * ReadiumReader if nothing else has, and whatever Dispatchers.Main resolves
     * to at that moment is what the singleton's own scope keeps for the rest of
     * the run. Reading first would pin it to the real main dispatcher and make
     * this class the one that breaks setMain for everyone after it. What this
     * case asserts does not depend on the order either way: the scope it swaps
     * in is the same either way, and teardown restores whichever scope it found.
     */
    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        originalScope = getReaderField("mainScope") as CoroutineScope
        setReaderField("mainScope", CoroutineScope(SupervisorJob() + dispatcher))
        resetReaderState()
    }

    @AfterTest
    fun tearDown() {
        // resetMain() first: originalScope is lateinit, so if setUp() died
        // between setMain and the read, restoring it throws and would leave the
        // test dispatcher installed as Main for every class after this one.
        Dispatchers.resetMain()
        setReaderField("mainScope", originalScope)
        resetReaderState()
    }

    @Test
    fun detachDoesNotCancelThePublicationCloseItLaunched() {
        setReaderField("_currentPublication", mock(Publication::class.java))

        ReadiumReader.detach()
        dispatcher.scheduler.advanceUntilIdle()

        assertNull(
            getReaderField("_currentPublication"),
            "closePublication() must survive detach() and run to completion"
        )
    }

    @Test
    fun detachCancelsItsJobsBeforeTheFirstTeardownStatement() {
        @Suppress("UNCHECKED_CAST")
        val jobs = getReaderField("jobs") as MutableList<Job>
        val job = Job()
        jobs.add(job)

        // epubNavigator.dispose() is the first thing detach() reaches after the
        // cancel block, by way of epubClose(). Reading the job from inside the
        // stub is what makes this an ordering case rather than an after-the-fact
        // one: a cancel that has merely happened by the time detach() returns
        // would satisfy the assertions below if they ran afterwards.
        var cancelledByFirstTeardown = false
        var jobsHeldAtFirstTeardown = -1
        val navigator = mock(EpubNavigator::class.java)
        doAnswer {
            cancelledByFirstTeardown = job.isCancelled
            jobsHeldAtFirstTeardown = jobs.size
            null
        }.`when`(navigator).dispose()
        setReaderField("epubNavigator", navigator)

        ReadiumReader.detach()

        verify(navigator).dispose()
        assertTrue(
            cancelledByFirstTeardown,
            "detach() must cancel this session's jobs before it starts tearing down"
        )
        assertEquals(
            0,
            jobsHeldAtFirstTeardown,
            "detach() must clear the job list before it starts tearing down"
        )
    }
}
