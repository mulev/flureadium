import Flutter

/// Owns the example app's headless car `FlutterEngine` for STAGE-1 CarPlay
/// validation (car bridge ADR, variant (a): app-scoped headless engine +
/// method channel).
///
/// Engine ownership is a host/app concern, so it lives in the example Runner,
/// not the flureadium plugin — a shipping app (Fablum, Phase 5) provides its own
/// strategy here (a dedicated car engine like this, or a single shared app
/// engine) without changing the plugin's renderer or bridge.
///
/// It runs the `carMain` Dart entrypoint once so the `dev.mulev.flureadium/car`
/// channel has a registered provider to answer, and exposes the engine's
/// messenger for the CarPlay scene's bridge.
@available(iOS 14.0, *)
final class CarPlayEngine {
  static let shared = CarPlayEngine()

  private var engine: FlutterEngine?

  private init() {}

  /// Starts the car engine on `carMain` and registers the app's plugins against
  /// it. Idempotent: later calls return the running engine's messenger.
  func messenger() -> FlutterBinaryMessenger {
    if let engine = engine {
      return engine.binaryMessenger
    }
    let engine = FlutterEngine(
      name: "flureadium.car", project: nil, allowHeadlessExecution: true)
    engine.run(withEntrypoint: "carMain")
    GeneratedPluginRegistrant.register(with: engine)
    self.engine = engine
    return engine.binaryMessenger
  }
}
