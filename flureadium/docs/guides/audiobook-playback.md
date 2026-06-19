# Audiobook Playback Guide

This guide covers playing audiobooks and publications with pre-recorded audio.

## Detecting Audiobooks

### Check Publication Type

```dart
final pub = await flureadium.openPublication(path);

if (pub.conformsToReadiumAudiobook) {
  // Pure audiobook
  _setupAudioPlayer();
} else if (pub.containsMediaOverlays) {
  // EPUB with synchronized audio (read-along)
  _setupReadAlongPlayer();
} else {
  // Standard EPUB - visual only or TTS
  _setupVisualReader();
}
```

## Enabling Audio Playback

### Basic Setup

```dart
await flureadium.audioEnable(
  prefs: AudioPreferences(
    volume: 1.0,
    speed: 1.0,
  ),
);
```

### With Saved Position

```dart
// Restore from saved position
final savedLocator = await loadSavedPosition();

await flureadium.audioEnable(
  prefs: AudioPreferences(
    volume: 1.0,
    speed: 1.0,
    seekInterval: 30,
    allowExternalSeeking: true,
  ),
  fromLocator: savedLocator,
);
```

## Playback Controls

### Basic Controls

```dart
// Start playing
await flureadium.play(null);

// Play from specific position
await flureadium.play(locator);

// Pause
await flureadium.pause();

// Resume
await flureadium.resume();

// Stop
await flureadium.stop();
```

### Track Navigation

```dart
// Next track/chapter
await flureadium.next();

// Previous track/chapter
await flureadium.previous();
```

`next()` and `previous()` move one track along the publication's reading order (the audiobook equivalent of a chapter). They are bounded: `previous()` on the first track and `next()` on the last track stay put.

Do not confuse them with the seek and TOC APIs:

- `audioSeekBy(Duration)` moves the playhead by a relative offset inside the current playback, never across tracks. Use it for the skip-back / skip-forward buttons.
- `skipToNext()` / `skipToPrevious()` on `ReadiumReaderWidget` walk the EPUB table of contents and have no effect on an audiobook.

### Seeking

```dart
// Skip forward 30 seconds
await flureadium.audioSeekBy(Duration(seconds: 30));

// Skip backward 10 seconds
await flureadium.audioSeekBy(Duration(seconds: -10));
```

### Transition Safety

