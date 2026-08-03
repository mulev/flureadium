package dev.mulev.flureadium

import android.app.Activity
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformViewRegistry
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * The plugin attaches to an Activity only when a Flutter UI exists. A headless
 * engine — the Android Auto car engine, a background isolate — never gets one,
 * so everything reading [ReadiumReader.application] (TTS voice queries,
 * navigator construction) has to work off the engine attach alone.
 *
 * These tests drive the real [FlureadiumPlugin] lifecycle callbacks rather than
 * calling [ReadiumReader] directly, because the original defect was a missing
 * callback wiring, not a missing method.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class)
internal class FlureadiumPluginEngineAttachTest {

    @BeforeTest
    fun setUp() {
        clearApplicationRef()
    }

    @AfterTest
    fun tearDown() {
        clearApplicationRef()
    }

    @Test
    fun onAttachedToEngine_withoutActivity_exposesApplication() {
        FlureadiumPlugin().onAttachedToEngine(engineBinding())

        // The exact expression PublicationChannel.ttsGetSystemVoices evaluates.
        assertNotNull(ReadiumReader.application.applicationContext)
    }

    @Test
    fun onDetachedFromActivity_keepsApplication() {
        val plugin = FlureadiumPlugin()
        plugin.onAttachedToEngine(engineBinding())
        plugin.onAttachedToActivity(activityBinding())

        plugin.onDetachedFromActivity()

        assertNotNull(ReadiumReader.application.applicationContext)
    }

    @Test
    fun application_beforeAnyAttach_throws() {
        val error = assertFailsWith<IllegalStateException> { ReadiumReader.application }

        // The message has to name the call that actually seeds the reference.
        assertTrue(error.message!!.contains("attachApplication"))
    }

    @Test
    fun attachApplication_withActivityWithoutApplication_leavesApplicationUnset() {
        ReadiumReader.attachApplication(mock(Activity::class.java))

        assertFailsWith<IllegalStateException> { ReadiumReader.application }
    }

    @Test
    fun attachApplication_withActivityWithoutApplication_keepsSeededApplication() {
        ReadiumReader.attachApplication(RuntimeEnvironment.getApplication())

        // Every engine attach calls this, so an unresolvable context must not
        // wipe the reference an earlier engine seeded.
        ReadiumReader.attachApplication(mock(Activity::class.java))

        assertNotNull(ReadiumReader.application.applicationContext)
    }

    private fun engineBinding(): FlutterPluginBinding =
        mock(FlutterPluginBinding::class.java).also { binding ->
            `when`(binding.applicationContext).thenReturn(RuntimeEnvironment.getApplication())
            `when`(binding.binaryMessenger).thenReturn(mock(BinaryMessenger::class.java))
            `when`(binding.platformViewRegistry).thenReturn(mock(PlatformViewRegistry::class.java))
        }

    private fun activityBinding(): ActivityPluginBinding =
        mock(ActivityPluginBinding::class.java).also { binding ->
            `when`(binding.activity).thenReturn(mock(Activity::class.java))
        }

    private fun clearApplicationRef() {
        val field = ReadiumReader::class.java.getDeclaredField("appRef")
        field.isAccessible = true
        field.set(ReadiumReader, null)
    }
}
