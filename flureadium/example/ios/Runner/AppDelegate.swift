import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Under the UIScene lifecycle the Flutter view runs on an implicit engine
  // created per scene. Plugins are registered here, against that engine's
  // registry, and only here — also registering in didFinishLaunching would
  // register every plugin on the same engine twice and abort in
  // registrarForPlugin:.
  func didInitializeImplicitFlutterEngine(_ engineBridge: any FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // No configurationForConnecting override: the Info.plist scene manifest routes
  // each connecting scene by role on its own — the window role to SceneDelegate
  // (a FlutterSceneDelegate, loading Main.storyboard) and the CarPlay role to
  // CarPlaySceneDelegate. Overriding it to build the window config by hand black-
  // screened on iOS 17.5, and calling super crashes because FlutterAppDelegate
  // does not implement this optional UIApplicationDelegate method.

  @objc func onCustomEditingAction() {
    debugPrint("onCustomEditingAction")
    // TODO: Find a way to call the plugin here, to trigger a custom action response.
  }
}
