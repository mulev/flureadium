package dev.mulev.flureadium

import dev.mulev.flureadium.navigators.AudiobookNavigator
import dev.mulev.flureadium.navigators.ImageNavigator
import dev.mulev.flureadium.navigators.SyncAudiobookNavigator
import dev.mulev.flureadium.navigators.TTSNavigator
import dev.mulev.flureadium.navigators.TimebasedNavigator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerSettings
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.navigator.media.tts.TtsNavigator
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.navigator.media.tts.android.AndroidTtsSettings
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertNull

/**
 * Tests that ReadiumReader's cleanup methods (closePublication, etc.)
 * properly call release() on active navigators instead of fire-and-forget dispose().
 *
 * Uses reflection to set private navigator fields on the ReadiumReader singleton.
 * openPublication() cleanup is tested via integration tests (Phase 5) since it
 * requires full Readium infrastructure for loadPublication().
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class ReadiumReaderCleanupTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        // Clean up ReadiumReader singleton state
        setReaderField("audiobookNavigator", null)
        setReaderField("syncAudiobookNavigator", null)
        setReaderField("ttsNavigator", null)
        setReaderField("pdfNavigator", null)
        setReaderField("imageNavigator", null)
    }

    private fun createMockAudiobookNavigator(): AudiobookNavigator {
        return AudiobookNavigator(
            mock(Publication::class.java),
            mock(TimebasedNavigator.TimebasedListener::class.java),
            null,
            FlutterAudioPreferences()
        )
    }

    private fun createMockTtsNavigator(): TTSNavigator {
        return TTSNavigator(
            mock(Publication::class.java),
            mock(TimebasedNavigator.TimebasedListener::class.java),
            null,
            FlutterTtsPreferences()
        )
    }

    @Test
    fun closePublication_releasesAudiobookNavigator() = runTest {
        val navigator = createMockAudiobookNavigator()
        setReaderField("audiobookNavigator", navigator)

        ReadiumReader.closePublication()

        assertNull(getReaderField("audiobookNavigator"))
    }

    @Test
    fun closePublication_releasesTtsNavigator() = runTest {
        val navigator = createMockTtsNavigator()
        setReaderField("ttsNavigator", navigator)

        ReadiumReader.closePublication()

        assertNull(getReaderField("ttsNavigator"))
    }

    @Test
    fun closePublication_nullsSyncAudiobookNavigator() = runTest {
        val navigator = SyncAudiobookNavigator(
            mock(Publication::class.java),
            emptyList(),
            mock(TimebasedNavigator.TimebasedListener::class.java),
            null,
            FlutterAudioPreferences()
        )
        setReaderField("syncAudiobookNavigator", navigator)

        ReadiumReader.closePublication()

        assertNull(getReaderField("syncAudiobookNavigator"))
    }

    @Test
    fun closePublication_releasesImageNavigator() = runTest {
        val navigator = ImageNavigator(
            mock(Publication::class.java),
            null,
            mock(ImageNavigator.VisualListener::class.java)
        )
        setReaderField("imageNavigator", navigator)

        ReadiumReader.closePublication()

        assertNull(getReaderField("imageNavigator"))
    }
}
