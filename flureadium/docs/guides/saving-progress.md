# Saving Progress Guide

This guide covers persisting reading position across app sessions.

## Basic Position Saving

### Listen for Position Changes

```dart
flureadium.onTextLocatorChanged.listen((locator) async {
  await saveProgress(locator);
});
```

### Save to SharedPreferences

```dart
Future<void> saveProgress(Locator locator) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'reading_position_${publication.identifier}',
    locator.json,
  );
}
```

### Restore on Open

```dart
Future<Locator?> loadProgress(String bookId) async {
  final prefs = await SharedPreferences.getInstance();
  final json = prefs.getString('reading_position_$bookId');
  if (json == null) return null;
  return Locator.fromJsonString(json);
}
```

## Debouncing Position Updates

Position updates can be frequent. Debounce to reduce storage writes. `rxdart`
is not a flureadium dependency — add it to your own `pubspec.yaml`:

```dart
import 'package:rxdart/rxdart.dart';

@override
void initState() {
  super.initState();

  flureadium.onTextLocatorChanged
      .debounceTime(Duration(seconds: 2))  // Wait 2 seconds after last change
      .listen((locator) async {
        await saveProgress(locator);
      });
}
```

## Using ReaderWidget Callback

```dart
ReadiumReaderWidget(
  publication: publication,
  initialLocator: savedLocator,
  onLocatorChanged: (locator) {
    // Called on every position change
    _debounceSave(locator);
  },
)
```

### Platform Notes

- iOS progress updates are emitted from the navigator location-change callback.
- Android EPUB progress updates are normalized to the visual-current-location callback,
  and pagination callback noise during the initial restore window is ignored.
- On Android, explicit `go()` calls clear stale deferred startup scroll targets before
  applying the requested locator, so restore follows a single authoritative path.

## Complete Progress Manager

```dart
class ReadingProgressManager {
  final _saveController = StreamController<Locator>();
  StreamSubscription? _subscription;

  ReadingProgressManager() {
    _subscription = _saveController.stream
        .debounceTime(Duration(seconds: 2))
        .listen(_saveProgress);
  }

  void updatePosition(Locator locator) {
    _saveController.add(locator);
  }

  Future<void> _saveProgress(Locator locator) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'position_${locator.href.hashCode}',
      locator.json,
    );
    print('Saved position: ${locator.locations?.totalProgression}');
  }

  static Future<Locator?> loadProgress(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('position_$bookId');
    if (json == null) return null;
    return Locator.fromJsonString(json);
  }

  void dispose() {
    _subscription?.cancel();
    _saveController.close();
  }
}
```

## Database Storage

For more complex apps, use a database:

### SQLite Schema

```dart
class ReadingProgressDatabase {
  late Database _db;

  Future<void> initialize() async {
    _db = await openDatabase(
      'reading_progress.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE reading_progress (
            book_id TEXT PRIMARY KEY,
            locator_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> saveProgress(String bookId, Locator locator) async {
    await _db.insert(
      'reading_progress',
      {
        'book_id': bookId,
        'locator_json': locator.json,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Locator?> loadProgress(String bookId) async {
    final results = await _db.query(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return Locator.fromJsonString(results.first['locator_json'] as String);
  }

  Future<List<RecentBook>> getRecentBooks({int limit = 10}) async {
    final results = await _db.query(
      'reading_progress',
      orderBy: 'updated_at DESC',
      limit: limit,
    );

    return results.map((r) => RecentBook(
      bookId: r['book_id'] as String,
      locator: Locator.fromJsonString(r['locator_json'] as String)!,
      lastRead: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    )).toList();
  }
}

class RecentBook {
  final String bookId;
  final Locator locator;
  final DateTime lastRead;

  RecentBook({
    required this.bookId,
    required this.locator,
    required this.lastRead,
  });
}
```

## Multiple Reading Positions

Allow users to have multiple saved positions per book:

```dart
class BookmarkPosition {
  final String id;
  final String bookId;
  final Locator locator;
  final String? label;
  final DateTime created;

  BookmarkPosition({
    required this.id,
    required this.bookId,
    required this.locator,
    this.label,
    required this.created,
  });
}

class PositionManager {
  Future<void> saveNamedPosition(
    String bookId,
    Locator locator,
    String label,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final positions = await _loadPositions(bookId);

    positions.add(BookmarkPosition(
      id: uuid.v4(),
      bookId: bookId,
      locator: locator,
      label: label,
      created: DateTime.now(),
    ));

    await prefs.setString(
      'positions_$bookId',
      jsonEncode(positions.map(_toJson).toList()),
    );
  }

  Future<List<BookmarkPosition>> getPositions(String bookId) async {
    return _loadPositions(bookId);
  }

  Future<void> deletePosition(String bookId, String positionId) async {
    final prefs = await SharedPreferences.getInstance();
    final positions = await _loadPositions(bookId);
    positions.removeWhere((p) => p.id == positionId);
    await prefs.setString(
      'positions_$bookId',
      jsonEncode(positions.map(_toJson).toList()),
    );
  }
}
```

