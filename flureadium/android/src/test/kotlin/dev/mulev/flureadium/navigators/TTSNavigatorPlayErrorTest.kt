package dev.mulev.flureadium.navigators

import dev.mulev.flureadium.FlutterTtsPreferences
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
import org.readium.navigator.media.tts.TtsNavigator
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.navigator.media.tts.android.AndroidTtsSettings
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test

@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class TTSNavigatorPlayErrorTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun TTSNavigator.setField(name: String, value: Any?) {
        val field = TTSNavigator::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(this, value)
    }

    @Suppress("UNCHECKED_CAST")
    @Test
    fun play_callsCloseSession_whenOpenSessionThrows() = runTest {
        val navigator = TTSNavigator(
            mock(Publication::class.java),
            mock(TimebasedNavigator.TimebasedListener::class.java),
            null,
            FlutterTtsPreferences()
        )
        val mockFacade = mock(PluginMediaServiceFacade::class.java)
        val mockTtsNavigator = mock(TtsNavigator::class.java)
            as TtsNavigator<AndroidTtsSettings, AndroidTtsPreferences, AndroidTtsEngine.Error, AndroidTtsEngine.Voice>
        doThrow(RuntimeException("simulated failure"))
            .`when`(mockFacade)
            .openSession(any(), any())
        navigator.setField("mediaServiceFacade", mockFacade)
        navigator.setField("ttsNavigator", mockTtsNavigator)

        navigator.play(null)

        verify(mockFacade).closeSession()
    }
}
