import CarPlay

/// Configures the Search tab's Siri assistant-cell row — the always-present
/// voice entry point for playback.
///
/// CarPlay draws and owns the cell: the app supplies only where it sits and when
/// it shows, never its title, icon, or tap action. Tapping it hands off to Siri,
/// which produces an `INPlayMediaIntent` the host app answers from its Intents
/// extension (there is no list-template or scene delegate callback for the tap).
/// The underlying `CPAssistantCellConfiguration` API ships from iOS 15, so the
/// assistant cell is the baseline search path from iOS 15 up to the iOS 27+
/// typed `CarSearchTemplate` enhancement. iOS 14 CarPlay has no assistant-cell
/// API and gets no dedicated search row.
@available(iOS 15.0, *)
public enum CarAssistantCell {
  /// The media-playback assistant-cell configuration for the Search tab: pinned
  /// to the top and always visible, so voice search is reachable at any time —
  /// not only while CarPlay has limited the app's interface. `assistantAction`
  /// is `.playMedia`, the only action audio apps may use; it requires the host
  /// app to ship an Intents extension handling `INPlayMediaIntent`.
  public static func configuration() -> CPAssistantCellConfiguration {
    CPAssistantCellConfiguration(position: .top, visibility: .always, assistantAction: .playMedia)
  }
}
