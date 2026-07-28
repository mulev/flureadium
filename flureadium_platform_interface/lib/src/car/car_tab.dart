/// One root tab shown on a car head unit's tab bar (Continue / Library /
/// Search).
///
/// A serializable value type with runtime guards: a blank id or title would
/// render an unusable tab on the head unit, so both are rejected at
/// construction rather than in debug-only asserts.
class CarTab {
  CarTab({required this.id, required this.title, this.iconName}) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (title.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
  }

  /// Rebuilds a tab from its [toMap] representation.
  factory CarTab.fromMap(Map<String, Object?> map) => CarTab(
    id: map['id']! as String,
    title: map['title']! as String,
    iconName: map['iconName'] as String?,
  );

  /// Opaque host id, e.g. `library`.
  final String id;

  /// Tab label, e.g. `Library`.
  final String title;

  /// Optional platform icon hint, e.g. `books`; renderers map it to a native
  /// system image where available.
  final String? iconName;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'title': title,
    'iconName': iconName,
  };
}
