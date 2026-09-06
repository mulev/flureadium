# Publication

The `Publication` class represents a Readium Web Publication Manifest (RWPM). It contains all metadata, content structure, and resources needed to render an ebook, audiobook, or comic.

**Source:** [publication.dart](../../../flureadium_platform_interface/lib/src/shared/publication/publication.dart)

## Overview

```dart
final pub = await flureadium.openPublication('book.epub');
print(pub.metadata.title);        // "Book Title"
print(pub.tableOfContents.length); // Number of chapters
```

## Structure

```
Publication
├── context            # JSON-LD context URIs
├── metadata           # Title, authors, language, etc.
├── links              # Related resources (self, alternate)
├── readingOrder       # Sequential content spine
├── resources          # Images, stylesheets, fonts
├── tableOfContents    # Navigation structure
└── subCollections     # Page lists, landmarks, etc.
```

## Properties

### context

**Type:** `List<String>`

JSON-LD context URIs for the manifest.

### metadata

**Type:** `Metadata`

Publication metadata including title, authors, language, etc.

```dart
print(pub.metadata.title);           // "Pride and Prejudice"
print(pub.metadata.authors);         // [Contributor(name: "Jane Austen")]
print(pub.metadata.language);        // ["en"]
print(pub.metadata.identifier);      // "urn:isbn:9780141439518"
print(pub.metadata.publisher);       // "Penguin Classics"
print(pub.metadata.publicationDate); // DateTime(1813, 1, 28)
```

### links

**Type:** `List<Link>`

Links to related resources (self, alternate, search, etc.).

### readingOrder

**Type:** `List<Link>`

Ordered list of content documents forming the reading spine.

```dart
for (final link in pub.readingOrder) {
  print('${link.href}: ${link.type}');
  // "chapter1.xhtml: application/xhtml+xml"
}
```

Hrefs are returned in the same format the `Locator` stream emits — as the
native Readium parser produced them, with no synthetic leading slash. A bare
resource such as `001.jpg` stays `001.jpg`, so an href round-tripped between
`readingOrder` and a live `Locator` compares equal. That holds for a packaged
publication whose manifest names itself with a relative `self` link: the href
is resolved against the manifest's location only when that location is one, so
a relative `self` link leaves its siblings untouched. Android is where this
comes up, because readium-kotlin passes a packaged manifest's `self` link
through and readium-swift drops it. A remote manifest served from
`https://host/dir/manifest.json` still resolves its hrefs against
`https://host/dir/`.

### resources

**Type:** `List<Link>`

Additional resources like images, stylesheets, and fonts.

```dart
final images = pub.resources.where(
  (r) => r.type?.startsWith('image/') == true,
);
```

### tableOfContents

**Type:** `List<Link>`

Navigation table of contents. For EPUB3 publications, the hierarchy from `toc.xhtml` is preserved — chapters nested under a part or section come back as `link.children`, not as top-level entries.

```dart
for (final link in pub.tableOfContents) {
  print(link.title);  // "Part I"

  for (final child in link.children) {
    print('  ${child.title}');  // "  Chapter 1"
  }
}
```

To get every entry in reading order, use `flattenToc`:

```dart
import 'package:flureadium/flureadium.dart';

final chapters = flattenToc(pub.tableOfContents);
// [Part I, Chapter 1, Chapter 2, Part II, Chapter 3, ...]
```

`navigableToc(pub)` returns the same flat list with the entries that cannot
produce a locator removed — the ones a reader cannot reach, because
`locatorFromLink` answers null for them. Prefer it in any code that indexes the
contents to decide what is adjacent:

```dart
final reachable = navigableToc(pub);
```

`skipToNext` and `skipToPrevious` flatten the TOC internally, so skip buttons work at any nesting depth without extra setup. Flattening also surfaces entries that are not chapters at all — a byline or an imprint line anchored inside a title page — so the skip additionally passes over any entry that is already on the reader's current page.

### toc

**Type:** `List<Link>`

Alias for `tableOfContents`.

### subCollections

**Type:** `Map<String, List<PublicationCollection>>`

Named subcollections like page-list, landmarks, or guided navigation.

```dart
final pageList = pub.collectionLinks('page-list');
for (final page in pageList) {
  print('Page ${page.title}: ${page.href}');
}
```

### identifier

**Type:** `String`

The publication identifier from metadata, or `'unidentified'`.

```dart
print(pub.identifier);  // "urn:isbn:9780141439518"
```

## Computed Properties

### coverLink

**Type:** `Link?`

The cover image link, if available.

```dart
final cover = pub.coverLink;
if (cover != null) {
  print('Cover: ${cover.href}');
}
```

### coverUri

**Type:** `Uri?`

