package dev.mulev.flureadium.navigators

import dev.mulev.flureadium.FlutterAudioPreferences
import dev.mulev.flureadium.PluginMediaServiceFacade
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito.doThrow
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerSettings
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test

@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class AudiobookNavigatorPlayErrorTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private class TestableAudiobookNavigator(
        publication: Publication,
        listener: TimebasedNavigator.TimebasedListener,
        preferences: FlutterAudioPreferences
    ) : AudiobookNavigator(publication, listener, null, preferences) {
        override suspend fun initNavigator() {
            // No-op for JVM unit tests.
        }

        fun setTestAudioNavigator(
            navigator: AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>?
        ) {
            audioNavigator = navigator
        }

        fun setTestMediaServiceFacade(facade: PluginMediaServiceFacade?) {
            mediaServiceFacade = facade
        }
    }

    @Suppress("UNCHECKED_CAST")
    @Test
    fun play_callsCloseSession_whenOpenSessionThrows() = runTest {
        val navigator = TestableAudiobookNavigator(
            mock(Publication::class.java),
            mock(TimebasedNavigator.TimebasedListener::class.java),
            FlutterAudioPreferences()
        )
        val mockFacade = mock(PluginMediaServiceFacade::class.java)
        val mockAudioNavigator = mock(AudioNavigator::class.java)
            as AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>
        doThrow(RuntimeException("simulated failure"))
            .`when`(mockFacade)
            .openSession(any(), any())
        navigator.setTestMediaServiceFacade(mockFacade)
        navigator.setTestAudioNavigator(mockAudioNavigator)

        navigator.play(null)

        verify(mockFacade).closeSession()
    }
}
