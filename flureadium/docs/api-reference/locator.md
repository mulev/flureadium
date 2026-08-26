# Locator

The `Locator` class precisely identifies a position within a publication. Locators are used for saving progress, bookmarks, highlights, search results, and navigation.

**Source:** [locator.dart](../../../flureadium_platform_interface/lib/src/shared/publication/locator.dart)

## Overview

```dart
Locator(
  href: 'chapter1.xhtml',
  type: 'application/xhtml+xml',
  title: 'Chapter 1',
  locations: Locations(
    totalProgression: 0.25,
  ),
)
```

## Properties

### href

**Type:** `String` (required)

The path to the content document within the publication. Internally, `href` is always stored in decoded form (e.g. `Happiness v01 [HD].jpg`). When serialized via `toJson()`, the value is percent-encoded for safe transport to native platforms (e.g. `Happiness%20v01%20%5BHD%5D.jpg`). `fromJson()` automatically decodes percent-encoded hrefs on parse.

```dart
print(locator.href);  // "chapter1.xhtml"
```

### type

**Type:** `String` (required)

The media type of the content document.

```dart
print(locator.type);  // "application/xhtml+xml"
```

### title

**Type:** `String?`

Optional title for this position.

```dart
print(locator.title);  // "Chapter 1"
```

### locations

**Type:** `Locations?`

