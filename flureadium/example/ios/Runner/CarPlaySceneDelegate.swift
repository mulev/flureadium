import CarPlay
import flureadium

/// Adapts the CarPlay scene lifecycle to the flureadium renderer. All
/// template-building lives in the plugin (`CarTemplateRenderer`); this delegate
/// only starts the car engine, builds the channel-backed bridge, and hands the
/// interface controller to the renderer.
@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

  private var renderer: CarTemplateRenderer?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    let bridge = CarPlayContentBridge(binaryMessenger: CarPlayEngine.shared.messenger())
    let renderer = CarTemplateRenderer(
      interfaceController: interfaceController,
      bridge: bridge,
      fallbackStrings: Self.fallbackStrings)
    self.renderer = renderer
    renderer.presentRoot()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    renderer = nil
  }

  /// The host's own status copy, shown synchronously before the Dart provider
  /// answers. The Dart `carMain` registers the same strings for the live path; a
  /// shipping app supplies its localized copy here.
  private static let fallbackStrings = CarContentStrings(
    emptyRootTitle: "Nothing to play yet",
    emptyRootSubtitle: "Add books to see them here",
    voiceUnavailable: "This voice is not installed",
    offline: "This book needs a connection")
}
