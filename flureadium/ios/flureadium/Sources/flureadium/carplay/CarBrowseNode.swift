import Foundation

/// The kind of a car browse row, mirroring the Dart `CarNodeKind`. Drives how a
/// renderer presents the row (tab vs container vs playable vs assistant cell).
public enum CarNodeKind: String {
  case tab
  case container
  case audiobook
  case ttsBook
  case chapter
  case siri
}

/// One browsable or playable row shown on a car head unit — the native mirror
/// of the Dart `CarBrowseNode`, decoded from the transport channel.
///
/// A plain value type with no reader dependencies, so it survives the
/// native↔Dart hop. Renderers turn it into platform templates; the host builds
/// it from its own library.
public struct CarBrowseNode: Equatable {
  public let id: String
  public let title: String
  public let subtitle: String?
  public let artworkPath: String?
  public let kind: CarNodeKind
  public let isPlayable: Bool
  public let progress: Double?
  public let isNowPlaying: Bool

  public init(
    id: String,
    title: String,
    subtitle: String? = nil,
    artworkPath: String? = nil,
    kind: CarNodeKind,
    isPlayable: Bool = false,
    progress: Double? = nil,
    isNowPlaying: Bool = false
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.artworkPath = artworkPath
    self.kind = kind
    self.isPlayable = isPlayable
    self.progress = progress
    self.isNowPlaying = isNowPlaying
  }

  /// Decodes one node from its channel map, or returns nil if a required field
  /// (id, title, a known kind) is missing — a malformed row is dropped rather
  /// than rendered as a broken cell.
  public init?(map: [String: Any]) {
    guard let id = map["id"] as? String, !id.isEmpty,
      let title = map["title"] as? String, !title.isEmpty,
      let kindName = map["kind"] as? String,
      let kind = CarNodeKind(rawValue: kindName)
    else { return nil }
    self.id = id
    self.title = title
    self.kind = kind
    self.subtitle = map["subtitle"] as? String
    self.artworkPath = map["artworkPath"] as? String
    self.isPlayable = (map["isPlayable"] as? Bool) ?? false
    self.progress = (map["progress"] as? NSNumber)?.doubleValue
    self.isNowPlaying = (map["isNowPlaying"] as? Bool) ?? false
  }
}

/// One root tab on a car head unit's tab bar — the native mirror of the Dart
/// `CarTab`.
public struct CarTab: Equatable {
  public let id: String
  public let title: String
  public let iconName: String?

  public init(id: String, title: String, iconName: String? = nil) {
    self.id = id
    self.title = title
    self.iconName = iconName
  }

  /// Decodes one tab from its channel map, or nil if id/title are missing.
  public init?(map: [String: Any]) {
    guard let id = map["id"] as? String, !id.isEmpty,
      let title = map["title"] as? String, !title.isEmpty
    else { return nil }
    self.id = id
    self.title = title
    self.iconName = map["iconName"] as? String
  }
}

/// Host-supplied, already-localized status strings the car renderer shows
/// verbatim — the native mirror of the Dart `CarContentStrings`. flureadium
/// owns none of this copy.
public struct CarContentStrings: Equatable {
  public let emptyRootTitle: String
  public let emptyRootSubtitle: String
  public let voiceUnavailable: String
  public let offline: String

  public init(
    emptyRootTitle: String,
    emptyRootSubtitle: String,
    voiceUnavailable: String,
    offline: String
  ) {
    self.emptyRootTitle = emptyRootTitle
    self.emptyRootSubtitle = emptyRootSubtitle
    self.voiceUnavailable = voiceUnavailable
    self.offline = offline
  }

  /// Decodes the strings from their channel map, or nil if any field is missing
  /// or blank — the renderer then falls back to a bare (non-blank) template
  /// rather than showing empty labels.
  public init?(map: [String: Any]) {
    guard let emptyRootTitle = map["emptyRootTitle"] as? String, !emptyRootTitle.isEmpty,
      let emptyRootSubtitle = map["emptyRootSubtitle"] as? String, !emptyRootSubtitle.isEmpty,
      let voiceUnavailable = map["voiceUnavailable"] as? String, !voiceUnavailable.isEmpty,
      let offline = map["offline"] as? String, !offline.isEmpty
    else { return nil }
    self.emptyRootTitle = emptyRootTitle
    self.emptyRootSubtitle = emptyRootSubtitle
    self.voiceUnavailable = voiceUnavailable
    self.offline = offline
  }
}