Position metadata. See [Locations](#locations-class) below.

```dart
print(locator.locations?.totalProgression);  // 0.25
```

### text

**Type:** `LocatorText?`

Text context around the position. See [LocatorText](#locatortext-class) below.

```dart
print(locator.text?.highlight);  // "selected text"
```

## Computed Properties

### hrefPath

**Type:** `String`

Returns the href without fragment identifiers or query parameters.

```dart
final locator = Locator(href: 'chapter1.xhtml#section-2?param=1', ...);
print(locator.hrefPath);  // "chapter1.xhtml"
```

### json

**Type:** `String`

Serialized JSON string for storage.

```dart
final jsonString = locator.json;
// '{"href":"chapter1.xhtml","type":"application/xhtml+xml",...}'

// Save to storage
await prefs.setString('position', locator.json);
```

## Factory Methods

### fromJson

Creates a Locator from a JSON map.

```dart
static Locator? fromJson(Map<String, dynamic>? json)
```

```dart
final locator = Locator.fromJson({
  'href': 'chapter1.xhtml',
  'type': 'application/xhtml+xml',
  'locations': {'totalProgression': 0.5},
});
```

### fromJsonString

Creates a Locator from a JSON string.

```dart
static Locator? fromJsonString(String jsonString)
```

```dart
// Restore from storage
final savedJson = prefs.getString('position');
if (savedJson != null) {
  final locator = Locator.fromJsonString(savedJson);
}
```

## Methods

### copyWith

Creates a copy with specified fields replaced.

```dart
Locator copyWith({
  String? href,
  String? type,
  String? title,
  Locations? locations,
  LocatorText? text,
  Map<String, dynamic>? additionalProperties,
})
```

```dart
final updated = locator.copyWith(
  title: 'New Title',
  locations: Locations(totalProgression: 0.75),
);
```

### copyWithLocations

Shortcut to copy with different location properties.

```dart
Locator copyWithLocations({
  List<String>? fragments,
  double? progression,
  int? position,
  double? totalProgression,
  Map<String, dynamic>? otherLocations,
})
```

```dart
final updated = locator.copyWithLocations(
  totalProgression: 0.5,
  position: 10,
);
```

### toTextLocator

Converts to a text-focused locator suitable for navigation.

```dart
Locator toTextLocator()
```

### toJson

Serializes to a JSON map.

```dart
Map<String, dynamic> toJson()
```

## Locations Class

Position information in various formats.

**Source:** [locations.dart](../../../flureadium_platform_interface/lib/src/shared/publication/locations.dart)

### Properties

#### fragments

**Type:** `List<String>`

Fragment identifiers for the position.

```dart
locations.fragments  // ['heading-1', 'toc=Chapter%201']
```

In an EPUB, the `toc=` fragment carries the id of the heading that names the
reader's position. It either carries an id or is not there; it is never present
with an empty value. So a host can treat its presence as proof that a heading
resolved and look the id up in the table of contents without guarding against a
blank one. When no heading, section or body around the position carries an id,
no `toc=` fragment is emitted.

#### progression

**Type:** `double?`

Position within the current resource as a percentage (0.0 to 1.0).

```dart
locations.progression  // 0.25 = 25% through chapter
```

#### position

**Type:** `int?`

Absolute position index (>= 1) in the publication.

```dart
locations.position  // 5 = 5th position
```

#### totalProgression

**Type:** `double?`

Position in the entire publication as a percentage (0.0 to 1.0).

```dart
locations.totalProgression  // 0.1 = 10% through book
```

#### cssSelector

**Type:** `String?`

CSS selector for the position.

```dart
locations.cssSelector  // '#paragraph-3'
```

#### domRange

**Type:** `DomRange?`

HTML DOM range for precise text selection.

#### partialCfi

**Type:** `String?`

EPUB Canonical Fragment Identifier.

### Computed Properties

#### timestamp

**Type:** `int`

For audio positions, extracts the timestamp from fragments.

```dart
// If fragments contains 't=287.5'
locations.timestamp  // 287
```

### Example

```dart
Locations(
  fragments: ['heading-1'],
  progression: 0.25,        // 25% through this chapter
  position: 5,              // 5th reading position
  totalProgression: 0.1,    // 10% through book
  cssSelector: '#para-3',
)
```

## LocatorText Class

Text context around the position.

### Properties

#### before

**Type:** `String?`

Text immediately before the position.

#### highlight

**Type:** `String?`

The selected or highlighted text.

#### after

**Type:** `String?`

Text immediately after the position.

### Example

```dart
LocatorText(
  before: 'This is the text ',
  highlight: 'selected text',
  after: ' and this comes after.',
)
```

## Common Use Cases

### Saving Reading Progress

```dart
// Listen for position changes
flureadium.onTextLocatorChanged.listen((locator) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('book_${pub.identifier}', locator.json);
});
```

### Restoring Reading Position

```dart
// On app launch
final prefs = await SharedPreferences.getInstance();
final savedJson = prefs.getString('book_${pub.identifier}');
if (savedJson != null) {
  final locator = Locator.fromJsonString(savedJson);
  if (locator != null) {
    await flureadium.goToLocator(locator);
  }
}
```

### Creating Bookmarks

```dart
class Bookmark {
  final String id;
  final Locator locator;
  final DateTime created;

  Bookmark({required this.locator})
      : id = uuid.v4(),
        created = DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'locator': locator.toJson(),
    'created': created.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    locator: Locator.fromJson(json['locator'])!,
  );
}
```

### Displaying Progress

```dart
Widget buildProgressIndicator(Locator locator) {
  final progress = locator.locations?.totalProgression ?? 0;
  return Column(
    children: [
      LinearProgressIndicator(value: progress),
      Text('${(progress * 100).toStringAsFixed(1)}% complete'),
    ],
  );
}
```

### Creating Highlights

```dart
void createHighlight(Locator locator, Color color) {
  final highlight = ReaderDecoration(
    id: uuid.v4(),
    locator: locator,
    style: ReaderDecorationStyle(
      style: DecorationStyle.highlight,
      tint: color,
    ),
  );

  flureadium.applyDecorations('highlights', [highlight]);
}
```

## Link Extension

The `LinkLocator` extension adds a `toLocator()` method to `Link`:

```dart
extension LinkLocator on Link {
  Locator toLocator() { ... }
}
```

```dart
final link = pub.tableOfContents.first;
final locator = link.toLocator();
await flureadium.goToLocator(locator);
```

## JSON Format

```json
{
  "href": "chapter1.xhtml",
  "type": "application/xhtml+xml",
  "title": "Chapter 1",
  "locations": {
    "fragments": ["heading-1"],
    "progression": 0.25,
    "position": 5,
    "totalProgression": 0.1,
    "cssSelector": "#para-3"
  },
  "text": {
    "before": "text before ",
    "highlight": "selected text",
    "after": " text after"
  }
}
```

## See Also

- [Publication](publication.md) - Publication model
- [Decorations](decorations.md) - Using locators for highlights
- [Saving Progress Guide](../guides/saving-progress.md) - Progress persistence
