package dev.mulev.flureadium.car

/**
 * App-scoped hand-off point for the car content source.
 *
 * The Android Auto media service is instantiated by the system, so it can't be
 * given a source through a constructor. Instead the host app (for example, the
 * plugin's example app) stands up its headless car engine and publishes a
 * [MethodChannelCarContentSource] bound to that engine's messenger here; the
 * browse callback reads it. It stays null until the engine is up, which the
 * callback renders as the empty root — the "app not ready" cold state.
 *
 * This is the same app-scoped-static seam the callback already uses for
 * `ReadiumReader`; the browse/search units themselves take an injected source
 * and never touch this holder, so they remain testable in isolation.
 */
object FlureadiumCarEngine {
    @Volatile
    var source: CarContentSource? = null
}
