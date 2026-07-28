package com.example.flureadium_example

import android.app.Application
import dev.mulev.flureadium.car.FlureadiumCarEngine
import dev.mulev.flureadium.car.MethodChannelCarContentSource
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * STAGE-1 Android host for the car bridge (see the car bridge ADR): starts an
 * app-scoped headless [FlutterEngine] running the example's `carMain` entrypoint
 * — which registers the stub `CarContentProvider` — and publishes a car content
 * source bound to that engine so `PluginMediaService` can answer Android Auto
 * browse/search from a cold, UI-less process.
 *
 * `Application.onCreate` runs whenever the process starts, including when Android
 * Auto binds the media service without the reader UI foregrounded, which is what
 * makes the cold browse path testable in the Desktop Head Unit.
 */
class CarStubApplication : Application() {

    private var carEngine: FlutterEngine? = null

    override fun onCreate() {
        super.onCreate()

        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "carMain",
            ),
        )
        carEngine = engine
        FlureadiumCarEngine.source =
            MethodChannelCarContentSource.fromMessenger(engine.dartExecutor.binaryMessenger)
    }
}
