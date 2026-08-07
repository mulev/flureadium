# Streams and Events

Flureadium provides reactive streams for real-time updates from the reader. Subscribe to these streams to track reading progress, playback state, and errors.

## Available Streams

| Stream | Emits | Use Case |
|--------|-------|----------|
| `onTextLocatorChanged` | `Locator` | Reading position tracking |
| `onTimebasedPlayerStateChanged` | `ReadiumTimebasedState` | Audio/TTS playback state |
| `onReaderStatusChanged` | `ReadiumReaderStatus` | Reader lifecycle events |
| `onErrorEvent` | `ReadiumError` | Error handling |

## onTextLocatorChanged

Emits whenever the reading position changes.

**Type:** `Stream<Locator>`

### Usage

```dart
final subscription = flureadium.onTextLocatorChanged.listen((locator) {
  final progress = locator.locations?.totalProgression ?? 0;
  print('Progress: ${(progress * 100).toStringAsFixed(1)}%');
  print('Chapter: ${locator.title}');
  print('Href: ${locator.href}');
});

// Don't forget to cancel when done
@override
void dispose() {
  subscription.cancel();
  super.dispose();
}
```

### Delivery

Nothing is buffered. A page change that happens while no one is subscribed is
dropped, and a locator already delivered is never replayed to a later
subscriber. This is deliberately unlike `onReaderStatusChanged`, which holds
its latest value for a first subscriber: a status describes where the reader
*is*, while a locator describes a page turn that already happened. Replaying
one would move a reader that never went there.

The consequence for a host app: subscribe from
[`ReadiumReaderWidget.onReady`](reader-widget.md), which fires once per
platform view — including after a publication swap — and treat the stream as
silent until the reader reports its first page. Do not carry a locator across
a swap; an href from the publication that just closed does not resolve in the
one replacing it.

### Debouncing

For performance, consider debouncing frequent updates:

```dart
import 'package:rxdart/rxdart.dart';

flureadium.onTextLocatorChanged
    .debounceTime(Duration(milliseconds: 500))
    .listen((locator) {
      // Save position (less frequent)
      saveProgress(locator);
    });
```

### Distinct Values

Filter out duplicate emissions:

```dart
flureadium.onTextLocatorChanged
    .distinct()
    .listen((locator) {
      // Only when position actually changes
    });
```

## onTimebasedPlayerStateChanged

Emits for audio playback (TTS and audiobook) state changes.

**Type:** `Stream<ReadiumTimebasedState>`

### Usage

```dart
flureadium.onTimebasedPlayerStateChanged.listen((state) {
  print('State: ${state.state}');
  print('Current: ${state.currentOffset}');
  print('Duration: ${state.currentDuration}');

  // Update UI
  setState(() {
    _playbackState = state.state;
    _currentPosition = state.currentOffset;
    _totalDuration = state.currentDuration;
  });
});
```

### ReadiumTimebasedState

```dart
class ReadiumTimebasedState {
  TimebasedState state;         // Current playback state
  Duration? currentOffset;      // Current position
  Duration? currentBuffered;    // Buffered position
  Duration? currentDuration;    // Total duration
  Locator? currentLocator;      // Current locator position
  TtsErrorType? ttsErrorType;   // TTS-specific error detail (see below)
}
```

#### ttsErrorType

**Type:** `TtsErrorType?`

Present only when `state == TimebasedState.failure` and the failure originated from TTS. Allows the app to distinguish between different TTS failure modes and respond accordingly (for example, prompting the user to install voice data when the value is `languageMissingData`).

```dart
enum TtsErrorType {
  languageMissingData,  // Required voice data not installed
  unknown,              // Unclassified TTS error
}
```