## Sync with Cloud

### Cloud Sync Interface

```dart
abstract class CloudProgressSync {
  Future<void> uploadProgress(String bookId, Locator locator);
  Future<Locator?> downloadProgress(String bookId);
  Future<void> syncAll();
}

class FirebaseProgressSync implements CloudProgressSync {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _userId;

  FirebaseProgressSync(this._userId);

  @override
  Future<void> uploadProgress(String bookId, Locator locator) async {
    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('reading_progress')
        .doc(bookId)
        .set({
          'locator': locator.toJson(),
          'updated_at': FieldValue.serverTimestamp(),
        });
  }

  @override
  Future<Locator?> downloadProgress(String bookId) async {
    final doc = await _firestore
        .collection('users')
        .doc(_userId)
        .collection('reading_progress')
        .doc(bookId)
        .get();

    if (!doc.exists) return null;
    return Locator.fromJson(doc.data()!['locator']);
  }

  @override
  Future<void> syncAll() async {
    // Implement bidirectional sync
  }
}
```

### Conflict Resolution

```dart
class SyncManager {
  final CloudProgressSync _cloud;
  final ReadingProgressDatabase _local;

  SyncManager(this._cloud, this._local);

  Future<Locator?> resolveProgress(String bookId) async {
    final localProgress = await _local.loadProgress(bookId);
    final cloudProgress = await _cloud.downloadProgress(bookId);

    if (localProgress == null) return cloudProgress;
    if (cloudProgress == null) return localProgress;

    // Use the one with higher progress
    final localProg = localProgress.locations?.totalProgression ?? 0;
    final cloudProg = cloudProgress.locations?.totalProgression ?? 0;

    return localProg > cloudProg ? localProgress : cloudProgress;
  }

  Future<void> syncProgress(String bookId, Locator locator) async {
    await _local.saveProgress(bookId, locator);

    // Upload in background
    _cloud.uploadProgress(bookId, locator).catchError((e) {
      print('Failed to sync: $e');
      // Queue for later sync
    });
  }
}
```

## Reading Statistics

Track reading time and progress:

```dart
class ReadingStats {
  final String bookId;
  int totalReadingTimeSeconds = 0;
  DateTime? lastSessionStart;
  double highestProgress = 0;

  ReadingStats(this.bookId);

  void startSession() {
    lastSessionStart = DateTime.now();
  }

  void endSession() {
    if (lastSessionStart != null) {
      totalReadingTimeSeconds +=
          DateTime.now().difference(lastSessionStart!).inSeconds;
      lastSessionStart = null;
    }
  }

  void updateProgress(double progress) {
    if (progress > highestProgress) {
      highestProgress = progress;
    }
  }

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'totalReadingTimeSeconds': totalReadingTimeSeconds,
    'highestProgress': highestProgress,
  };
}

class ReadingStatsTracker {
  final Map<String, ReadingStats> _stats = {};

  void onBookOpened(String bookId) {
    _stats.putIfAbsent(bookId, () => ReadingStats(bookId));
    _stats[bookId]!.startSession();
  }

  void onPositionChanged(String bookId, double progress) {
    _stats[bookId]?.updateProgress(progress);
  }

  void onBookClosed(String bookId) {
    _stats[bookId]?.endSession();
    _saveStats(bookId);
  }

  Future<void> _saveStats(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'stats_$bookId',
      jsonEncode(_stats[bookId]?.toJson()),
    );
  }
}
```

## Complete Example

```dart
class BookReader extends StatefulWidget {
  final String bookPath;
  final String bookId;

  const BookReader({
    required this.bookPath,
    required this.bookId,
    super.key,
  });

  @override
  State<BookReader> createState() => _BookReaderState();
}

class _BookReaderState extends State<BookReader> {
  final _flureadium = Flureadium();
  final _progressManager = ReadingProgressManager();

  Publication? _publication;
  Locator? _initialLocator;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Load saved position
    _initialLocator = await ReadingProgressManager.loadProgress(widget.bookId);

    // Open publication
    final pub = await _flureadium.openPublication(widget.bookPath);

    setState(() {
      _publication = pub;
      _isLoading = false;
    });

    // Set up position tracking
    _flureadium.onTextLocatorChanged.listen((locator) {
      _progressManager.updatePosition(locator);
    });
  }

  @override
  void dispose() {
    _progressManager.dispose();
    _flureadium.closePublication();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_publication!.metadata.title ?? 'Reader'),
      ),
      body: ReadiumReaderWidget(
        publication: _publication!,
        initialLocator: _initialLocator,
        onLocatorChanged: (locator) {
          // Additional immediate handling if needed
        },
      ),
    );
  }
}
```

