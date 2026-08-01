package dev.mulev.flureadium

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.ExperimentalCoroutinesApi

private const val TAG = "FlureadiumPlugin"

@ExperimentalCoroutinesApi
class FlureadiumPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {
    /**
      * The MethodChannel that will the communication between Flutter and native Android
      *
      * This local reference serves to register the plugin with the Flutter Engine and unregister it
      * when the Flutter Engine is detached from the Activity
      */
    private lateinit var publicationChannel: MethodChannel

    private lateinit var publicationMethodCallHandler: PublicationMethodCallHandler

    private lateinit var binaryMessenger: BinaryMessenger

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine")
        binaryMessenger = flutterPluginBinding.binaryMessenger

        // The binding's application context exists with no Activity attached,
        // so a headless engine — the Android Auto car engine, a background
        // isolate — can reach application-only Readium APIs.
        ReadiumReader.attachApplication(flutterPluginBinding.applicationContext)

        // Register reader view factory
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            viewTypeChannelName,
            ReadiumReaderViewFactory(binaryMessenger)
        )

        // Setup publication channel
        publicationMethodCallHandler = PublicationMethodCallHandler()
        publicationChannel = MethodChannel(binaryMessenger, publicationChannelName)
        publicationChannel.setMethodCallHandler(publicationMethodCallHandler)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.d(TAG, "onMethodCall")
        result.notImplemented()
    }

    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine")
        ReadiumReader.detach()
        publicationChannel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.d(TAG, "onAttachedToActivity")

        ReadiumReader.attach(binding.activity, binaryMessenger)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.d(TAG, "onDetachedFromActivityForConfigChanges")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        Log.d(TAG, "onReattachedToActivityForConfigChanges")
    }

    override fun onDetachedFromActivity() {
        Log.d(TAG, "onDetachedFromActivity")
        ReadiumReader.detach()
    }
}
