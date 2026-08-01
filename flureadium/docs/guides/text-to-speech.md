# Text-to-Speech Guide

This guide covers integrating text-to-speech (TTS) into your reading app.

## Before Enabling TTS

Always check whether the current publication supports TTS before calling `ttsEnable()`. This prevents crashes on unsupported formats (e.g. PDF) and lets you show a user-friendly message instead.

```dart
final canSpeak = await flureadium.ttsCanSpeak();
if (!canSpeak) {
  // Show a message — this publication doesn't support TTS
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('TTS is not supported for this publication')),
  );
  return;
}

// Safe to enable TTS
await flureadium.ttsEnable(null);
await flureadium.play(null);
```

Platform behavior:
- **iOS** — calls `PublicationSpeechSynthesizer.canSpeak(publication:)` to check content service availability.
- **Android** — probes `TtsNavigatorFactory` to see if the publication can be spoken.
- **Web** — returns `true` when the browser has `window.speechSynthesis` and a navigator is loaded.

`ttsCanSpeak()` is safe to call before `ttsEnable()` and has no side effects.

## Handling Android Language Errors

On Android, TTS can fail when the device lacks voice data for the publication's language. You can detect this through the `ttsErrorType` field on `ReadiumTimebasedState` and prompt the user to install the missing voice.

```dart
flureadium.onTimebasedPlayerStateChanged.listen((state) {
  if (state.ttsErrorType == TtsErrorType.languageMissingData) {
    // Android is missing voice data for this language.
    // Show a button or dialog prompting the user to install it.
    showInstallVoiceDialog();
  }
});

Future<void> showInstallVoiceDialog() async {
  // Opens the system voice data installer on Android.
  // No-op on iOS and web.
  await flureadium.ttsRequestInstallVoice();
}
```

`TtsErrorType` values:
- `languageMissingData` — Android only. The TTS engine doesn't have voice data for the requested language.
- `unknown` — a generic TTS engine failure.

This field is always `null` on iOS and web, which don't discriminate TTS error types.

## Getting Voices Before Enabling TTS

Use `ttsGetSystemVoices()` to query available voices from the OS before enabling TTS. This lets you show a voice picker UI while the user is still browsing, without needing a TTS navigator.

```dart
// Works without calling ttsEnable() first
final voices = await flureadium.ttsGetSystemVoices();

// Show a voice picker to the user
final selectedVoice = await showVoicePicker(voices);

// Later, when the user starts reading aloud
await flureadium.ttsEnable(TTSPreferences(
  voiceIdentifier: selectedVoice.identifier,
));
await flureadium.play(null);
```

`ttsGetSystemVoices()` vs `ttsGetAvailableVoices()`:
- `ttsGetSystemVoices()` queries the OS directly — works anytime, no navigator needed.
- `ttsGetAvailableVoices()` reports what the TTS session has. It does not throw merely because TTS is off: on Android and iOS it returns an empty list, and on Web it queries the browser and may return voices either way.

Both return the same `ReaderTTSVoice` model. Use `ttsGetSystemVoices()` when you need voices before playback starts.

Platform behavior:
- **iOS** — calls `AVSpeechSynthesizer.speechVoices()` (static, no initialization).
- **Android** — creates a temporary `TextToSpeech` instance, gets voices, then disposes it.
- **Web** — calls `window.speechSynthesis.getVoices()` (same as `ttsGetAvailableVoices` on web).

## Enabling TTS

### Basic Setup

```dart
// Enable TTS with default settings
await flureadium.ttsEnable(null);

// Or with custom preferences
await flureadium.ttsEnable(TTSPreferences(
  speed: 1.0,   // Normal speed
  pitch: 1.0,   // Normal pitch
));
```

### With Voice Selection

```dart
// Get the device's voices — no TTS session needed yet
final voices = await flureadium.ttsGetSystemVoices();

// Select a voice
final englishVoice = voices.firstWhere(
  (v) => v.language.startsWith('en'),
  orElse: () => voices.first,
);

// Enable with selected voice
await flureadium.ttsEnable(TTSPreferences(
  speed: 1.0,
  pitch: 1.0,
  voiceIdentifier: englishVoice.identifier,
));
```

### Resuming from Position

Save the current TTS position before stopping, then pass it back when re-enabling:

```dart
Locator? lastTtsLocator;

// Save position from the timebased state stream while TTS is playing
flureadium.onTimebasedPlayerStateChanged.listen((state) {
  lastTtsLocator = state.currentLocator;
});

// Later, resume from where TTS left off
await flureadium.ttsEnable(
  TTSPreferences(speed: 1.0),
  fromLocator: lastTtsLocator,
);
await flureadium.play(null);
```

