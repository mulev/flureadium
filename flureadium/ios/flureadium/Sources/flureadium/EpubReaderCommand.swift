import Flutter
import ReadiumNavigator
import ReadiumShared

/// A decoded `ReadiumReaderWidget` method-channel call.
///
/// Decoding is separated from execution because the argument shapes — index
/// order, optional trailing flags, the raw locator strings — are the part of the
/// channel a refactor can break silently. Force-unwraps are deliberate and
/// unchanged: a malformed call from our own Dart layer is a programming error,
/// and turning it into a Flutter error is a separate change.
enum EpubReaderCommand {
  case go(locator: Locator, animated: Bool, isAudioBookWithText: Bool)
  case goLeft(animated: Bool)
  case goRight(animated: Bool)
  case setLocation(locator: Locator, isAudioBookWithText: Bool)
  /// Raw locator JSON, or `"null"` when the host sent none.
  case locatorFragments(json: String)
  case currentLocator
  /// Carries the parsed locator for the href comparison and the raw JSON for
  /// the JavaScript call.
  case isLocatorVisible(locator: Locator, json: String)
  case isReaderReady
  case setPreferences(EPUBPreferences)
  case setNavigationConfig(FlutterNavigationConfig)
  /// `decorations` is nil when `json` did not map — the caller answers a
  /// `FlutterError` naming `json`, as it does today. `json` carries the raw
  /// decoration maps Dart sent, purely for that message.
  case applyDecorations(group: String, decorations: [Decoration]?, json: [[String: Any]])
  case dispose

  /// - Returns: nil for a method this view does not implement.
  init?(_ call: FlutterMethodCall) {
    switch call.method {
    case "go":
      let args = call.arguments as! [Any?]
      self = .go(
        locator: try! Locator(jsonString: args[0] as! String, warnings: readiumBugLogger)!,
        animated: args[1] as! Bool,
        isAudioBookWithText: args[2] as? Bool ?? false)
    case "goLeft":
      self = .goLeft(animated: call.arguments as! Bool)
    case "goRight":
      self = .goRight(animated: call.arguments as! Bool)
    case "setLocation":
      let args = call.arguments as! [Any]
      self = .setLocation(
        locator: try! Locator(jsonString: args[0] as! String, warnings: readiumBugLogger)!,
        isAudioBookWithText: args[1] as? Bool ?? false)
    case "getLocatorFragments":
      self = .locatorFragments(json: call.arguments as? String ?? "null")
    case "getCurrentLocator":
      self = .currentLocator
    case "isLocatorVisible":
      let json = call.arguments as! String
      self = .isLocatorVisible(
        locator: try! Locator(jsonString: json, warnings: readiumBugLogger)!, json: json)
    case "isReaderReady":
      self = .isReaderReady
    case "setPreferences":
      self = .setPreferences(EPUBPreferences(fromMap: call.arguments as! [String: String]))
    case "setNavigationConfig":
      self = .setNavigationConfig(
        FlutterNavigationConfig(fromMap: call.arguments as! [String: Any]))
    case "applyDecorations":
      let args = call.arguments as! [Any?]
      let json = args[1] as! [[String: Any]]
      self = .applyDecorations(
        group: args[0] as! String,
        decorations: try? json.map { try Decoration(fromDartMap: $0) },
        json: json)
    case "dispose":
      self = .dispose
    default:
      return nil
    }
  }
}
