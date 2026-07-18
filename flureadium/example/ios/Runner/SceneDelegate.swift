import Flutter
import UIKit

/// Hosts the Flutter UI under the UIScene lifecycle. Declaring a CarPlay scene
/// forces the whole app onto UIScene, so the phone window needs its own scene
/// delegate; `FlutterSceneDelegate` attaches the FlutterViewController window
/// for us. Without it the app launches to a blank screen and every
/// launch/integration test fails.
class SceneDelegate: FlutterSceneDelegate {}
