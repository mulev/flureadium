# EPUB Reading Guide

This guide covers visual EPUB reading with navigation, customization, and content interaction.

## Setting Up the Reader

### Basic Reader Screen

```dart
class ReaderScreen extends StatefulWidget {
  final String publicationPath;

  const ReaderScreen({required this.publicationPath, super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _flureadium = Flureadium();
  Publication? _publication;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _openPublication();
  }

  Future<void> _openPublication() async {
    try {
      final pub = await _flureadium.openPublication(widget.publicationPath);
      setState(() {
        _publication = pub;
        _isLoading = false;
      });
    } on ReadiumException catch (e) {
      setState(() => _isLoading = false);
      _showError(e.message);
    }
  }

  @override
  void dispose() {
    _flureadium.closePublication();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_publication == null) {
      return Scaffold(
        body: Center(child: Text('Failed to load')),
      );
    }

    return Scaffold(
      body: ReadiumReaderWidget(
        publication: _publication!,
        onTap: (_) => _toggleControls(),
        onLocatorChanged: (locator) => _saveProgress(locator),
      ),
    );
  }
}
```

## Page Navigation

### Basic Navigation

```dart
// Navigate to previous page
await flureadium.goLeft();

// Navigate to next page
await flureadium.goRight();
```

### Swipe Gestures

Swiping to turn pages is not a widget you build — a gesture layer stacked over the
platform view is not the supported path for it. What the flag does depends on the
platform, and for EPUB on Android it does less than its name suggests:

```dart
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(enableSwipeNavigation: true),
);
```

- **iOS, EPUB**: the flag adds a swipe, it does not remove one. On, the plugin's
  own recognizers page from a swipe anywhere in the reader. Off, Readium's
  `PaginationView` — a paging `UIScrollView` the plugin never disables — still
  pages on a horizontal drag. So `enableSwipeNavigation: false` does not stop
  iOS EPUB swiping either.
- **Android, EPUB**: a paginated EPUB is paged by Readium's own internal
  `R2WebView`, which has no toggle in Readium Kotlin 3.1.2. A horizontal drag turns
  the page whether this flag is on or off. What the flag controls is narrow: whether
  a fling starting inside an edge strip the edge-tap gate already claimed pages
  through the plugin's overlay. Do not reach for it to switch EPUB swiping off — that
  is not available on Android today.
- **Android, PDF**: the flag works as written. It reaches the pdfium view's own
  `enableSwipe`, so drag paging stops while taps and zoom keep working.

An EPUB in scroll mode leaves swiping to the WebView, which scrolls.

### Tap Zones

You do not build them any more. One `onTap` reports where the reader was
tapped, and edge paging belongs to the native overlay, so nothing has to sit
between the user and the reader to catch a tap.

```dart
ReadiumReaderWidget(
  publication: pub,
  onTap: (position) {
    // One callback, one decision: show the chrome or hide it.
    setState(() => _showControls = !_showControls);
  },
)
```

Tapping the left and right edges to turn pages is configuration, not a widget:

```dart
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(
    enableEdgeTapNavigation: true,
    edgeTapAreaPoints: 60, // per side, clamped to 44-120
  ),
);
```

`position` is in logical pixels from the top-left of the reader. What a region
of the page means is yours to decide; the plugin only says where the tap
landed.

**A tap on a link never reaches `onTap`.** Readium checks whether the pointer
landed on an interactive element — a hyperlink, a footnote — follows it, and
reports no tap, so what arrives at `onTap` is a tap nothing else claimed. That
is what makes a single tap safe to toggle chrome with: you cannot swallow a
link by accident. The filter is WebView-only. PDF and CBZ have no equivalent,
so a tap on a PDF link annotation is reported as a content tap.