Without `fromLocator`, TTS starts from the current visible position in the reader, which may not match where TTS previously stopped.

### Starting TTS After Navigation

When the user disables TTS, navigates to a different page, and then re-enables TTS, you should detect the navigation and pass `fromLocator: null` instead of the saved TTS locator. This makes TTS start from the current reader position rather than jumping back to where TTS left off on the previous page.

```dart
Locator? lastTtsLocator;
Locator? readerLocatorAtTtsDisable;

// When disabling TTS, save both the TTS position and the reader position
lastTtsLocator = timebasedState?.currentLocator;
readerLocatorAtTtsDisable = currentReaderLocator;

// When re-enabling, check if the reader moved since TTS was disabled
final navigated = readerLocatorAtTtsDisable != null &&
    currentReaderLocator != null &&
    readerLocatorAtTtsDisable != currentReaderLocator;
final resumeLocator = navigated ? null : lastTtsLocator;

await flureadium.ttsEnable(
  TTSPreferences(speed: 1.0),
  fromLocator: resumeLocator,
);
await flureadium.play(null);
```

Both iOS and Android have scroll-suppression logic in their TTS navigators that prevents the reader from jumping backward when TTS starts mid-utterance at a new position. This means the reader stays on the page the user navigated to while TTS begins reading from that position.

## Playback Controls

### Basic Controls

```dart
// Start playing from current position
await flureadium.play(null);

// Start from a specific position
await flureadium.play(savedLocator);

// Pause
await flureadium.pause();

// Resume
await flureadium.resume();

// Stop completely
await flureadium.stop();
```

### Sentence Navigation

```dart
// Move to next sentence
await flureadium.next();

// Move to previous sentence
await flureadium.previous();
```

## Voice Selection

### Getting Available Voices

```dart
final voices = await flureadium.ttsGetAvailableVoices();

for (final voice in voices) {
  print('Name: ${voice.name}');
  print('Language: ${voice.language}');
  print('ID: ${voice.identifier}');
  print('---');
}
```

### Setting a Voice

```dart
// Set by identifier
await flureadium.ttsSetVoice(
  'com.apple.voice.compact.en-US.Samantha',
  'en-US',
);

// Or just identifier without language filter
await flureadium.ttsSetVoice(voiceId, null);
```

### Voice Picker UI

```dart
class VoicePicker extends StatefulWidget {
  @override
  State<VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<VoicePicker> {
  List<ReaderTTSVoice>? _voices;
  String? _selectedVoiceId;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    // ttsGetSystemVoices works before ttsEnable — show voices immediately
    final voices = await flureadium.ttsGetSystemVoices();
    setState(() => _voices = voices);
  }

  @override
  Widget build(BuildContext context) {
    if (_voices == null) {
      return CircularProgressIndicator();
    }

    // Group by language
    final grouped = <String, List<ReaderTTSVoice>>{};
    for (final voice in _voices!) {
      final lang = voice.language.split('-').first;
      grouped.putIfAbsent(lang, () => []).add(voice);
    }

    return ListView(
      children: grouped.entries.map((entry) {
        return ExpansionTile(
          title: Text(_languageName(entry.key)),
          children: entry.value.map((voice) {
            return RadioListTile<String>(
              title: Text(voice.name),
              subtitle: Text(voice.language),
              value: voice.identifier,
              groupValue: _selectedVoiceId,
              onChanged: (id) async {
                setState(() => _selectedVoiceId = id);
                await flureadium.ttsSetVoice(id!, voice.language);
              },
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  String _languageName(String code) {
    const names = {'en': 'English', 'es': 'Spanish', 'fr': 'French'};
    return names[code] ?? code;
  }
}
```

## Speed and Pitch Control

### Adjusting Speed

```dart
await flureadium.ttsSetPreferences(TTSPreferences(
  speed: 1.5,  // 50% faster
));
```

### Speed Slider

```dart
class SpeedControl extends StatefulWidget {
  @override
  State<SpeedControl> createState() => _SpeedControlState();
}

class _SpeedControlState extends State<SpeedControl> {
  double _speed = 1.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Speed: ${_speed.toStringAsFixed(1)}x'),
        Slider(
          min: 0.5,
          max: 2.0,
          divisions: 15,
          value: _speed,
          onChanged: (value) async {
            setState(() => _speed = value);
            await flureadium.ttsSetPreferences(TTSPreferences(
              speed: value,
            ));
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => _setSpeed(0.75),
              child: Text('0.75x'),
            ),
            TextButton(
              onPressed: () => _setSpeed(1.0),
              child: Text('1x'),
            ),
            TextButton(
              onPressed: () => _setSpeed(1.5),
              child: Text('1.5x'),
            ),
            TextButton(
              onPressed: () => _setSpeed(2.0),
              child: Text('2x'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await flureadium.ttsSetPreferences(TTSPreferences(speed: speed));
  }
}
```

