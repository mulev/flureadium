package dk.nota.flureadium

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.mockito.Mockito

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

@OptIn(ExperimentalCoroutinesApi::class)
internal class FlureadiumPluginTest {
  @Test
  fun onMethodCall_returnsNotImplemented() {
    val plugin = FlureadiumPlugin()

    val call = MethodCall("getPlatformVersion", null)
    val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(call, mockResult)

    // FlureadiumPlugin.onMethodCall() returns notImplemented for all method calls
    // The actual method handling is done by PublicationMethodCallHandler
    Mockito.verify(mockResult).notImplemented()
  }
}
