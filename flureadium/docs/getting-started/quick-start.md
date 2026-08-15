# Quick Start

Get a working EPUB reader in your Flutter app in 5 minutes.

## Prerequisites

Complete the [Installation](installation.md) guide first.

## Minimal Example

### 1. Create the Reader Screen

```dart
import 'package:flutter/material.dart';
import 'package:flureadium/flureadium.dart';

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
  String? _error;

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
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
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

    if (_error != null) {
      return Scaffold(
        body: Center(child: Text('Error: $_error')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_publication!.metadata.title ?? 'Reader'),
      ),
      body: ReadiumReaderWidget(
        publication: _publication!,
        onTap: (position) {
          // Handle tap (e.g., show/hide controls)
        },
        onLocatorChanged: (locator) {
          // Save reading progress
          print('Progress: ${locator.locations?.totalProgression}');
        },
      ),
    );
  }
}
```

### 2. Navigate to the Reader

```dart
// From your book selection screen
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ReaderScreen(
      publicationPath: 'file:///path/to/your/book.epub',
    ),
  ),
);
```

### 3. Add Navigation Controls

Extend the reader with page navigation:

```dart
class _ReaderScreenState extends State<ReaderScreen> {
  // ... existing code ...

  @override
  Widget build(BuildContext context) {
    // ... loading/error handling ...

    return Scaffold(
      appBar: AppBar(
        title: Text(_publication!.metadata.title ?? 'Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _showTableOfContents,
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! < 0) {
            _flureadium.goRight();  // Swipe left -> next page
          } else {
            _flureadium.goLeft();   // Swipe right -> previous page
          }
        },
        child: ReadiumReaderWidget(
          publication: _publication!,
          onLocatorChanged: (locator) {
            print('Progress: ${locator.locations?.totalProgression}');
          },
        ),
      ),
    );
  }

  void _showTableOfContents() {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView.builder(
        itemCount: _publication!.tableOfContents.length,
        itemBuilder: (_, index) {
          final link = _publication!.tableOfContents[index];
          return ListTile(
            title: Text(link.title ?? 'Chapter ${index + 1}'),
            onTap: () {
              Navigator.pop(context);
              _flureadium.goByLink(link, _publication!);
            },
          );
        },
      ),
    );
  }
}
```

## Customize Appearance

Set default preferences before opening the publication:

```dart
@override
void initState() {
  super.initState();

  // Set default visual preferences
  _flureadium.setDefaultPreferences(EPUBPreferences(
    fontFamily: 'Georgia',
    fontSize: 100,  // 100% = normal size
    fontWeight: 400,
    verticalScroll: false,  // Paginated mode
    backgroundColor: const Color(0xFFFFFFF8),  // Off-white
    textColor: const Color(0xFF333333),  // Dark gray
  ));

  _openPublication();
}
```

## Listen to Position Changes

Track reading progress for bookmarks or saving position:

```dart
@override
void initState() {
  super.initState();

  // Listen to position stream
  _flureadium.onTextLocatorChanged.listen((locator) {
    final progress = locator.locations?.totalProgression ?? 0;
    print('Reading progress: ${(progress * 100).toStringAsFixed(1)}%');

    // Save to persistent storage
    _saveProgress(locator);
  });

  _openPublication();
}

Future<void> _saveProgress(Locator locator) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('lastPosition', locator.json);
}
```

## Restore Reading Position

Load saved position when opening:

```dart
Future<void> _openPublication() async {
  try {
    final pub = await _flureadium.openPublication(widget.publicationPath);

    // Try to restore saved position
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('lastPosition');
    Locator? savedLocator;
    if (savedJson != null) {
      savedLocator = Locator.fromJsonString(savedJson);
    }

    setState(() {
      _publication = pub;
      _initialLocator = savedLocator;
      _isLoading = false;
    });
  } on ReadiumException catch (e) {
    // ... error handling
  }
}

// Use in widget
ReadiumReaderWidget(
  publication: _publication!,
  initialLocator: _initialLocator,  // Start from saved position
  onLocatorChanged: (locator) => _saveProgress(locator),
)
```

## Complete Example

See the [example app](../../example/) for a minimal single-file implementation covering:
- EPUB, audiobook, and remote WebPub opening
- TTS and audio playback
- Navigation and chapter skipping
- EPUB preferences and highlighting

## Next Steps

- [Concepts](concepts.md) - Understand the data models
- [EPUB Reading Guide](../guides/epub-reading.md) - Advanced navigation
- [Text-to-Speech](../guides/text-to-speech.md) - Add TTS support
- [Saving Progress](../guides/saving-progress.md) - Persist reading position
