# Flureadium Error Handling Guide

## Overview

Flureadium uses a structured error handling approach with specific exception types and standardized logging.

---

## Exception Hierarchy

### Base Exception: `ReadiumException`

```dart
class ReadiumException implements Exception {
  const ReadiumException(this.message, {this.type});
  final String message;
  final Object? type;
}
```

**Factory Methods:**
- `fromPlatformException(PlatformException)` - Converts Flutter platform exceptions
- `fromError(Object?)` - Generic error converter

---

### Specialized Exceptions

#### 1. `OpeningReadiumException`
Used when opening/loading publications fails.

```dart
enum OpeningReadiumExceptionType {
  formatNotSupported,  // Publication format not supported
  readingError,        // Error reading file/stream
  notFound,            // Resource not found
  forbidden,           // Access forbidden (DRM, permissions)
  unavailable,         // Resource temporarily unavailable
  incorrectCredentials,// Authentication failed
  unknown,             // Unknown error
}
```

**Usage:**
```dart
try {
  await readium.openPublication(asset);
} on OpeningReadiumException catch (e) {
  switch (e.type) {
    case OpeningReadiumExceptionType.formatNotSupported:
      // Handle unsupported format
    case OpeningReadiumExceptionType.forbidden:
      // Handle DRM or permission issues
    default:
      // Handle other cases
  }
}
```

#### 2. `PublicationNotSetReadiumException`
Thrown when attempting operations before publication is loaded.

```dart
if (publication == null) {
  throw PublicationNotSetReadiumException('Cannot navigate without publication');
}
```

#### 3. `OfflineReadiumException`
Thrown when network-required operations fail due to offline state.

```dart
if (!await connectivity.isOnline) {
  throw OfflineReadiumException('Cannot download while offline');
}
```

---

## Error Objects: `ReadiumError`

For non-fatal errors that need detailed logging:

```dart
class ReadiumError implements Error {
  ReadiumError(
    this.message,
    {this.code, this.data, StackTrace? stackTrace}
  );

  final String message;
  final String? code;
  final Object? data;
  final StackTrace? stackTrace;

  Map<String, dynamic> toJson();
  factory ReadiumError.fromJson(Map<String, dynamic> map);
}
```

**Usage:**
```dart
try {
  // Some operation
} catch (e, stackTrace) {
  final error = ReadiumError(
    'Failed to parse locator',
    code: 'PARSE_ERROR',
    data: {'locator': locatorJson},
    stackTrace: stackTrace,
  );
  R2Log.e(error, data: additionalContext);
}
```

---

## Error Event Stream: `onErrorEvent`

Not every failure is thrown from the call you made. Playback failures happen
asynchronously, after `play()` has already returned, so they arrive on a stream
rather than as an exception. `Flureadium.onErrorEvent` delivers a `ReadiumError`
(`{message, code?, data?}`) for these out-of-band errors.

```dart
final sub = flureadium.onErrorEvent.listen((error) {
  R2Log.e(error);
  // Surface it — a streamed audio track that fails to load otherwise stalls
  // silently at 0:00 with nothing to show the user.
  showErrorToast(error.message);
});
// Cancel in dispose().
```

### Audiobook streaming failures

When a streamed audio resource fails to load (unreachable host, 404, codec
rejection), the native audio path forwards the failure onto this stream:

- **Android** — `ReadiumReader.onTimebasedPlaybackFailure` forwards the failure
  onto the stream with `code: "TimebasedError"` and `data` set to the Readium
  error category (e.g. `"unknown"`). This covers both load-time failures (dead
  host, 404) and mid-stream failures.
- **iOS** — the plugin implements the timebased navigator's `encounteredError`
  hook, which forwards Readium's `didFailToLoadResourceAt` plus a best-effort
  NotificationCenter observation of AVFoundation's
  `AVPlayerItemFailedToPlayToEndTime` / `AVPlayerItemNewErrorLogEntry`. Errors
  arrive with the same `code: "TimebasedError"`.