## TTS Highlighting

Highlight the current sentence and word being spoken.

### Setting Decoration Styles

```dart
await flureadium.setDecorationStyle(
  // Current sentence highlight
  ReaderDecorationStyle(
    style: DecorationStyle.highlight,
    tint: Color(0x80FFFF00),  // Semi-transparent yellow
  ),
  // Current word highlight
  ReaderDecorationStyle(
    style: DecorationStyle.underline,
    tint: Color(0xFF0000FF),  // Blue underline
  ),
);
```

### Customizable Highlight Colors

```dart
class TTSHighlightSettings {
  Color sentenceColor;
  Color wordColor;

  TTSHighlightSettings({
    this.sentenceColor = const Color(0x80FFFF00),
    this.wordColor = const Color(0xFF0000FF),
  });

  Future<void> apply() async {
    await flureadium.setDecorationStyle(
      ReaderDecorationStyle(
        style: DecorationStyle.highlight,
        tint: sentenceColor,
      ),
      ReaderDecorationStyle(
        style: DecorationStyle.underline,
        tint: wordColor,
      ),
    );
  }
}
```

## Tracking Playback State

### Listening to State Changes

```dart
flureadium.onTimebasedPlayerStateChanged.listen((state) {
  switch (state.state) {
    case TimebasedState.playing:
      print('Playing');
      break;
    case TimebasedState.paused:
      print('Paused');
      break;
    case TimebasedState.ended:
      print('Finished');
      break;
    case TimebasedState.loading:
      print('Loading...');
      break;
    case TimebasedState.failure:
      print('Error');
      break;
  }
});
```

### Playback UI State

```dart
class TTSController extends StatefulWidget {
  @override
  State<TTSController> createState() => _TTSControllerState();
}

class _TTSControllerState extends State<TTSController> {
  TimebasedState _state = TimebasedState.paused;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = flureadium.onTimebasedPlayerStateChanged.listen((state) {
      setState(() => _state = state.state);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.skip_previous),
          onPressed: () => flureadium.previous(),
        ),
        IconButton(
          icon: Icon(_state == TimebasedState.playing
              ? Icons.pause
              : Icons.play_arrow),
          iconSize: 48,
          onPressed: _togglePlayback,
        ),
        IconButton(
          icon: Icon(Icons.skip_next),
          onPressed: () => flureadium.next(),
        ),
      ],
    );
  }

  Future<void> _togglePlayback() async {
    if (_state == TimebasedState.playing) {
      await flureadium.pause();
    } else {
      await flureadium.resume();
    }
  }
}
```

## Complete TTS Integration

