package dev.mulev.flureadium.navigators

import dev.mulev.flureadium.FlutterAudioPreferences
import dev.mulev.flureadium.PluginMediaServiceFacade
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.mockito.Mockito.inOrder
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Tests that AudiobookNavigator forwards TimebasedState.Ended to the listener
 * and cancels forwarding jobs BEFORE closing the media session, so the
 * un-throttled teardown can't push a post-Ended state that the stacked
 * throttleLatest windows coalesce over Ended.
 *
 * Uses a test subclass to access protected fields (jobs, mediaServiceFacade)
 * and to invoke the protected onAudioNavigatorEnded() handler.
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class AudiobookNavigatorEndedTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    /**
     * Subclass that exposes the Ended handler and protected fields for testing.
     */
    private class TestableAudiobookNavigator(
        publication: Publication,
        listener: TimebasedNavigator.TimebasedListener,
        preferences: FlutterAudioPreferences
    ) : AudiobookNavigator(publication, listener, null, preferences) {

        override suspend fun initNavigator() {
            // No-op — skip ExoPlayer setup in tests
        }

        fun setTestMediaServiceFacade(facade: PluginMediaServiceFacade?) {
            mediaServiceFacade = facade
        }

        fun addTestJob(job: Job) {
            jobs.add(job)
        }

        fun callOnAudioNavigatorEnded() {
            onAudioNavigatorEnded()
        }
    }

    private fun navigatorWith(
        listener: TimebasedNavigator.TimebasedListener
    ): TestableAudiobookNavigator =
        TestableAudiobookNavigator(
            mock(Publication::class.java),
            listener,
            FlutterAudioPreferences()
        )

    @Test
    fun endedForwardsStateToListener() = runTest {
        val listener = mock(TimebasedNavigator.TimebasedListener::class.java)
        val navigator = navigatorWith(listener)

        navigator.callOnAudioNavigatorEnded()

        verify(listener)
            .onTimebasedPlaybackStateChanged(TimebasedNavigator.TimebasedState.Ended)
    }

    @Test
    fun endedCancelsForwardingJobs() = runTest {
        val listener = mock(TimebasedNavigator.TimebasedListener::class.java)
        val navigator = navigatorWith(listener)
        val job = Job()
        navigator.addTestJob(job)

        navigator.callOnAudioNavigatorEnded()

        assertTrue(job.isCancelled)
    }

    @Test
    fun endedForwardsBeforeClosingSession() = runTest {
        val listener = mock(TimebasedNavigator.TimebasedListener::class.java)
        val facade = mock(PluginMediaServiceFacade::class.java)
        val navigator = navigatorWith(listener)
        navigator.setTestMediaServiceFacade(facade)

        navigator.callOnAudioNavigatorEnded()

        val order = inOrder(listener, facade)
        order.verify(listener)
            .onTimebasedPlaybackStateChanged(TimebasedNavigator.TimebasedState.Ended)
        order.verify(facade).closeSession()
    }
}
