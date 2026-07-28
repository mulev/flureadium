/// Host-supplied, already-localized status strings the car renderers show
/// verbatim.
///
/// flureadium owns none of this copy: the host (e.g. a reader app) passes it in
/// already localized, keeping the OSS and localization boundary intact. Every
/// field is required non-empty because blank status copy must never reach a head
/// unit; the guards throw [ArgumentError] at construction and when decoding, so
/// native callers get a stable failure rather than a silent empty label.
class CarContentStrings {
  CarContentStrings({
    required this.emptyRootTitle,
    required this.emptyRootSubtitle,
    required this.voiceUnavailable,
    required this.offline,
  }) {
    _requireNonEmpty(emptyRootTitle, 'emptyRootTitle');
    _requireNonEmpty(emptyRootSubtitle, 'emptyRootSubtitle');
    _requireNonEmpty(voiceUnavailable, 'voiceUnavailable');
    _requireNonEmpty(offline, 'offline');
  }

  /// Rebuilds the strings from a [toMap] representation, rejecting any missing
  /// or blank field with an [ArgumentError].
  factory CarContentStrings.fromMap(Map<String, Object?> map) =>
      CarContentStrings(
        emptyRootTitle: _readNonEmpty(map, 'emptyRootTitle'),
        emptyRootSubtitle: _readNonEmpty(map, 'emptyRootSubtitle'),
        voiceUnavailable: _readNonEmpty(map, 'voiceUnavailable'),
        offline: _readNonEmpty(map, 'offline'),
      );

  /// Empty-library title, e.g. `Nothing to play yet`.
  final String emptyRootTitle;

  /// Empty-library subtitle explaining how content appears.
  final String emptyRootSubtitle;

  /// Shown when a book's TTS voice is not installed (status-only).
  final String voiceUnavailable;

  /// Shown when a streamed book needs a connection (status-only).
  final String offline;

  Map<String, Object?> toMap() => <String, Object?>{
    'emptyRootTitle': emptyRootTitle,
    'emptyRootSubtitle': emptyRootSubtitle,
    'voiceUnavailable': voiceUnavailable,
    'offline': offline,
  };
}

void _requireNonEmpty(String value, String name) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

String _readNonEmpty(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw ArgumentError.value(value, key, 'must be a non-empty string');
  }
  return value;
}