The cover image URI, if available.

```dart
if (pub.coverUri != null) {
  Image.network(pub.coverUri.toString());
}
```

### conformsToReadiumAudiobook

**Type:** `bool`

Returns `true` if this publication conforms to the Readium audiobook profile.

```dart
if (pub.conformsToReadiumAudiobook) {
  // Enable audiobook controls
  await flureadium.audioEnable();
}
```

### conformsToReadiumEbook

**Type:** `bool`

Returns `true` if this publication conforms to the Readium EPUB profile.

```dart
if (pub.conformsToReadiumEbook) {
  // Enable visual reader
}
```

### containsMediaOverlays

**Type:** `bool`

Returns `true` if this publication contains media overlays (synchronized narration).

```dart
if (pub.containsMediaOverlays) {
  // Show "Read Along" option
}
```

### pageList

**Type:** `List<Link>`

Convenience accessor for the page-list collection.

```dart
final pages = pub.pageList;
print('Total pages: ${pages.length}');
```

## Methods

### linkWithHref

Finds the first link with the given HREF.

```dart
Link? linkWithHref(String href)
```

Searches through readingOrder, resources, and links (including alternates and children).

```dart
final link = pub.linkWithHref('chapter1.xhtml');
if (link != null) {
  print('Found: ${link.title}');
}
```

### linkWithRel

Finds the first link with the given relation.

```dart
Link? linkWithRel(String rel)
```

```dart
final tocLink = pub.linkWithRel('toc');
final coverLink = pub.linkWithRel('cover');
```

### linksWithRel

Finds all links having the given relation.

```dart
List<Link> linksWithRel(String rel)
```

```dart
final coverLinks = pub.linksWithRel('cover');
```

### collectionLinks

Returns links from the first subcollection with the given role.

```dart
List<Link> collectionLinks(String role)
```

```dart
final pageList = pub.collectionLinks('page-list');
final landmarks = pub.collectionLinks('landmarks');
```

### locatorFromLink

Converts a link to a locator for navigation.

```dart
Locator? locatorFromLink(Link link, {MediaType? typeOverride})
```

**Parameters:**
- `link` - The link to convert
- `typeOverride` - Optional media type override

**Returns:** A [Locator](locator.md) for navigation, or `null` if type cannot be determined

```dart
// Navigate to TOC entry
final tocLink = pub.tableOfContents.first;
final locator = pub.locatorFromLink(tocLink);
if (locator != null) {
  await flureadium.goToLocator(locator);
}
```

### copyWith

Creates a copy with the given fields replaced.

```dart
Publication copyWith({
  List<String>? context,
  Metadata? metadata,
  List<Link>? links,
  List<Link>? readingOrder,
  List<Link>? resources,
  List<Link>? tableOfContents,
  Map<String, List<PublicationCollection>>? subCollections,
})
```

### toJson

Serializes to RWPM JSON representation.

```dart
Map<String, dynamic> toJson()
```

### fromJson

Parses from RWPM JSON representation.

```dart
static Publication? fromJson(
  Map<String, dynamic>? json, {
  bool packaged = false,
})
```

## Table of Contents Helpers

Top-level functions from `package:flureadium/flureadium.dart` that resolve a
reading position to a table-of-contents entry.

### findTocIndexByFragment

```dart
({int index, bool ownFile}) findTocIndexByFragment(
  List<Link> toc,
  String fragment,
  String path,
)
```

Finds the entry a heading id names, and reports where it was found. Pass a
flattened TOC, the `toc=` fragment from the position's locations, and the
position's `hrefPath`.

```dart
final fragment = locator.locations?.tocFragment;
if (fragment != null) {
  final match = findTocIndexByFragment(
    flattenToc(pub.tableOfContents),
    fragment,
    locator.hrefPath,
  );
}
```

The null check in that example is the whole guard, and it needs
`flureadium_platform_interface` 0.10.3 or newer to work. Before 0.10.3 a bare
`toc=` — a fragment that is present but names no heading — made `tocFragment`
return an empty string, which passes `!= null` and sends a fragment that
identifies nothing into the lookup. 0.18.1 and later require 0.10.3 for that reason; if
you are on 0.18.0 with a lockfile pinned to 0.10.2, upgrade the platform
interface.

The lookup runs two passes: first inside the resource `path` names, then across
the whole TOC. `ownFile` says which pass matched. `index` is -1 when neither
did, and for an empty fragment.

Read `ownFile` before you act on `index`. A heading id is not unique across a
publication: in a book whose chapters all open with `id="top"`, searching the
whole TOC maps every position to the first entry. The second pass still earns
its place, because during a navigation the locator's href and its `toc=`
fragment disagree for one frame, naming the chapter being left and the chapter
being entered at once, and only that pass resolves it to the one being entered.

