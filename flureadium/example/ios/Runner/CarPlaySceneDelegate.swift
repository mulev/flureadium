import CarPlay
import flureadium

/// Adapts the CarPlay scene lifecycle to the flureadium renderer. All
/// template-building lives in the plugin (`CarTemplateRenderer`); this delegate
/// only starts the car engine, builds the channel-backed bridge, and hands the
/// interface controller to the renderer.
@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate,
  CPSessionConfigurationDelegate
{

  private var renderer: CarTemplateRenderer?
  private var sessionConfiguration: CPSessionConfiguration?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    let sessionConfiguration = CPSessionConfiguration(delegate: self)
    self.sessionConfiguration = sessionConfiguration
    let bridge = CarPlayContentBridge(binaryMessenger: CarPlayEngine.shared.messenger())
    let renderer = CarTemplateRenderer(
      interfaceController: interfaceController,
      bridge: bridge,
      fallbackStrings: Self.fallbackStrings,
      isKeyboardAvailable: { [weak sessionConfiguration] in
        guard let sessionConfiguration else { return false }
        return !sessionConfiguration.limitedUserInterfaces.contains(.keyboard)
      })
    self.renderer = renderer
    renderer.presentRoot()
    // STAGE-1 stub's now-playing item is an audiobook, so the full button set
    // (Bookmark + Speed + Chapters) installs and round-trips over the channel.
    renderer.installNowPlayingButtons(isAudiobook: true)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    renderer = nil
    sessionConfiguration = nil
  }

  func sessionConfiguration(
    _ sessionConfiguration: CPSessionConfiguration,
    limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface
  ) {
    // The renderer reads keyboard availability live from the configuration when
    // it builds the Search tab, so no action is needed on change here.
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
