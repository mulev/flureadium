package dev.mulev.flureadium.navigators

import android.os.Looper
import dev.mulev.flureadium.FlutterAudioPreferences
import dev.mulev.flureadium.ReadiumReader
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNotSame
import kotlin.test.assertSame
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerSettings
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Regression test for the streamed-audiobook ANR fix.
 *
 * AudiobookNavigator.initNavigator MUST resolve the Readium audio navigator OFF
 * the main thread. Readium's AudioNavigatorFactory.createNavigator probes each
 * reading-order track's duration up front, and for a track whose manifest
 * `duration` is null it reads the remote resource synchronously (blocking
 * network `readAt`). On `Dispatchers.Main.immediate` that froze the UI thread
 * (ANR). The fix wraps the navigator build in `withContext(navigatorDispatcher)`.
 *
 * The test overrides `navigatorDispatcher` with a single-thread executor and
 * overrides `buildAudioNavigator` to record the thread it runs on (so no real
 * ExoPlayer / MetadataRetriever is constructed), then asserts the build ran off
 * the main looper thread and the navigator + media-service facade were still
 * wired up afterwards on the main scope.
 */
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
internal class AudiobookNavigatorInitDispatchTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        // initNavigator constructs PluginMediaServiceFacade(ReadiumReader.application),
        // which throws unless an Application is attached. Provide the Robolectric one.
        setAppRef(WeakReference(RuntimeEnvironment.getApplication()))
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        setAppRef(null)
    }

    private fun setAppRef(value: WeakReference<*>?) {
        val field = ReadiumReader::class.java.getDeclaredField("appRef")
        field.isAccessible = true
        field.set(ReadiumReader, value)
    }

    private fun AudiobookNavigator.readField(name: String): Any? {
        val field = AudiobookNavigator::class.java.getDeclaredField(name)
        field.isAccessible = true
        return field.get(this)
    }

    /**
     * Records the thread `buildAudioNavigator` runs on and returns a mock
     * navigator instead of building a real one, and pins the navigator
     * dispatcher to an identifiable single-thread executor.
     */
    private class RecordingAudiobookNavigator(
        publication: Publication,
        listener: TimebasedNavigator.TimebasedListener,
        preferences: FlutterAudioPreferences,
        private val navigator: AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>
    ) : AudiobookNavigator(publication, listener, null, preferences) {

        val ioDispatcher: ExecutorCoroutineDispatcher =
            Executors.newSingleThreadExecutor { r -> Thread(r, "audio-nav-test-io") }
                .asCoroutineDispatcher()

        override val navigatorDispatcher: CoroutineDispatcher = ioDispatcher

        @Volatile
        var buildThread: Thread? = null

        override suspend fun buildAudioNavigator(): AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences> {
            buildThread = Thread.currentThread()
            return navigator
        }

        // Isolate the off-main build: real listener wiring reads the navigator's
        // playback/currentLocator flows, which are null on a bare mock and are
        // unrelated to what this test asserts.
        override fun setupNavigatorListeners() {
            // no-op
        }
    }

    @Test
    fun initNavigator_resolvesNavigatorOffMainThread() = runTest {
        @Suppress("UNCHECKED_CAST")
        val mockNavigator =
            mock(AudioNavigator::class.java) as AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>
        val listener = mock(TimebasedNavigator.TimebasedListener::class.java)
        val navigator = RecordingAudiobookNavigator(
            mock(Publication::class.java),
            listener,
            FlutterAudioPreferences(),
            mockNavigator
        )

        try {
            navigator.initNavigator()

            val buildThread = navigator.buildThread
            assertNotNull(buildThread, "buildAudioNavigator must have run")
            assertNotSame(
                Looper.getMainLooper().thread,
                buildThread,
                "navigator must be built off the main thread"
            )
            assertSame(
                mockNavigator,
                navigator.readField("audioNavigator"),
                "audioNavigator must be assigned after init"
            )
            assertNotNull(
                navigator.readField("mediaServiceFacade"),
                "mediaServiceFacade must be wired after init"
            )
        } finally {
            navigator.dispose()
            navigator.ioDispatcher.close()
        }
    }
}