**Known limitation (iOS):** Readium keeps its `AVPlayer` private, so the plugin
can only observe failures through `NotificationCenter`
(`AVPlayerItemFailedToPlayToEndTime`, `AVPlayerItemNewErrorLogEntry`). In
practice these do not fire for every failure — a load-time failure (unreachable
host, where `AVPlayerItem.status` goes straight to `.failed`) is a KVO signal
that posts no notification, and even some mid-stream interruptions are not
reported. **Treat iOS audio-error delivery as best-effort — do not rely on an
error event for a given failure; the player may simply stall at 0:00.** A
deterministic upstream hook is tracked as a follow-up.

Android has no such gap — every timebased failure is forwarded. Coverage:
`ReadiumReaderTimebasedErrorTest` (Android unit) verifies the forwarding, and
the `partial stream failure surfaces an error event` integration test asserts it
end-to-end on Android (skipped on iOS, where delivery is best-effort). The
load-time `unreachable streamed audio` integration test is skipped everywhere —
kept for documentation and manual runs, with the Android forwarding it would
exercise already covered by the unit test.

---

## Logging System: `R2Log`

### Log Levels

```dart
R2Log.d('Debug message');     // Debug (filtered by trace keywords)
R2Log.i('Info message');      // Info
R2Log.w('Warning message');   // Warning
R2Log.e(error, data: data);   // Error (accepts ReadiumError or any Object)
```

### Debug Trace Filtering

Debug logs are filtered by keywords defined in `_trace` list:

```dart
// In r2_log.dart
const _trace = <String>[
  'Flureadium',      // Class/method names containing this will be logged
  'Publication',     // Logs publication-related debug messages
  'Navigation',      // Logs navigation debug messages
  'Locator',         // Logs locator operations
  'Preferences',     // Logs preference changes
];
```

**How it works:**
1. `R2Log.d()` automatically captures call stack
2. Checks if log message or stack trace contains any trace keyword (case-insensitive)
3. Only logs if match found (to reduce noise in production builds)

### Specialized Logging

#### Map Diff Logging
Useful for debugging JSON transformation issues:

```dart
R2Log.logMapDiff(
  leftJson,
  rightJson,
  prefix: 'Publication transformation:',
);
```

**Output:**
```
Publication transformation:
  metadata:
    title: "Old Title" --> "New Title"
  + newField: "value"
  - removedField: "value"
```

---

## Error Handling Best Practices

### 1. Use Specific Exceptions

❌ **Bad:**
```dart
throw Exception('File not found');
```

✅ **Good:**
```dart
throw OpeningReadiumException(
  'Publication file not found: $path',
  type: OpeningReadiumExceptionType.notFound,
);
```

### 2. Include Context in Errors

❌ **Bad:**
```dart
catch (e) {
  R2Log.e(e);
}
```

✅ **Good:**
```dart
catch (e, stackTrace) {
  R2Log.e(
    ReadiumError(
      'Failed to load publication',
      code: 'LOAD_ERROR',
      data: {'path': path, 'originalError': e.toString()},
      stackTrace: stackTrace,
    ),
  );
}
```

### 3. Handle Platform Exceptions

```dart
try {
  final result = await methodChannel.invokeMethod('openPublication', args);
} on PlatformException catch (e) {
  throw ReadiumException.fromPlatformException(e);
}
```

### 4. Graceful Degradation

```dart
try {
  final cover = await publication.cover();
  return Image.memory(cover);
} on ReadiumException catch (e) {
  R2Log.w('Could not load cover: ${e.message}');
  return PlaceholderImage();
}
```

### 5. Handle Audio/TTS Enable Failures

`audioEnable()` can throw a `PlatformException` when the native audio navigator
factory fails to initialize (e.g., missing codecs, hardware audio session
conflicts). Wrap the call in a try/catch and surface the error to the user:

```dart
try {
  await flureadium.audioEnable();
  await flureadium.play(null);
} catch (e) {
  debugPrint('audioEnable error: $e');
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Audio playback unavailable: $e')),
    );
  }
}
```

Without this guard, a single `PlatformException` from `audioEnable()` can
corrupt the Flutter integration test harness (`_pendingFrame` state) and cause
all subsequent tests to fail in cascade.

---

## Error Categories (Recommended Extension)

For systematic error handling, consider categorizing errors:

