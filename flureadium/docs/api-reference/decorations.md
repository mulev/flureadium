# Decorations

Decorations add visual markers to publication content, such as highlights, bookmarks, and annotations.

**Source:** [reader_decoration.dart](../../../flureadium_platform_interface/lib/src/reader/reader_decoration.dart)

## Overview

```dart
await flureadium.applyDecorations('highlights', [
  ReaderDecoration(
    id: 'highlight-1',
    locator: selectedLocator,
    style: ReaderDecorationStyle(
      style: DecorationStyle.highlight,
      tint: Color(0xFFFFFF00),
    ),
  ),
]);
```

## DecorationStyle Enum

Available decoration styles.

```dart
enum DecorationStyle {
  highlight,  // Background color highlight
  underline,  // Underline decoration
}
```

## ReaderDecoration

Represents a single decoration applied to the content.

### Constructor

```dart
ReaderDecoration({
  required String id,
  required Locator locator,
  required ReaderDecorationStyle style,
})
```

### Properties

#### id

**Type:** `String` (required)

Unique identifier for this decoration.

```dart
id: 'highlight-1'
id: 'bookmark-abc123'
id: uuid.v4()
```

#### locator

**Type:** `Locator` (required)

The position where the decoration should appear. See [Locator](locator.md).

```dart
locator: selectedLocator
locator: bookmarkPosition
```

#### style

**Type:** `ReaderDecorationStyle` (required)