```dart
class TTSReaderScreen extends StatefulWidget {
  final Publication publication;

  const TTSReaderScreen({required this.publication, super.key});

  @override
  State<TTSReaderScreen> createState() => _TTSReaderScreenState();
}

class _TTSReaderScreenState extends State<TTSReaderScreen> {
  final _flureadium = Flureadium();
  bool _ttsEnabled = false;
  TimebasedState _playbackState = TimebasedState.paused;
  double _speed = 1.0;
  List<ReaderTTSVoice>? _voices;
  String? _selectedVoiceId;
  Locator? _lastTtsLocator;

  StreamSubscription? _stateSubscription;

  @override
  void initState() {
    super.initState();
    _loadVoices();
    _stateSubscription = _flureadium.onTimebasedPlayerStateChanged.listen(
      (state) {
        _lastTtsLocator = state.currentLocator;
        setState(() => _playbackState = state.state);
      },
    );
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    if (_ttsEnabled) {
      _flureadium.stop();
    }
    super.dispose();
  }

  Future<void> _loadVoices() async {
    // ttsGetSystemVoices works before ttsEnable — populate the picker early
    final voices = await _flureadium.ttsGetSystemVoices();
    setState(() {
      _voices = voices;
      // Select first English voice by default
      _selectedVoiceId = voices
          .firstWhere(
            (v) => v.language.startsWith('en'),
            orElse: () => voices.first,
          )
          .identifier;
    });
  }

  Future<void> _enableTTS({Locator? fromLocator}) async {
    await _flureadium.ttsEnable(
      TTSPreferences(speed: _speed, voiceIdentifier: _selectedVoiceId),
      fromLocator: fromLocator,
    );

    // Set up highlighting
    await _flureadium.setDecorationStyle(
      ReaderDecorationStyle(
        style: DecorationStyle.highlight,
        tint: Color(0x80FFFF00),
      ),
      ReaderDecorationStyle(
        style: DecorationStyle.underline,
        tint: Color(0xFF0000FF),
      ),
    );

    setState(() => _ttsEnabled = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Reader
          Expanded(
            child: ReadiumReaderWidget(
              publication: widget.publication,
            ),
          ),

          // TTS Controls
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Column(
              children: [
                // Enable/Disable TTS
                if (!_ttsEnabled)
                  ElevatedButton.icon(
                    icon: Icon(Icons.record_voice_over),
                    label: Text('Enable Read Aloud'),
                    onPressed: _enableTTS,
                  )
                else
                  Column(
                    children: [
                      // Playback controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.skip_previous),
                            onPressed: () => _flureadium.previous(),
                          ),
                          IconButton(
                            icon: Icon(
                              _playbackState == TimebasedState.playing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                            ),
                            iconSize: 56,
                            onPressed: _togglePlayback,
                          ),
                          IconButton(
                            icon: Icon(Icons.skip_next),
                            onPressed: () => _flureadium.next(),
                          ),
                          IconButton(
                            icon: Icon(Icons.stop),
                            onPressed: _stopTTS,
                          ),
                        ],
                      ),

                      // Speed control
                      Row(
                        children: [
                          Text('Speed:'),
                          Expanded(
                            child: Slider(
                              min: 0.5,
                              max: 2.0,
                              divisions: 15,
                              value: _speed,
                              label: '${_speed.toStringAsFixed(1)}x',
                              onChanged: (value) async {
                                setState(() => _speed = value);
                                await _flureadium.ttsSetPreferences(
                                  TTSPreferences(speed: value),
                                );
                              },
                            ),
                          ),
                        ],
                      ),

                      // Voice selection
                      if (_voices != null)
                        DropdownButton<String>(
                          value: _selectedVoiceId,
                          items: _voices!.map((v) {
                            return DropdownMenuItem(
                              value: v.identifier,
                              child: Text('${v.name} (${v.language})'),
                            );
                          }).toList(),
                          onChanged: (id) async {
                            setState(() => _selectedVoiceId = id);
                            final voice = _voices!.firstWhere(
                              (v) => v.identifier == id,
                            );
                            await _flureadium.ttsSetVoice(
                              id!,
                              voice.language,
                            );
                          },
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlayback() async {
    if (_playbackState == TimebasedState.playing) {
      await _flureadium.pause();
    } else {
      await _flureadium.play(null);
    }
  }

  Future<void> _stopTTS() async {
    await _flureadium.stop();
    setState(() => _ttsEnabled = false);
    // _lastTtsLocator is preserved so _enableTTS can resume from it.
  }
}
```

## Platform Notes

### iOS

- Uses AVSpeechSynthesizer through Readium's `PublicationSpeechSynthesizer`
- Voices are managed by the OS — `ttsRequestInstallVoice()` is a no-op
- `ttsCanSpeak()` checks content service availability via Readium
- `ttsGetSystemVoices()` calls `AVSpeechSynthesizer.speechVoices()` directly (static, no navigator)
- Voices are returned sorted alphabetically
- Word-level highlighting through `AVSpeechSynthesizerDelegate`

### Android

- Uses Readium's `TtsNavigator` backed by `AndroidTtsEngine`
- `ttsCanSpeak()` probes `TtsNavigatorFactory` to check publication support
- `ttsGetSystemVoices()` creates a temporary `TextToSpeech` instance, gets voices, then disposes it
- `ttsRequestInstallVoice()` opens the system voice data installer
- `TtsErrorType.languageMissingData` fires when voice data is missing for the publication's language
- Voice quality and availability vary by device and installed language packs
- When `fromLocator` is provided to `ttsEnable()`, Android uses it as the starting position. When null, it falls back to the first visible locator in the reader.

### Web

- Uses the Web Speech API (`window.speechSynthesis`)
- `ttsCanSpeak()` checks browser support and navigator readiness
- `ttsGetSystemVoices()` calls `window.speechSynthesis.getVoices()` (same as `ttsGetAvailableVoices` on web)
- `ttsRequestInstallVoice()` is a no-op — browsers manage voices through the OS
- No background playback — the browser tab must stay active
- Word-level highlighting is Chrome-only (via `SpeechSynthesisUtterance.onboundary`); sentence-level works cross-browser
- `setDecorationStyle()` is a no-op on web — the Web Speech API operates on extracted text, not the live EPUB DOM
- Voice enumeration may require user interaction in some browsers before voices load
- Position updates are resource-level only (no CFI precision from Web Speech API)

## See Also

- [TTSPreferences Reference](../api-reference/preferences.md#ttspreferences)
- [Audiobook Playback](audiobook-playback.md) - For pre-recorded audio
- [Streams and Events](../api-reference/streams-events.md) - Playback state tracking