Both answers are wrong somewhere, and the two cases look identical from inside
the lookup, so it reports the pass instead of choosing. Accept a cross-resource
match when a stale mid-navigation position is the worse failure. Reject it when
landing in the wrong chapter is.

Chapter skipping rejects it. `resolveCurrentTocIndex`, and so
`skipToNextChapter` and `skipToPreviousChapter`, takes the match only when
`ownFile` is true and falls back to path matching otherwise. That is the policy
you get from `resolveCurrentTocIndex`; apply your own by calling
`findTocIndexByFragment` yourself.

### Related lookups

- `flattenToc(toc)` — every entry in reading order, nesting removed.
- `navigableToc(publication)` — every reachable entry in reading order, nesting
  removed and unresolvable entries dropped.
- `findTocIndexByPath(locator, toc, {lastMatch})` — matches by file path, for
  publications whose headings carry no ids. `lastMatch` picks the last entry in
  the file rather than the first.
- `findTocIndexByPage(locator, toc)` — matches by page number, for PDFs.
- `resolveCurrentTocIndex(...)` — the composite the skip buttons use: a
  remembered index while it still points at the current file, then
  `findTocIndexByFragment`, then page or path matching.

## Link Class

A `Link` represents a reference to content or resources.

### Properties

```dart
Link(
  href: 'chapter1.xhtml',           // Resource path (required)
  type: 'application/xhtml+xml',    // Media type
  title: 'Chapter 1',               // Display title
  rel: ['contents'],                // Relations
  properties: Properties(...),       // Additional properties
  duration: Duration(minutes: 5),   // For audio resources
  bitrate: 128000,                  // For audio resources
  children: [...],                  // Nested links
  alternates: [...],                // Alternate representations
)
```

### Useful Properties

```dart
// Get href without fragment
final hrefPart = link.hrefPart;  // "chapter1.xhtml" (no #anchor)

// Check relations
if (link.rels.contains('cover')) {
  // This is a cover image
}

// Convert to locator
final locator = link.toLocator();
```

## Metadata Class

Publication metadata.

### Properties

```dart
Metadata(
  title: 'Book Title',
  subtitle: 'A Novel',
  identifier: 'urn:isbn:1234567890',
  authors: [Contributor(name: 'Author Name')],
  translators: [...],
  editors: [...],
  artists: [...],
  illustrators: [...],
  narrators: [...],
  contributors: [...],
  publishers: [...],
  language: ['en'],
  publicationDate: DateTime(2024, 1, 1),
  modified: DateTime.now(),
  description: 'Book description...',
  rights: 'Copyright 2024',
  subjects: ['Fiction', 'Romance'],
  conformsTo: ['https://readium.org/webpub-manifest/profiles/epub'],
)
```

## Example Usage

### Display Book Information

```dart
Widget buildBookInfo(Publication pub) {
  return Column(
    children: [
      if (pub.coverUri != null)
        Image.network(pub.coverUri.toString()),
      Text(pub.metadata.title ?? 'Unknown'),
      Text(pub.metadata.authors.map((a) => a.name).join(', ')),
      if (pub.metadata.description != null)
        Text(pub.metadata.description!),
    ],
  );
}
```

### Build Table of Contents

```dart
Widget buildToc(Publication pub) {
  return ListView.builder(
    itemCount: pub.tableOfContents.length,
    itemBuilder: (_, index) {
      final link = pub.tableOfContents[index];
      return _buildTocItem(link, pub, 0);
    },
  );
}

Widget _buildTocItem(Link link, Publication pub, int depth) {
  return Column(
    children: [
      ListTile(
        contentPadding: EdgeInsets.only(left: 16.0 * depth),
        title: Text(link.title ?? 'Untitled'),
        onTap: () async {
          final locator = pub.locatorFromLink(link);
          if (locator != null) {
            await flureadium.goToLocator(locator);
          }
        },
      ),
      ...link.children.map((c) => _buildTocItem(c, pub, depth + 1)),
    ],
  );
}
```

### Check Publication Type

```dart
void setupReader(Publication pub) {
  if (pub.conformsToReadiumAudiobook) {
    // Pure audiobook - show audio player
    flureadium.audioEnable();
  } else if (pub.containsMediaOverlays) {
    // EPUB with synchronized audio - show read-along option
  } else if (pub.conformsToReadiumEbook) {
    // Standard EPUB - show visual reader
  }
}
```

## See Also

- [Locator](locator.md) - Position tracking
- [Flureadium Class](flureadium-class.md) - Main API
- [ReaderWidget](reader-widget.md) - Display widget
