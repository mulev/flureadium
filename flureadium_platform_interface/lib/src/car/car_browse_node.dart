/// The kind of a car browse row, driving how a renderer presents it.
enum CarNodeKind {
  /// A root tab (Continue / Library / Search).
  tab,

  /// A non-playable grouping row that pushes a child list when selected.
  container,

  /// A playable pre-recorded audiobook.
  audiobook,

  /// A playable read-aloud (TTS) EPUB.
  ttsBook,

  /// A chapter within the now-playing publication.
  chapter,

  /// The Siri / voice assistant row.
  siri,
}

/// One browsable or playable row shown on a car head unit.
///
/// A serializable value type with no host or reader dependencies, so it
/// survives the Dart↔native hop regardless of the transport mechanism. The
/// host builds these from its own library; renderers turn them into
/// platform templates. [progress] is guarded to `0..1` at construction because
/// native templates (e.g. `CPListItem.playbackProgress`) require that range;
/// an out-of-range value throws rather than surfacing as renderer-specific
/// behavior later.
class CarBrowseNode {
  CarBrowseNode({
    required this.id,
    required this.title,
    this.subtitle,
    this.artworkPath,
    required this.kind,
    this.isPlayable = false,
    this.progress,
    this.isNowPlaying = false,
  }) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (title.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
    final p = progress;
    if (p != null && (p < 0 || p > 1)) {
      throw ArgumentError.value(p, 'progress', 'must be within 0..1');
    }
  }

  /// Rebuilds a node from its [toMap] representation, applying defaults for
  /// absent optional fields.
  factory CarBrowseNode.fromMap(Map<String, Object?> map) => CarBrowseNode(
    id: map['id']! as String,
    title: map['title']! as String,
    subtitle: map['subtitle'] as String?,
    artworkPath: map['artworkPath'] as String?,
    kind: CarNodeKind.values.byName(map['kind']! as String),
    isPlayable: (map['isPlayable'] as bool?) ?? false,
    progress: (map['progress'] as num?)?.toDouble(),
    isNowPlaying: (map['isNowPlaying'] as bool?) ?? false,
  );

  /// Opaque host id, e.g. `book:42` or `genre:sci-fi`.
  final String id;

  /// Primary row text, e.g. `Project Hail Mary`.
  final String title;

  /// Secondary row text, e.g. `Andy Weir · 62%` or `Read-aloud · 18 min left`.
  final String? subtitle;

  /// Host-resolved cover file path or url.
  final String? artworkPath;

  final CarNodeKind kind;

  /// Whether selecting the row starts playback (audiobook / TTS) rather than
  /// pushing a child list.
  final bool isPlayable;

  /// Playback progress in `0..1`, or null when not applicable.
  final double? progress;

  /// Whether this row is the currently playing item.
  final bool isNowPlaying;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'artworkPath': artworkPath,
    'kind': kind.name,
    'isPlayable': isPlayable,
    'progress': progress,
    'isNowPlaying': isNowPlaying,
  };
}