`onTap` also stays quiet in the edge strips while the overlay is claiming them.
[The `onTap` reference](../api-reference/reader-widget.md#ontap) has the
per-platform rule.

## Chapter Navigation

### Skip to Next/Previous Chapter

```dart
// Skip to next chapter
await flureadium.skipToNext();

// Skip to previous chapter
await flureadium.skipToPrevious();
```

For EPUB3 books with a hierarchical `toc.xhtml` — where chapters are nested under parts or sections — skip navigation moves to the next (or previous) chapter at any depth. It won't skip past a group of nested children to jump to the next top-level entry. Pages absent from the TOC (a cover, an interstitial) also work: the widget scans the reading order to find the nearest TOC entry on either side.

An entry the book points at but does not ship — a nav-document link to a file that is not in the spine and not among the resources — is passed over rather than aimed at, and the skip lands on the next entry the reader can reach. Before 0.19.0 such a tap did nothing and said nothing. Hierarchical contents are unaffected: a part or section heading is a document of its own, so it resolves and stays in the list.

### Navigate to Table of Contents Entry

```dart
// Get TOC entries
final toc = publication.tableOfContents;

// Navigate to a specific chapter
final chapter = toc[2];
await flureadium.goByLink(chapter, publication);
```

For EPUB3 publications with a hierarchical TOC, `tableOfContents` preserves the nesting. Use `flattenToc` to get every entry in reading order across all nesting levels:

```dart
import 'package:flureadium/flureadium.dart';

final chapters = flattenToc(publication.tableOfContents);
// [Part I, Chapter 1, Chapter 2, Part II, Section 1, Chapter 3, ...]

// Navigate to chapter 3 (index 5 in a typical structure)
await flureadium.goByLink(chapters[5], publication);
```

A chapter picker or a skip control should use `navigableToc(publication)` instead: it drops the entries whose tap cannot go anywhere, because they resolve to no locator.

### Building a Table of Contents

```dart
void showTableOfContents() {
  showModalBottomSheet(
    context: context,
    builder: (_) => TocView(
      toc: publication.tableOfContents,
      onTap: (link) {
        Navigator.pop(context);
        flureadium.goByLink(link, publication);
      },
    ),
  );
}

class TocView extends StatelessWidget {
  final List<Link> toc;
  final Function(Link) onTap;

  const TocView({required this.toc, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: toc.length,
      itemBuilder: (_, index) => _buildTocItem(toc[index], 0),
    );
  }

  Widget _buildTocItem(Link link, int depth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: 16.0 + (depth * 16.0)),
          title: Text(link.title ?? 'Untitled'),
          onTap: () => onTap(link),
        ),
        ...link.children.map((child) => _buildTocItem(child, depth + 1)),
      ],
    );
  }
}
```

For a flat chapter picker (useful for a progress slider or "jump to chapter N" feature), use `flattenToc` instead of iterating the raw list:

```dart
final chapters = flattenToc(publication.tableOfContents);

showModalBottomSheet(
  context: context,
  builder: (_) => ListView.builder(
    itemCount: chapters.length,
    itemBuilder: (_, i) => ListTile(
      title: Text(chapters[i].title ?? 'Chapter ${i + 1}'),
      onTap: () {
        Navigator.pop(context);
        flureadium.goByLink(chapters[i], publication);
      },
    ),
  ),
);
```

Use `navigableToc(publication)` here rather than `flattenToc` if the picker must never offer an entry that cannot be opened.

## Physical Page Navigation

If the publication has a page list (mapping to printed page numbers):

```dart
// Navigate to physical page 42
await flureadium.toPhysicalPageIndex('42', publication);
```

### Page Number Input Dialog

```dart
void showGoToPageDialog() {
  final controller = TextEditingController();

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Go to Page'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: 'Page Number'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await flureadium.toPhysicalPageIndex(
                controller.text,
                publication,
              );
            } on ReadiumException {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Page not found')),
              );
            }
          },
          child: Text('Go'),
        ),
      ],
    ),
  );
}
```

## Scroll Mode Swipe Navigation

In scroll mode (`verticalScroll: true`), horizontal swipes between spine items are
handled natively by WKWebView. No gesture configuration is needed.

### Position Restoration on Swipe-Back

When the user swipes back to a previously visited spine item, flureadium automatically
restores the last scroll position within that item. This is in-memory only — history
is cleared when the app is relaunched.

**How it works:**
- Each time the reader leaves a spine item, its last position is stored in memory.
- When a swipe-back is detected (new spine index < old spine index), the stored
  position is restored via `goToLocator`.
- Explicit navigation (TOC tap, `skipToPrevious`) clears the stored position for the
  target spine item so restoration does not override the intentional jump.
- `onLocatorChanged` fires after restoration — persistent position saving always
  reflects the final restored position.

**Known behaviour:**
- On swipe-back, there is a brief double save: the navigator first lands at position 0
  of the previous item (~50ms) before restoration fires. The final saved position is
  always correct.
- History is session-only and is not persisted across app launches.
- Forward swipes always land at the start of the next spine item (unchanged).

---

## Position Tracking

### Listen for Position Changes

```dart
@override
void initState() {
  super.initState();

  flureadium.onTextLocatorChanged.listen((locator) {
    setState(() {
      _currentProgress = locator.locations?.totalProgression ?? 0;
      _currentChapter = locator.title;
    });
  });
}
```

### Progress Bar

```dart
Widget buildProgressBar() {
  return StreamBuilder<Locator>(
    stream: flureadium.onTextLocatorChanged,
    builder: (context, snapshot) {
      final progress = snapshot.data?.locations?.totalProgression ?? 0;
      return LinearProgressIndicator(value: progress);
    },
  );
}
```

### Current Position Display

```dart
Widget buildPositionInfo(Locator locator) {
  final progress = locator.locations?.totalProgression ?? 0;
  final chapter = locator.title ?? 'Unknown Chapter';

  return Column(
    children: [
      Text('${(progress * 100).toStringAsFixed(1)}% complete'),
      Text('Current: $chapter'),
    ],
  );
}
```

## Restoring Position

### Save Position on Change

```dart
ReadiumReaderWidget(
  publication: publication,
  onLocatorChanged: (locator) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'position_${publication.identifier}',
      locator.json,
    );
  },
)
```

### Restore on Open

```dart
Future<void> _openPublication() async {
  final pub = await _flureadium.openPublication(path);

  // Restore position
  final prefs = await SharedPreferences.getInstance();
  final savedJson = prefs.getString('position_${pub.identifier}');
  Locator? savedLocator;
  if (savedJson != null) {
    savedLocator = Locator.fromJsonString(savedJson);
  }

  setState(() {
    _publication = pub;
    _initialLocator = savedLocator;
  });
}

// Use in widget
ReadiumReaderWidget(
  publication: _publication!,
  initialLocator: _initialLocator,
)
```

### Switching Publications

When `openPublication()` is called while another publication is active, the Android implementation automatically releases all active navigators (EPUB, audiobook, TTS, PDF) before opening the new publication. This prevents resource contention — particularly with ExoPlayer audio sessions, which may fail to initialize if a previous session hasn't fully closed.

You don't need to call `closePublication()` before `openPublication()` — cleanup is handled internally. However, calling `closePublication()` explicitly in your widget's `dispose()` remains good practice to free resources promptly.

## Visual Customization

### Setting Preferences

```dart
await flureadium.setEPUBPreferences(EPUBPreferences(
  fontFamily: 'Georgia',
  fontSize: 120,  // 1.2em
  fontWeight: 400,
  verticalScroll: false,
  backgroundColor: Color(0xFFFFFFFF),
  textColor: Color(0xFF000000),
  pageMargins: 0.1,
));
```

### Theme Presets

```dart
final lightTheme = EPUBPreferences(
  fontFamily: 'Georgia',
  fontSize: 100,
  fontWeight: 400,
  verticalScroll: false,
  backgroundColor: Color(0xFFFFFFFF),
  textColor: Color(0xFF000000),
);

final sepiaTheme = EPUBPreferences(
  fontFamily: 'Palatino',
  fontSize: 100,
  fontWeight: 400,
  verticalScroll: false,
  backgroundColor: Color(0xFFF5E6D3),
  textColor: Color(0xFF5C4033),
);

final darkTheme = EPUBPreferences(
  fontFamily: 'Helvetica',
  fontSize: 100,
  fontWeight: 400,
  verticalScroll: false,
  backgroundColor: Color(0xFF1A1A1A),
  textColor: Color(0xFFE0E0E0),
);
```

### Settings UI

```dart
class ReaderSettings extends StatelessWidget {
  final EPUBPreferences preferences;
  final Function(EPUBPreferences) onChanged;

  const ReaderSettings({
    required this.preferences,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Font size slider
        Slider(
          min: 50,
          max: 200,
          value: preferences.fontSize.toDouble(),
          onChanged: (value) {
            final newPrefs = EPUBPreferences(
              fontFamily: preferences.fontFamily,
              fontSize: value.round(),
              fontWeight: preferences.fontWeight,
              verticalScroll: preferences.verticalScroll,
              backgroundColor: preferences.backgroundColor,
              textColor: preferences.textColor,
            );
            onChanged(newPrefs);
          },
        ),

        // Theme buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _themeButton('Light', Colors.white, Colors.black),
            _themeButton('Sepia', Color(0xFFF5E6D3), Color(0xFF5C4033)),
            _themeButton('Dark', Color(0xFF1A1A1A), Colors.white),
          ],
        ),
      ],
    );
  }
}
```

## Handling External Links

```dart
ReadiumReaderWidget(
  publication: publication,
  onExternalLinkActivated: (url) async {
    // Confirm before opening
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Open External Link?'),
        content: Text(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Open'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    }
  },
)
```

`onExternalLinkActivated` is the handoff point from the native reader back into
your Flutter app. Treat it as policy, not just telemetry: your app decides
whether to block the URL, show a confirmation step, or hand it to the OS.

For restricted-content or parental-controls scenarios, prefer
`LaunchMode.externalApplication` so the OS browser owns the transition instead
of an in-app browser surface. That keeps reader-originated links aligned with
the same external launch policy you use elsewhere in the app.

## Complete Example

```dart
class FullReaderScreen extends StatefulWidget {
  final String publicationPath;

  const FullReaderScreen({required this.publicationPath, super.key});

  @override
  State<FullReaderScreen> createState() => _FullReaderScreenState();
}

class _FullReaderScreenState extends State<FullReaderScreen> {
  final _flureadium = Flureadium();
  Publication? _publication;
  Locator? _initialLocator;
  bool _showControls = true;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Set default preferences
    _flureadium.setDefaultPreferences(EPUBPreferences(
      fontFamily: 'Georgia',
      fontSize: 100,
      fontWeight: 400,
      verticalScroll: false,
      backgroundColor: Color(0xFFFFFFFF),
      textColor: Color(0xFF000000),
    ));

    // Open publication
    final pub = await _flureadium.openPublication(widget.publicationPath);

    // Load saved position
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('pos_${pub.identifier}');
    if (savedJson != null) {
      _initialLocator = Locator.fromJsonString(savedJson);
    }

    // Listen for progress
    _flureadium.onTextLocatorChanged.listen((loc) {
      setState(() => _progress = loc.locations?.totalProgression ?? 0);
    });

    setState(() => _publication = pub);
  }

  @override
  void dispose() {
    _flureadium.closePublication();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_publication == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Reader
          ReadiumReaderWidget(
            publication: _publication!,
            initialLocator: _initialLocator,
            onTap: (_) => setState(() => _showControls = !_showControls),
            onLocatorChanged: _saveProgress,
          ),

          // Top bar
          if (_showControls)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AppBar(
                backgroundColor: Colors.black54,
                title: Text(_publication!.metadata.title ?? 'Reader'),
                actions: [
                  IconButton(
                    icon: Icon(Icons.list),
                    onPressed: _showToc,
                  ),
                  IconButton(
                    icon: Icon(Icons.settings),
                    onPressed: _showSettings,
                  ),
                ],
              ),
            ),

          // Bottom bar
          if (_showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress
                    LinearProgressIndicator(value: _progress),
                    SizedBox(height: 8),
                    Text(
                      '${(_progress * 100).toStringAsFixed(1)}%',
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 8),
                    // Navigation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(Icons.skip_previous, color: Colors.white),
                          onPressed: () => _flureadium.skipToPrevious(),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_left, color: Colors.white),
                          onPressed: () => _flureadium.goLeft(),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right, color: Colors.white),
                          onPressed: () => _flureadium.goRight(),
                        ),
                        IconButton(
                          icon: Icon(Icons.skip_next, color: Colors.white),
                          onPressed: () => _flureadium.skipToNext(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveProgress(Locator locator) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pos_${_publication!.identifier}', locator.json);
  }

  void _showToc() {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView.builder(
        itemCount: _publication!.tableOfContents.length,
        itemBuilder: (_, i) {
          final link = _publication!.tableOfContents[i];
          return ListTile(
            title: Text(link.title ?? 'Chapter ${i + 1}'),
            onTap: () {
              Navigator.pop(context);
              _flureadium.goByLink(link, _publication!);
            },
          );
        },
      ),
    );
  }

  void _showSettings() {
    // Show settings bottom sheet
  }
}
```

## See Also

- [Quick Start](../getting-started/quick-start.md) - Minimal reader setup
- [Preferences Guide](preferences.md) - Detailed customization
- [Saving Progress Guide](saving-progress.md) - Position persistence
- [ReaderWidget Reference](../api-reference/reader-widget.md) - Widget API