## Best Practices

1. **Always debounce** - Don't save on every scroll
2. **Use book identifiers** - Not file paths
3. **Handle missing positions** - Start from beginning
4. **Validate locators** - Check href exists in publication
5. **Prefer enriched locators** - Keep `cssSelector`/`domRange` when available for precise restore
6. **Android restore fallback** - Progression-only locators restore with native navigation when selector data is missing
7. **Background sync** - Don't block UI for cloud sync
8. **Handle conflicts** - Prefer higher progress

## Testing Restore Behavior

### Manual Reopen Loop Test

To validate that position restore works correctly without drift, use this test procedure:

```dart
// 1. Open a book and navigate to a specific position
await flureadium.openPublication('test_book.epub');
await flureadium.goToLocator(testLocator);  // e.g., chapter 3, progression 0.317

// 2. Save the position
final savedLocator = flureadium.currentLocator;
await saveProgress(savedLocator);

// 3. Close and reopen the book
await flureadium.closePublication();
final restoredLocator = await loadProgress('test_book_id');
await flureadium.openPublication('test_book.epub', initialLocator: restoredLocator);

// 4. Verify position matches
final currentLocator = flureadium.currentLocator;
assert(currentLocator.href == savedLocator.href);
assert((currentLocator.locations.progression - savedLocator.locations.progression).abs() < 0.01);
```

### Reopen Loop Validation

Test restore stability by repeating the close/reopen cycle:

**Test Procedure:**
1. Open a book
2. Navigate to a specific page (e.g., page 27, progression ~0.317)
3. Close the book
4. Reopen the book with saved position
5. **Expected**: Should restore to the exact same page and progression
6. Repeat steps 3-5 at least 5-10 times
7. **Success criteria**: Position remains stable across all reopens (no drift to different chapters or positions)

**Platform-Specific Validation:**
- **Android**: Check logs for `::goToLocator - stay at <href>, delta=<n>`, which is the line the navigator prints when it decides the position is already correct and skips the scroll
- **iOS**: Position should be set via `initialLocation` parameter during navigator initialization

### Common Issues

**Issue**: Position drifts on Android after close/reopen

**Cause**: JavaScript `scrollToLocations()` recalculates progression from element bounding rect geometry, producing slightly different values than saved progression, then overwrites StateFlow

**Fix**: The Android implementation now skips `scrollToLocations()` when already positioned correctly (within 1% delta)

**Issue**: Position jumps to end of chapter on restore

**Cause**: Late locator emissions after restore window settles due to preference re-rendering or fragment lifecycle changes

**Fix**: Grace period validation (5s) suppresses late jumps that differ significantly from restore target

### Automated Tests

The plugin includes unit tests for restore behavior:

```bash
# Run Android unit tests
cd flureadium/example/android
./gradlew testDebugUnitTest

# Run specific test class
./gradlew testDebugUnitTest --tests "*.EpubNavigatorRestoreTest"
```

**Test Coverage:**
- Progression delta calculation (1% threshold)
- Small drift detection (JavaScript recalculation)
- Large progression differences requiring scroll
- Null progression value handling
- Edge cases (start/end of chapter)
- Locator href equivalence

See: [android/src/test/kotlin/dev/mulev/flureadium/navigators/EpubNavigatorRestoreTest.kt](../../android/src/test/kotlin/dev/mulev/flureadium/navigators/EpubNavigatorRestoreTest.kt)

### Debug Logging

Enable verbose logging to diagnose restore issues:

**Android:**
```bash
adb logcat | grep -E "(EpubNavigator|EpubReaderFragment|ReadiumReaderWidget)"
```

**Key log messages to look for:**
- `::locator - href=... prog=...` - Position the plugin reported to your app
- `::onPageLoaded - href=... pendingScroll=...` - A page loaded, and whether a restore is still queued
- `::onPageLoaded - fragment recreated, resubscribing` - The reader fragment was rebuilt after pause/resume
- `::goToLocator - ...` - What restore decided: go to another resource, stay put, or scroll
- `::scrollToLocations - ...` - The locations sent to the page's JavaScript
- `::restoreState - ...` - The locator and preferences read back from a saved state bundle
- `restore: settled after Xms` - Restore window lifecycle
- `SUPPRESS late jump during grace period!` - Grace period validation

## See Also

- [Locator Reference](../api-reference/locator.md) - Position model
- [Streams and Events](../api-reference/streams-events.md) - Position streams
- [Highlights Guide](highlights-annotations.md) - Saving annotations
- [Troubleshooting](../troubleshooting.md) - Common issues and solutions