Visual styling for the decoration. See [ReaderDecorationStyle](#readerdecorationstyle) below.

### Methods

#### toJson

Serializes to JSON.

```dart
Map<String, dynamic> toJson()
```

#### fromJsonMap

Creates from JSON.

```dart
factory ReaderDecoration.fromJsonMap(Map<String, dynamic> map)
```

## ReaderDecorationStyle

Visual styling for decorations.

### Constructor

```dart
ReaderDecorationStyle({
  required DecorationStyle style,
  required Color tint,
})
```

### Properties

#### style

**Type:** `DecorationStyle` (required)

The type of decoration (highlight or underline).

#### tint

**Type:** `Color` (required)

The color of the decoration.

```dart
tint: Color(0xFFFFFF00)  // Yellow
tint: Color(0xFF00FF00)  // Green
tint: Color(0xFFFF0000)  // Red
tint: Color(0xFF0000FF)  // Blue
```

### Methods

#### toJson

Serializes to JSON.

```dart
Map<String, dynamic> toJson()
```

## Applying Decorations

### applyDecorations

Use `flureadium.applyDecorations()` to add decorations:

```dart
Future<void> applyDecorations(String id, List<ReaderDecoration> decorations)
```

**Parameters:**
- `id` - Group identifier for these decorations
- `decorations` - List of decorations to apply

**Important:** Decorations are grouped by ID. Calling `applyDecorations` with the same ID replaces all previous decorations in that group.

### Grouping Decorations

Use different group IDs for different types of decorations:

```dart
// Highlights group
await flureadium.applyDecorations('highlights', highlights);

// Bookmarks group
await flureadium.applyDecorations('bookmarks', bookmarks);

// Search results group
await flureadium.applyDecorations('search', searchResults);

// Annotations group
await flureadium.applyDecorations('annotations', annotations);
```

### Clearing Decorations

Pass an empty list to clear decorations for a group:

```dart
// Clear all highlights
await flureadium.applyDecorations('highlights', []);

// Clear search results
await flureadium.applyDecorations('search', []);
```

### Rejected Decorations

A decoration the native side cannot read fails the whole call, so nothing in that batch is drawn. That happens when `id` is missing, when `locator` is missing or is not a locator map, or when the style carries no usable `tint`.

The call still answers. `applyDecorations` throws a `PlatformException` naming the payload it could not map, and the group keeps whatever it had before, so the reader is left as it was and nothing is applied halfway. `setDecorationStyle` works the same way: an unusable style map comes back as an error and the styles already in use stay put.

A wrong payload is never fatal. The plugin rejects it and replies instead of trapping, so a bad decoration cannot take the host app down.

```dart
try {
  await flureadium.applyDecorations('highlights', [decoration]);
} on PlatformException catch (e) {
  // e.message names the decoration that could not be decoded.
}
```

The exception `code` is platform-specific and is not part of the contract: iOS sends `JSON mapping error` ([`ReadiumReaderView.swift:385-390`](../../ios/flureadium/Sources/flureadium/ReadiumReaderView.swift)), Android sends the thrown exception's class name from its generic handler (`class java.lang.IllegalArgumentException`, [`ReadiumReaderWidget.kt:873`](../../android/src/main/kotlin/dev/mulev/flureadium/ReadiumReaderWidget.kt)). What both platforms guarantee is the type — `PlatformException` — and a message naming the offending decoration.

## Method-Channel Wire Format

`applyDecorations` is forwarded to the active reader view over that view's method channel ([`lib/reader_channel.dart:121-130`](../../lib/reader_channel.dart)). The arguments are a two-element list — the group id, then the decorations:

```json
[
  "highlights",
  [
    {
      "id": "highlight-1",
      "locator": { "href": "chapter1.xhtml", "type": "application/xhtml+xml" },
      "style": { "style": "highlight", "tint": "#ffff00" }
    }
  ]
]
```

| Key | Type on the wire | Produced by |
|---|---|---|
| `id` | String | `ReaderDecoration.toJson()` |
| `locator` | Map — the full `Locator.toJson()`, not a JSON string | `Locator.toJson()` |
| `style.style` | String — the `DecorationStyle` enum name, `highlight` or `underline` | `DecorationStyle.name` |
| `style.tint` | String — lowercase CSS hex, `#rrggbb`, or `#aarrggbb` when the colour's alpha is below 1 | `Color.toCSS()` |

`locator` is a nested map, and so is `style` — neither is flattened onto the decoration and neither is JSON-encoded into a string. Both native decoders read this shape and nothing else. The producers are `ReaderDecoration.toJson()` and `ReaderDecorationStyle.toJson()` ([`reader_decoration.dart:36-40`, `:49`](../../../flureadium_platform_interface/lib/src/reader/reader_decoration.dart)), and the hex comes from `toCSS()` ([`readium_color_extension.dart:4-15`](../../../flureadium_platform_interface/lib/src/extensions/readium_color_extension.dart)), which prepends the alpha byte only when the colour is translucent.

### Readers that accept the call and do nothing

Decorations only render in the EPUB reader. The other readers answer the call successfully so callers do not have to branch on publication type:

- **CBZ / DiViNa (iOS)** — `ImageReaderView.swift:228-229` answers `result(nil)`.
- **Audiobooks (iOS)** — `AudioReaderView.swift:51-54` answers `result(nil)`; the comment there notes Dart types the method as `Future<void>`, so `nil` is the whole contract.
- **Web** — `lib/reader_widget_web.dart:152-157` logs `applyDecorations not implemented in web version` and returns.

## Common Use Cases

### Creating Highlights

```dart
class HighlightManager {
  final List<ReaderDecoration> _highlights = [];

  void addHighlight(Locator locator, Color color) {
    final highlight = ReaderDecoration(
      id: uuid.v4(),
      locator: locator,
      style: ReaderDecorationStyle(
        style: DecorationStyle.highlight,
        tint: color,
      ),
    );
    _highlights.add(highlight);
    _applyHighlights();
  }

  void removeHighlight(String id) {
    _highlights.removeWhere((h) => h.id == id);
    _applyHighlights();
  }

  Future<void> _applyHighlights() async {
    await flureadium.applyDecorations('highlights', _highlights);
  }
}
```

### Color-Coded Highlights

```dart
enum HighlightColor {
  yellow(Color(0xFFFFFF00)),
  green(Color(0xFF90EE90)),
  blue(Color(0xFF87CEEB)),
  pink(Color(0xFFFFB6C1)),
  orange(Color(0xFFFFD700));

  final Color color;
  const HighlightColor(this.color);
}

void addColoredHighlight(Locator locator, HighlightColor color) {
  final highlight = ReaderDecoration(
    id: uuid.v4(),
    locator: locator,
    style: ReaderDecorationStyle(
      style: DecorationStyle.highlight,
      tint: color.color,
    ),
  );
  // Add to list and apply
}
```

### Bookmark Indicators

```dart
class BookmarkManager {
  final List<ReaderDecoration> _bookmarks = [];

  void toggleBookmark(Locator locator) {
    final existingIndex = _bookmarks.indexWhere(
      (b) => b.locator.href == locator.href,
    );

    if (existingIndex >= 0) {
      _bookmarks.removeAt(existingIndex);
    } else {
      _bookmarks.add(ReaderDecoration(
        id: uuid.v4(),
        locator: locator,
        style: ReaderDecorationStyle(
          style: DecorationStyle.underline,
          tint: Color(0xFFFF0000),
        ),
      ));
    }

    flureadium.applyDecorations('bookmarks', _bookmarks);
  }

  bool isBookmarked(Locator locator) {
    return _bookmarks.any((b) => b.locator.href == locator.href);
  }
}
```

### Search Result Highlighting

```dart
void highlightSearchResults(List<Locator> results) {
  final decorations = results.map((locator) => ReaderDecoration(
    id: 'search-${locator.hashCode}',
    locator: locator,
    style: ReaderDecorationStyle(
      style: DecorationStyle.highlight,
      tint: Color(0xFFFFD700),  // Gold
    ),
  )).toList();

  flureadium.applyDecorations('search', decorations);
}

void clearSearchResults() {
  flureadium.applyDecorations('search', []);
}
```

### TTS Highlighting

For text-to-speech, use `setDecorationStyle` to highlight the current utterance:

```dart
await flureadium.setDecorationStyle(
  // Style for current sentence
  ReaderDecorationStyle(
    style: DecorationStyle.highlight,
    tint: Color(0xFFFFFF00),  // Yellow
  ),
  // Style for current word
  ReaderDecorationStyle(
    style: DecorationStyle.underline,
    tint: Color(0xFF0000FF),  // Blue
  ),
);
```

## Persisting Decorations

### Save to Storage

```dart
class DecorationStorage {
  Future<void> saveHighlights(
    String bookId,
    List<ReaderDecoration> highlights,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final json = highlights.map((h) => h.toJson()).toList();
    await prefs.setString('highlights_$bookId', jsonEncode(json));
  }

  Future<List<ReaderDecoration>> loadHighlights(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('highlights_$bookId');
    if (jsonStr == null) return [];

    final List<dynamic> json = jsonDecode(jsonStr);
    return json
        .map((j) => ReaderDecoration.fromJsonMap(j))
        .toList();
  }
}
```

### Apply on Book Open

```dart
Future<void> openBook(String bookId, String path) async {
  final pub = await flureadium.openPublication(path);

  // Load and apply saved decorations
  final storage = DecorationStorage();
  final highlights = await storage.loadHighlights(bookId);
  final bookmarks = await storage.loadBookmarks(bookId);

  await flureadium.applyDecorations('highlights', highlights);
  await flureadium.applyDecorations('bookmarks', bookmarks);
}
```

## JSON Format

### ReaderDecoration

```json
{
  "id": "highlight-123",
  "locator": {
    "href": "chapter1.xhtml",
    "type": "application/xhtml+xml",
    "locations": { "totalProgression": 0.25 },
    "text": { "highlight": "selected text" }
  },
  "style": {
    "style": "highlight",
    "tint": "#ffff00"
  }
}
```

## See Also

- [Locator](locator.md) - Position tracking for decorations
- [Flureadium Class](flureadium-class.md) - Main API for applying decorations
- [Highlights Guide](../guides/highlights-annotations.md) - Complete highlighting guide