```dart
enum ErrorCategory {
  publication,   // Publication loading, parsing
  navigation,    // Page navigation, TOC
  playback,      // TTS, audio playback
  network,       // Downloads, streaming
  platform,      // Platform channel errors
  storage,       // File I/O, database
  preferences,   // Settings, configuration
}
```

**Future Enhancement:**
```dart
class CategorizedReadiumError extends ReadiumError {
  CategorizedReadiumError(
    super.message, {
    required this.category,
    super.code,
    super.data,
    super.stackTrace,
  });

  final ErrorCategory category;
}
```

---

## Testing Error Handling

### Testing Exceptions

```dart
test('throws OpeningReadiumException for invalid format', () {
  expect(
    () => readium.openPublication(invalidFile),
    throwsA(isA<OpeningReadiumException>()
      .having(
        (e) => e.type,
        'type',
        OpeningReadiumExceptionType.formatNotSupported,
      )
    ),
  );
});
```

### Testing Error Logging

```dart
test('logs error with context', () {
  final error = ReadiumError(
    'Test error',
    code: 'TEST_ERROR',
    data: {'key': 'value'},
  );

  R2Log.e(error);

  // Verify error was logged (requires mock/spy)
});
```

---

## Migration Path (If Needed)

If migrating from generic exceptions to structured errors:

1. **Identify error sources:**
   ```bash
   # Find all throws
   grep -r "throw " lib/ --include="*.dart"
   ```

2. **Replace with specific exceptions:**
   ```dart
   // Before
   throw Exception('Failed');

   // After
   throw ReadiumException('Failed', type: ErrorType.specific);
   ```

3. **Add error context:**
   ```dart
   // Before
   throw e;

   // After
   throw ReadiumError(
     'Operation failed',
     code: 'OP_FAILED',
     data: {'context': details},
   );
   ```

4. **Update error handlers:**
   ```dart
   // Before
   } catch (e) {
     print('Error: $e');
   }

   // After
   } on ReadiumException catch (e) {
     R2Log.e(e, data: contextInfo);
     // Handle specific exception type
   }
   ```

---

## Platform Channel Error Mapping

### Flutter → Native Error Codes

```dart
extension PlatformExceptionCodeExtension on PlatformException {
  int? get intCode => code.isEmpty ? null : int.tryParse(code, radix: 10);
}
```

### Native → Flutter Exception Mapping

Native code throws platform exceptions with string codes that map to `OpeningReadiumExceptionType`:

| Native Code | Exception Type | Description |
|-------------|----------------|-------------|
| `formatNotSupported` | formatNotSupported | Unrecognized file format |
| `readingError` | readingError | I/O error reading file |
| `notFound` | notFound | File/resource not found |
| `forbidden` | forbidden | DRM or permission denied |
| `unavailable` | unavailable | Service unavailable |
| `incorrectCredentials` | incorrectCredentials | Auth failed |
| (other) | unknown | Unmapped error |

The `details` field in platform channel errors is always `String?` or `null` — never a complex object. On Android, `publicationError()` converts `error.cause` to a string via `toString()` before passing it to `MethodChannel.Result.error()`. On iOS, `ReadiumError.toFlutterError()` uses `.localizedDescription` for the same purpose. This keeps the value compatible with Flutter's `StandardMessageCodec`, which only accepts primitives, maps, lists, and null.

---

## Summary

✅ **Current State:**
- Well-structured exception hierarchy
- ReadiumError for detailed error reporting
- R2Log with trace filtering
- Platform exception handling

📋 **Recommended Enhancements:**
1. Enable R2Log trace filtering with meaningful keywords ✅ (see below)
2. Add error categories for systematic handling
3. Create error handling documentation (this file) ✅
4. Add more context to existing error throws

🔧 **Configuration:**
Edit `lib/src/utils/r2_log.dart` trace filter:
```dart
const _trace = <String>[
  'Flureadium',
  'Publication',
  'Navigation',
  'Locator',
  'Preferences',
];
```

---

**Last Updated**: 2026-03-21
**Related Files:**
- `lib/src/exceptions/readium_exceptions.dart`
- `lib/src/utils/r2_log.dart`