These values come from the native TTS engine, which reports granular error codes on Android. See [Android platform docs](../platform-specific/android.md#event-channels) for how native events reach Dart.

### TimebasedState Enum

```dart
enum TimebasedState {
  playing,   // Currently playing
  loading,   // Loading/buffering
  paused,    // Paused by user
  ended,     // Reached end
  failure,   // Error occurred
}
```

### Building a Progress Bar

```dart
class AudioProgressBar extends StatelessWidget {
  final ReadiumTimebasedState state;

  const AudioProgressBar({required this.state, super.key});

  @override
  Widget build(BuildContext context) {
    final current = state.currentOffset?.inMilliseconds ?? 0;
    final total = state.currentDuration?.inMilliseconds ?? 1;
    final progress = current / total;

    return Column(
      children: [
        LinearProgressIndicator(value: progress),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatDuration(state.currentOffset)),
            Text(_formatDuration(state.currentDuration)),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
```

## onReaderStatusChanged

Emits when the reader's overall status changes.

**Type:** `Stream<ReadiumReaderStatus>`

### Usage

```dart
flureadium.onReaderStatusChanged.listen((status) {
  switch (status) {
    case ReadiumReaderStatus.loading:
      showLoadingIndicator();
      break;
    case ReadiumReaderStatus.ready:
      hideLoadingIndicator();
      break;
    case ReadiumReaderStatus.reachedEndOfPublication:
      showCompletionDialog();
      break;
    case ReadiumReaderStatus.error:
      showErrorMessage();
      break;
    case ReadiumReaderStatus.closed:
      navigateBack();
      break;
  }
});
```

### ReadiumReaderStatus Enum

```dart
enum ReadiumReaderStatus {
  loading,                    // Reader is loading
  ready,                      // Reader is ready
  closed,                     // Publication was closed
  reachedEndOfPublication,    // Reached the end
  error,                      // Error occurred
}
```

### Platform Notes

| Status | Android | iOS |
|--------|---------|-----|
| `loading` | Emitted from `ReadiumReaderWidget.init` | Emitted from `ReadiumReaderView.init` |
| `ready` | Emitted from `onVisualReaderIsReady()`, or from `ReadiumReaderWidget.init` for an audiobook, which has no visual navigator to signal it | Emitted from first `locationDidChange` |
| `closed` | Emitted from `ReadiumReaderWidget.dispose()`, by the widget that still owns the reader registration — a stale platform view replaced by a newer one stays quiet | Emitted on publication close |
| `error` | Emitted whenever a reader coroutine fails, from `readerCoroutineExceptionHandler` | Emitted from `didFailToLoadResourceAt` |
| `reachedEndOfPublication` | Not emitted natively (Dart-side only) | Not emitted natively (Dart-side only) |

On Android the widget's `init` runs inside the platform-view `create` call, which
finishes before Flutter replies to Dart. A `loading`, and the `ready` an audiobook
sends from `init`, therefore leave native before any Dart subscriber can exist, so
the native side holds the most recent status and delivers it when the first
subscriber arrives. Only the latest is held: status is a state rather than a log,
and a status already delivered is never replayed to a later subscriber. The error
channel holds what it is sent under the same rule with a different shape — an
error is an event, not a state, so it keeps the first eight in order instead of
the latest one.

See [Android platform docs](../platform-specific/android.md#event-channels) for implementation details.

### Extension Methods

```dart
extension ReadiumReaderStatusExtension on ReadiumReaderStatus {
  bool get isLoading => this == ReadiumReaderStatus.loading;
  bool get isReady => this == ReadiumReaderStatus.ready;
  bool get isClosed => this == ReadiumReaderStatus.closed;
  bool get isError => this == ReadiumReaderStatus.error;
  bool get isAtEnd => this == ReadiumReaderStatus.reachedEndOfPublication;
}
```

## onErrorEvent

Emits when errors occur in the reader.

**Type:** `Stream<ReadiumError>`

### Usage

```dart
flureadium.onErrorEvent.listen((error) {
  print('Error: ${error.message}');
  print('Code: ${error.code}');

  // Log error
  analytics.logError(error);

  // Show user-friendly message
  showSnackBar('An error occurred: ${error.message}');
});
```

### ReadiumError

```dart
class ReadiumError implements Error {
  final String message;         // Error description
  final String? code;           // Error code
  final Object? data;           // Additional data
  final StackTrace? stackTrace; // Stack trace

  Map<String, dynamic> toJson();
  factory ReadiumError.fromJson(Map<String, dynamic> map);
}
```

### Platform Notes

On iOS the `error` EventChannel is owned by `FlureadiumPlugin`, registered once in `register(with:)` and kept for the lifetime of the plugin. Reader views no longer register their own `error` handler; both `ReadiumReaderView` and `ImageReaderView` route resource-load failures through the plugin's `sendError(message:code:data:)`. Because the channel has a single owner, the Dart subscription survives reader-view open/close cycles, and paths that have no reader view (such as the audiobook player) can send on the same channel. The PDF reader uses a separate `pdf-error` channel and is unaffected.

On Android the `error` EventChannel handler is registered at activity attach time.
Android emits two kinds of error today: a timebased playback failure, with
`code: "TimebasedError"` and the Readium error category as `data`, and an
uncaught reader coroutine failure, with `code: "ReaderFailure"`, the exception
message, and the native stack trace as `data`. A reader failure is usually
reported from platform-view creation, before any Dart subscriber can exist, so
the channel holds errors sent while nobody is listening and replays them in
order, up to eight of them, to the first subscriber. Disposing the channel drops
whatever it still holds, so a finished reader session cannot surface on a later
subscription.

### Error Handling Pattern

```dart
class ReaderErrorHandler {
  late StreamSubscription<ReadiumError> _errorSubscription;

  void init() {
    _errorSubscription = flureadium.onErrorEvent.listen(_handleError);
  }

  void _handleError(ReadiumError error) {
    switch (error.code) {
      case 'NETWORK_ERROR':
        _showRetryDialog();
        break;
      case 'PARSE_ERROR':
        _showCorruptedBookMessage();
        break;
      default:
        _showGenericError(error.message);
    }
  }

  void dispose() {
    _errorSubscription.cancel();
  }
}
```

## Complete Example

### Reader State Management

```dart
class ReaderBloc extends Cubit<ReaderState> {
  final _subscriptions = <StreamSubscription>[];

  ReaderBloc() : super(ReaderState.initial()) {
    _subscriptions.add(
      flureadium.onReaderStatusChanged.listen((status) {
        emit(state.copyWith(status: status));
      }),
    );

    _subscriptions.add(
      flureadium.onTextLocatorChanged
          .debounceTime(Duration(milliseconds: 100))
          .listen((locator) {
        emit(state.copyWith(
          currentLocator: locator,
          progress: locator.locations?.totalProgression ?? 0,
        ));
      }),
    );

    _subscriptions.add(
      flureadium.onTimebasedPlayerStateChanged.listen((playback) {
        emit(state.copyWith(playbackState: playback));
      }),
    );

    _subscriptions.add(
      flureadium.onErrorEvent.listen((error) {
        emit(state.copyWith(error: error));
      }),
    );
  }

  @override
  Future<void> close() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    return super.close();
  }
}

class ReaderState {
  final ReadiumReaderStatus status;
  final Locator? currentLocator;
  final double progress;
  final ReadiumTimebasedState? playbackState;
  final ReadiumError? error;

  const ReaderState({
    this.status = ReadiumReaderStatus.loading,
    this.currentLocator,
    this.progress = 0,
    this.playbackState,
    this.error,
  });

  factory ReaderState.initial() => const ReaderState();

  ReaderState copyWith({
    ReadiumReaderStatus? status,
    Locator? currentLocator,
    double? progress,
    ReadiumTimebasedState? playbackState,
    ReadiumError? error,
  }) => ReaderState(
    status: status ?? this.status,
    currentLocator: currentLocator ?? this.currentLocator,
    progress: progress ?? this.progress,
    playbackState: playbackState ?? this.playbackState,
    error: error,  // Allow clearing error
  );
}
```

### StreamBuilder Usage

```dart
Widget build(BuildContext context) {
  return StreamBuilder<Locator>(
    stream: flureadium.onTextLocatorChanged,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox.shrink();
      }

      final locator = snapshot.data!;
      final progress = locator.locations?.totalProgression ?? 0;

      return LinearProgressIndicator(value: progress);
    },
  );
}
```

## Best Practices

### 1. Always Cancel Subscriptions

```dart
class _ReaderScreenState extends State<ReaderScreen> {
  final _subscriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subscriptions.add(
      flureadium.onTextLocatorChanged.listen((_) {}),
    );
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}
```

### 2. Use Debouncing for Frequent Events

```dart
flureadium.onTextLocatorChanged
    .debounceTime(Duration(milliseconds: 500))
    .listen((locator) {
      // Expensive operation like saving to database
    });
```

### 3. Handle Errors Gracefully

```dart
flureadium.onErrorEvent.listen((error) {
  // Log for debugging
  debugPrint('Reader error: ${error.message}');

  // Show user-friendly message
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Something went wrong')),
    );
  }
});
```

### 4. Use Distinct for Duplicate Prevention

```dart
flureadium.onTextLocatorChanged
    .distinct((a, b) => a.href == b.href)
    .listen((locator) {
      // Only when chapter changes
    });
```

## See Also

- [Flureadium Class](flureadium-class.md) - Main API
- [Locator](locator.md) - Position model
- [Saving Progress Guide](../guides/saving-progress.md) - Using streams for persistence
