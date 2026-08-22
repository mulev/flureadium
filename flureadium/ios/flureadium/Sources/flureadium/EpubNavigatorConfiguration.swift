import ReadiumNavigator
import UIKit

/// The editing actions shown in the EPUB long-press selection menu.
let epubEditingActions: [EditingAction] = [.copy, .lookup, .translate]

/// Builds the configuration the EPUB reader hands to Readium.
///
/// `contentInset` is zeroed to remove Readium's undocumented 20 pt / 44 pt
/// top-and-bottom padding (see `EPUBNavigatorViewController.swift` in
/// r2-navigator-swift); all margin and safe area is handled on the Flutter side.
func makeEpubNavigatorConfiguration(
  preferences: EPUBPreferences?
) -> EPUBNavigatorViewController.Configuration {
  var config = EPUBNavigatorViewController.Configuration()
  config.contentInset = [
    .compact: (top: 0, bottom: 0),
    .regular: (top: 0, bottom: 0),
  ]
  // TODO: Make this config configurable from Flutter
  // Might want it to be higher for a local publication than remote.
  config.preloadPreviousPositionCount = 2
  config.preloadNextPositionCount = 4
  config.debugState = true
  config.decorationTemplates = HTMLDecorationTemplate.defaultTemplates(
    alpha: 1.0, experimentalPositioning: true)
  config.editingActions = epubEditingActions
  if let preferences {
    config.preferences = preferences
  }
  return config
}