Changing chapter, seeking to a locator, and end-of-track auto-advance all run without blocking the UI thread. The navigator's delegate callbacks serve playback state from the last values Readium delivered off the AVPlayer lock, so a transition never reads back into the live player while the player is mid-seek. Earlier versions read the player's current time from inside the seek itself, which deadlocked and froze the app on every transition (see [Troubleshooting](../troubleshooting.md#ios-app-freezes-on-chapter-change-seek-or-end-of-track-audiobook)).

## Playback State Tracking

### Listening to State

```dart
flureadium.onTimebasedPlayerStateChanged.listen((state) {
  print('State: ${state.state}');
  print('Position: ${state.currentOffset}');
  print('Duration: ${state.currentDuration}');
  print('Buffered: ${state.currentBuffered}');

  // Update UI
  setState(() {
    _isPlaying = state.state == TimebasedState.playing;
    _currentPosition = state.currentOffset;
    _totalDuration = state.currentDuration;
  });
});
```

### TimebasedState Values

```dart
enum TimebasedState {
  playing,   // Currently playing
  loading,   // Loading/buffering
  paused,    // Paused by user
  ended,     // Reached end
  failure,   // Error occurred
}
```

## Audio Preferences

### Configuration Options

```dart
AudioPreferences(
  volume: 1.0,              // 0.0 to 1.0
  speed: 1.5,               // Playback speed multiplier
  pitch: 1.0,               // Audio pitch
  seekInterval: 30,         // Skip interval in seconds
  allowExternalSeeking: true, // Allow lockscreen controls
  controlPanelInfoType: ControlPanelInfoType.chapterTitleAuthor,
)
```

### Updating Preferences During Playback

```dart
// Change speed
await flureadium.audioSetPreferences(AudioPreferences(
  speed: 1.5,
));

// Change skip interval
await flureadium.audioSetPreferences(AudioPreferences(
  seekInterval: 15,
));
```

## Building an Audio Player UI

### Complete Player Widget

```dart
class AudioPlayerWidget extends StatefulWidget {
  final Publication publication;

  const AudioPlayerWidget({required this.publication, super.key});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final _flureadium = Flureadium();

  TimebasedState _state = TimebasedState.paused;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;

  StreamSubscription? _stateSubscription;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Enable audio
    await _flureadium.audioEnable(
      prefs: AudioPreferences(
        speed: _speed,
        seekInterval: 30,
        allowExternalSeeking: true,
      ),
    );

    // Listen for state changes
    _stateSubscription = _flureadium.onTimebasedPlayerStateChanged.listen(
      (state) {
        setState(() {
          _state = state.state;
          _position = state.currentOffset ?? Duration.zero;
          _duration = state.currentDuration ?? Duration.zero;
        });
      },
    );
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _flureadium.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cover and title
          _buildHeader(),

          SizedBox(height: 24),

          // Progress bar
          _buildProgressBar(),

          SizedBox(height: 16),

          // Main controls
          _buildMainControls(),

          SizedBox(height: 16),

          // Speed control
          _buildSpeedControl(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // Cover image
        if (widget.publication.coverUri != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              widget.publication.coverUri.toString(),
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
        SizedBox(width: 16),
        // Title and author
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.publication.metadata.title ?? 'Unknown',
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.publication.metadata.authors
                    .map((a) => a.name)
                    .join(', '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
          ),
          child: Slider(
            value: progress,
            onChanged: (value) {
              final newPosition = Duration(
                milliseconds: (value * _duration.inMilliseconds).round(),
              );
              _flureadium.audioSeekBy(newPosition - _position);
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_position)),
              Text(_formatDuration(_duration)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Skip back 30s
        IconButton(
          icon: Icon(Icons.replay_30),
          iconSize: 40,
          onPressed: () => _flureadium.audioSeekBy(Duration(seconds: -30)),
        ),

        SizedBox(width: 16),

        // Previous track
        IconButton(
          icon: Icon(Icons.skip_previous),
          iconSize: 40,
          onPressed: () => _flureadium.previous(),
        ),

        SizedBox(width: 8),

        // Play/Pause
        IconButton(
          icon: Icon(
            _state == TimebasedState.playing
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
          ),
          iconSize: 72,
          onPressed: _togglePlayback,
        ),

        SizedBox(width: 8),

        // Next track
        IconButton(
          icon: Icon(Icons.skip_next),
          iconSize: 40,
          onPressed: () => _flureadium.next(),
        ),

        SizedBox(width: 16),

        // Skip forward 30s
        IconButton(
          icon: Icon(Icons.forward_30),
          iconSize: 40,
          onPressed: () => _flureadium.audioSeekBy(Duration(seconds: 30)),
        ),
      ],
    );
  }

  Widget _buildSpeedControl() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Speed: '),
        ...['0.5', '1.0', '1.5', '2.0'].map((s) {
          final speed = double.parse(s);
          final isSelected = _speed == speed;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text('${s}x'),
              selected: isSelected,
              onSelected: (selected) async {
                if (selected) {
                  setState(() => _speed = speed);
                  await _flureadium.audioSetPreferences(
                    AudioPreferences(speed: speed),
                  );
                }
              },
            ),
          );
        }),
      ],
    );
  }

  Future<void> _togglePlayback() async {
    if (_state == TimebasedState.playing) {
      await _flureadium.pause();
    } else {
      await _flureadium.play(null);
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
```

## Chapter/Track List

### Building Track List

```dart
Widget buildTrackList(Publication pub) {
  return ListView.builder(
    itemCount: pub.readingOrder.length,
    itemBuilder: (_, index) {
      final track = pub.readingOrder[index];
      return ListTile(
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(track.title ?? 'Track ${index + 1}'),
        subtitle: track.duration != null
            ? Text(_formatDuration(track.duration!))
            : null,
        onTap: () async {
          final locator = pub.locatorFromLink(track);
          if (locator != null) {
            await flureadium.play(locator);
          }
        },
      );
    },
  );
}
```

## Saving Playback Position

### Auto-Save Position

```dart
flureadium.onTimebasedPlayerStateChanged
    .debounceTime(Duration(seconds: 5))
    .listen((state) async {
  if (state.currentLocator != null) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'audio_position_${publication.identifier}',
      state.currentLocator!.json,
    );
  }
});
```

### Restore on Open

```dart
Future<void> _openAudiobook(String path) async {
  final pub = await flureadium.openPublication(path);

  // Restore saved position
  final prefs = await SharedPreferences.getInstance();
  final savedJson = prefs.getString('audio_position_${pub.identifier}');
  Locator? savedLocator;
  if (savedJson != null) {
    savedLocator = Locator.fromJsonString(savedJson);
  }

  await flureadium.audioEnable(
    prefs: AudioPreferences(speed: 1.0),
    fromLocator: savedLocator,
  );
}
```

## Background Playback

### Enabling Background Audio

Background audio is enabled automatically when using `audioEnable`. The audio will continue playing when the app is in the background.

### Lock Screen Controls

```dart
// Enable external seeking for lock screen controls
await flureadium.audioEnable(
  prefs: AudioPreferences(
    allowExternalSeeking: true,
    controlPanelInfoType: ControlPanelInfoType.chapterTitleAuthor,
  ),
);
```

### Control Panel Info Types

```dart
enum ControlPanelInfoType {
  standard,           // Default
  standardWCh,        // Standard with chapter
  chapterTitleAuthor, // Chapter, Title, Author
  chapterTitle,       // Chapter and Title
  titleChapter,       // Title and Chapter
}
```

## Sleep Timer

```dart
class SleepTimer {
  Timer? _timer;
  int _remainingMinutes = 0;

  void start(int minutes) {
    _remainingMinutes = minutes;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: 1), (timer) {
      _remainingMinutes--;
      if (_remainingMinutes <= 0) {
        flureadium.pause();
        timer.cancel();
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _remainingMinutes = 0;
  }

  int get remainingMinutes => _remainingMinutes;
}
```

## In-Car (Android Auto / CarPlay)

Flureadium exposes the open audiobook to Android Auto and CarPlay head units. When a publication is loaded, both platforms present a browsable chapter list and the same transport controls as the in-app player.

### What the browse tree exposes

Both platforms build the list from the publication's `readingOrder` — one entry per chapter, in order. The tree is one level deep (a root that lists chapters; no nested folders). Chapter titles come from each reading-order entry, falling back to `Chapter N` when an entry has no title.

Selecting a chapter on the head unit seeks the same audiobook navigator the in-app controls use. There is no second player, so the car and the app always show the same position.

### Transport behavior

Play/pause, skip (next/previous chapter), and seek on the head unit drive the same navigator and the same now-playing metadata as the lockscreen. On both platforms this reuses the existing media-session / now-playing wiring, so position, duration, and title stay in sync across the app, the lockscreen, and the head unit.

### Host-app setup

The chapter list only appears once the host app declares in-car support. This is platform plumbing the host owns, not a Dart API call:

- **Android Auto** — add the `com.google.android.gms.car.application` manifest metadata and an `automotive_app_desc.xml` descriptor. See [Android platform setup](../platform-specific/android.md#6-android-auto-optional).
- **CarPlay** — add a CarPlay scene to the scene manifest and the `com.apple.developer.carplay-audio` entitlement. The entitlement requires an Apple per-app grant (request lead time applies). See [iOS platform setup](../platform-specific/ios.md#4-carplay-optional).

No Flureadium Dart API changes are needed — the browse tree is built natively from the already-open publication.

## See Also

- [AudioPreferences Reference](../api-reference/preferences.md#audiopreferences)
- [Text-to-Speech Guide](text-to-speech.md) - For synthesized audio
- [Streams and Events](../api-reference/streams-events.md) - Playback state tracking
