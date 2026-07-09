import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flureadium/flureadium.dart';

const _defaultInitialAsset = String.fromEnvironment(
  'FLUREADIUM_INITIAL_ASSET',
  defaultValue: 'assets/pubs/moby_dick.epub',
);

void main({String initialAsset = _defaultInitialAsset}) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ExampleApp(initialAsset: initialAsset));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({this.initialAsset = _defaultInitialAsset, super.key});

  final String initialAsset;

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: ReaderPage(initialAsset: initialAsset));
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({this.initialAsset = _defaultInitialAsset, super.key});

  final String initialAsset;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _flureadium = Flureadium();
  Publication? _publication;
  Locator? _locator;
  Locator? _savedLocator;
  ReadiumTimebasedState? _timebasedState;
  bool _endedSeen = false;
  bool _controlsVisible = true;
  bool _ttsEnabled = false;
  Locator? _lastTtsLocator;
  Locator? _readerLocatorAtTtsDisable;
  bool _audioEnabled = false;
  bool _audioPaused = false;
  List<ReaderTTSVoice> _voices = [];
  int _voiceIndex = 0;
  TimebasedState? _ttsPlaybackState;
  TtsErrorType? _ttsErrorType;
  double _ttsSpeed = 1.0;
  // Latches the last error delivered on onErrorEvent so integration tests can
  // assert that a failed audio resource load surfaces instead of stalling.
  String _lastAudioError = '';
  // Local server backing the 'Open AudioBook BadStream' action: serves a WAV
  // whose Content-Length promises the full clip but drops the socket after a
  // partial body, producing a mid-stream failure both audio engines observe.
  HttpServer? _badStreamServer;

  StreamSubscription<ReadiumReaderStatus>? _statusSub;
  StreamSubscription<Locator>? _locatorSub;
  StreamSubscription<ReadiumError>? _errorSub;
  StreamSubscription<ReadiumTimebasedState>? _timebasedSub;

  @override
  void initState() {
    super.initState();
    // timebased-state is registered eagerly by the plugin; subscribe here.
    // reader-status, text-locator and error are registered lazily on iOS
    // (inside ReadiumReaderView.init(), which fires from _onPlatformViewCreated).
    // Those channels are subscribed via ReadiumReaderWidget.onReady, which is
    // called from _onPlatformViewCreated after all native handlers are set up.
    _timebasedSub = _flureadium.onTimebasedPlayerStateChanged.listen(
      (s) => setState(() {
        _timebasedState = s;
        // Latch end-of-book: the player can settle to `paused` immediately
        // after emitting `ended`, so the resting state is not reliable. Record
        // that `ended` was ever delivered for end-of-book assertions.
        if (s.state == TimebasedState.ended) _endedSeen = true;
        _ttsPlaybackState = _ttsEnabled ? s.state : null;
        _ttsErrorType = _ttsEnabled ? s.ttsErrorType : null;
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openPublicationAsset(widget.initialAsset),
    );
  }

  // Called by ReadiumReaderWidget.onReady, which fires from _onPlatformViewCreated
  // after the native platform view (and all EventChannel handlers) are ready.
  // Safe to call on all platforms: Android registers channels eagerly; iOS
  // registers them lazily in ReadiumReaderView.init() which runs just before
  // onReady fires. No polling, no timers — pumpAndSettle works correctly.
  void _subscribeToChannels() {
    _statusSub?.cancel();
    _locatorSub?.cancel();
    _errorSub?.cancel();
    _statusSub = _flureadium.onReaderStatusChanged.listen(
      (s) => debugPrint('ReaderStatus: $s'),
    );
    _locatorSub = _flureadium.onTextLocatorChanged.listen(
      (l) => setState(() {
        _locator = l;
        _savedLocator = l;
      }),
    );
    _errorSub = _flureadium.onErrorEvent.listen((e) {
      debugPrint('FlureadiumError: $e');
      if (!mounted) return;
      setState(() => _lastAudioError = e.message);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _locatorSub?.cancel();
    _errorSub?.cancel();
    _timebasedSub?.cancel();
    _badStreamServer?.close(force: true);
    super.dispose();
  }

  Future<void> _openEpub() async {
    try {
      await _openPublicationAsset('assets/pubs/moby_dick.epub');
    } catch (e) {
      debugPrint('openEpub error: $e');
    }
  }

  Future<void> _openCbz() async {
    try {
      await _openPublicationAsset('assets/pubs/sample_comic.cbz');
    } catch (e) {
      debugPrint('openCbz error: $e');
    }
  }

  Future<void> _openDivina() async {
    try {
      await _openPublicationAsset('assets/pubs/sample_visual.divina');
    } catch (e) {
      debugPrint('openDivina error: $e');
    }
  }

  Future<void> _openAudiobook() async {
    try {
      final path = await _extractAsset('assets/pubs/38533.audiobook');
      final pub = await _flureadium.openPublication(path);
      if (!mounted) return;
      setState(() {
        _publication = pub;
        _endedSeen = false;
        _ttsEnabled = false;
        _lastTtsLocator = null;
        _readerLocatorAtTtsDisable = null;
        _audioEnabled = false;
        _audioPaused = false;
        _voices = [];
        _voiceIndex = 0;
      });
    } catch (e) {
      debugPrint('openAudiobook error: $e');
    }
  }

  Future<void> _openAudiobookUntitledChapter() async {
    try {
      final path = await _extractAsset(
        'assets/pubs/untitled_chapter.audiobook',
      );
      final pub = await _flureadium.openPublication(path);
      if (!mounted) return;
      setState(() {
        _publication = pub;
        _ttsEnabled = false;
        _lastTtsLocator = null;
        _readerLocatorAtTtsDisable = null;
        _audioEnabled = false;
        _audioPaused = false;
        _voices = [];
        _voiceIndex = 0;
      });
    } catch (e) {
      debugPrint('openAudiobookUntitledChapter error: $e');
    }
  }

  Future<void> _openUnreachableAudiobook() async {
    // A well-formed audiobook manifest whose only track points at an
    // unreachable host. The manifest parses, but the first audio resource load
    // fails inside AVFoundation — the streaming path Phase 2 forwards to
    // onErrorEvent instead of stalling silently at 0:00.
    const manifest = '''
{
  "@context": "https://readium.org/webpub-manifest/context.jsonld",
  "metadata": {
    "@type": "http://schema.org/Audiobook",
    "conformsTo": "https://readium.org/webpub-manifest/profiles/audiobook",
    "title": "Unreachable Audio",
    "duration": 120
  },
  "links": [
    { "rel": "self", "href": "http://127.0.0.1:9/manifest.json", "type": "application/audiobook+json" }
  ],
  "readingOrder": [
    { "href": "http://127.0.0.1:9/unreachable.mp3", "type": "audio/mpeg", "duration": 120 }
  ]
}
''';
    try {
      final tmp = File(
        '${Directory.systemTemp.path}/'
        '${DateTime.now().millisecondsSinceEpoch}_unreachable.json',
      );
      await tmp.writeAsString(manifest);
      final pub = await _flureadium.openPublication(tmp.path);
      if (!mounted) return;
      setState(() {
        _publication = pub;
        _lastAudioError = '';
        _endedSeen = false;
        _ttsEnabled = false;
        _lastTtsLocator = null;
        _readerLocatorAtTtsDisable = null;
        _audioEnabled = false;
        _audioPaused = false;
        _voices = [];
        _voiceIndex = 0;
      });
    } catch (e) {
      debugPrint('openUnreachableAudiobook error: $e');
    }
  }

  // Builds a 44-byte canonical PCM WAV header declaring [dataSize] bytes of
  // audio data. The header is valid on its own, so a player can start decoding
  // before the (never fully delivered) data chunk arrives.
  Uint8List _wavHeader({
    required int dataSize,
    int sampleRate = 8000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final header = ByteData(44);
    void putAscii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    putAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataSize, Endian.little);
    putAscii(8, 'WAVE');
    putAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    header.setUint16(20, 1, Endian.little); // audioFormat = PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    putAscii(36, 'data');
    header.setUint32(40, dataSize, Endian.little);
    return header.buffer.asUint8List();
  }

  // Opens an audiobook whose single track streams from a local server that
  // sends a valid WAV header plus a short PCM prefix, then drops the socket
  // before satisfying the advertised Content-Length. Playback starts and then
  // fails mid-stream — the observable failure path (unlike a dead host, which
  // fails at load time before iOS can surface it).
  Future<void> _openMidStreamFailAudiobook() async {
    const sampleRate = 8000;
    const bytesPerSample = 2; // 16-bit mono
    const fullDataSize = sampleRate * bytesPerSample * 30; // 30s promised
    const prefixSize = sampleRate * bytesPerSample; // 1s actually sent
    final header = _wavHeader(dataSize: fullDataSize, sampleRate: sampleRate);
    final contentLength = header.length + fullDataSize;

    await _badStreamServer?.close(force: true);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _badStreamServer = server;
    server.listen((request) async {
      // Bypass HttpResponse's length bookkeeping: write a raw response whose
      // Content-Length exceeds what we send, then close early.
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.add(
        utf8.encode(
          'HTTP/1.1 200 OK\r\n'
          'Content-Type: audio/wav\r\n'
          'Content-Length: $contentLength\r\n'
          'Accept-Ranges: none\r\n'
          'Connection: close\r\n\r\n',
        ),
      );
      socket.add(header);
      socket.add(Uint8List(prefixSize)); // 1s of silence, then nothing
      await socket.flush();
      await socket.close();
      socket.destroy();
    });

    final audioUrl = 'http://127.0.0.1:${server.port}/audio.wav';
    final manifest =
        '''
{
  "@context": "https://readium.org/webpub-manifest/context.jsonld",
  "metadata": {
    "@type": "http://schema.org/Audiobook",
    "conformsTo": "https://readium.org/webpub-manifest/profiles/audiobook",
    "title": "Truncated Stream Audio",
    "duration": 30
  },
  "links": [
    { "rel": "self", "href": "$audioUrl", "type": "application/audiobook+json" }
  ],
  "readingOrder": [
    { "href": "$audioUrl", "type": "audio/wav", "duration": 30 }
  ]
}
''';
    try {
      final tmp = File(
        '${Directory.systemTemp.path}/'
        '${DateTime.now().millisecondsSinceEpoch}_truncated.json',
      );
      await tmp.writeAsString(manifest);
      final pub = await _flureadium.openPublication(tmp.path);
      if (!mounted) return;
      setState(() {
        _publication = pub;
        _lastAudioError = '';
        _endedSeen = false;
        _ttsEnabled = false;
        _lastTtsLocator = null;
        _readerLocatorAtTtsDisable = null;
        _audioEnabled = false;
        _audioPaused = false;
        _voices = [];
        _voiceIndex = 0;
      });
    } catch (e) {
      debugPrint('openMidStreamFailAudiobook error: $e');
    }
  }

  Future<void> _openPublicationAsset(String assetPath) async {
    final path = await _extractAsset(assetPath);
    final pub = await _flureadium.openPublication(path);
    if (!mounted) return;
    setState(() {
      _publication = pub;
      _ttsEnabled = false;
      _lastTtsLocator = null;
      _readerLocatorAtTtsDisable = null;
      _audioEnabled = false;
      _audioPaused = false;
      _voices = [];
      _voiceIndex = 0;
    });
  }

  Future<void> _openWebPub() async {
    try {
      await _flureadium.setCustomHeaders({'X-Example': 'flureadium-demo'});
      const url =
          'https://readium.org/webpub-manifest/examples/MobyDick/manifest.json';
      final pub = await _flureadium.openPublication(url);
      if (!mounted) return;
      setState(() {
        _publication = pub;
        _ttsEnabled = false;
        _lastTtsLocator = null;
        _readerLocatorAtTtsDisable = null;
        _audioEnabled = false;
        _audioPaused = false;
        _voices = [];
        _voiceIndex = 0;
      });
    } catch (e) {
      debugPrint('openWebPub error: $e');
    }
  }

  Future<String> _extractAsset(String assetPath) async {
    if (kIsWeb) {
      return Uri.base.resolve(assetPath).toString();
    }
    final bytes = await rootBundle.load(assetPath);
    final filename = assetPath.split('/').last;
    final tmp = File(
      '${Directory.systemTemp.path}/${DateTime.now().millisecondsSinceEpoch}_$filename',
    );
    await tmp.writeAsBytes(bytes.buffer.asUint8List());
    return tmp.path;
  }

  Future<void> _close() async {
    await _flureadium.closePublication();
    if (!mounted) return;
    setState(() {
      _publication = null;
      _ttsEnabled = false;
      _lastTtsLocator = null;
      _readerLocatorAtTtsDisable = null;
      _audioEnabled = false;
      _audioPaused = false;
      _voices = [];
      _voiceIndex = 0;
    });
  }

  Future<void> _setNightPreferences() async {
    await _flureadium.setEPUBPreferences(
      EPUBPreferences(
        fontFamily: 'Georgia',
        fontSize: 100,
        fontWeight: null,
        verticalScroll: false,
        backgroundColor: const Color(0xFF1A1A1A),
        textColor: const Color(0xFFE0E0E0),
      ),
    );
  }

  Future<void> _toggleTts() async {
    if (_ttsEnabled) {
      _lastTtsLocator = _timebasedState?.currentLocator;
      _readerLocatorAtTtsDisable = _locator;
      await _flureadium.stop();
      if (!mounted) return;
      setState(() {
        _ttsEnabled = false;
        _ttsPlaybackState = null;
        _ttsErrorType = null;
        _voices = [];
        _voiceIndex = 0;
      });
      return;
    }
    final canSpeak = await _flureadium.ttsCanSpeak();
    if (!canSpeak) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('TTS is not supported for this publication'),
          ),
        );
      }
      return;
    }
    // Detect whether the reader position changed since TTS was disabled.
    // If the user navigated to a different page, start TTS from the current
    // reader position (fromLocator: null) instead of resuming from the saved
    // TTS locator — this prevents backward scrolling to the previous page.
    final navigated =
        _readerLocatorAtTtsDisable != null &&
        _locator != null &&
        _readerLocatorAtTtsDisable != _locator;
    final resumeLocator = navigated ? null : _lastTtsLocator;
    await _flureadium.ttsEnable(
      TTSPreferences(speed: _ttsSpeed),
      fromLocator: resumeLocator,
    );
    if (!mounted) return;
    // Set _ttsEnabled before play() so that the onTimebasedPlayerStateChanged
    // callback (which guards on _ttsEnabled) correctly captures the 'playing'
    // state when the native engine reports it.
    setState(() {
      _ttsEnabled = true;
    });
    await _flureadium.play(null);
    final voices = await _flureadium.ttsGetAvailableVoices();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _voiceIndex = 0;
    });
  }

  Future<void> _ttsPause() async => _flureadium.pause();

  Future<void> _ttsResume() async => _flureadium.resume();

  Future<void> _installVoice() async => _flureadium.ttsRequestInstallVoice();

  Future<void> _showSystemVoices() async {
    final voices = await _flureadium.ttsGetSystemVoices();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('System voices: ${voices.length}')));
  }

  Future<void> _nextVoice() async {
    if (_voices.isEmpty) return;
    final next = (_voiceIndex + 1) % _voices.length;
    final voice = _voices[next];
    await _flureadium.ttsSetVoice(voice.identifier, voice.language);
    if (!mounted) return;
    setState(() => _voiceIndex = next);
  }

  Future<void> _toggleAudio() async {
    if (_audioEnabled && !_audioPaused) {
      await _flureadium.pause();
      if (!mounted) return;
      setState(() => _audioPaused = true);
    } else if (_audioEnabled && _audioPaused) {
      await _flureadium.resume();
      if (!mounted) return;
      setState(() => _audioPaused = false);
    } else {
      try {
        await _flureadium.audioEnable();
        await _flureadium.play(null);
        if (!mounted) return;
        setState(() {
          _audioEnabled = true;
          _audioPaused = false;
        });
      } catch (e) {
        debugPrint('audioEnable error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Audio playback unavailable: $e')),
          );
        }
      }
    }
  }

  Future<void> _addHighlight() async {
    final loc = _locator;
    if (loc == null) return;
    await _flureadium.applyDecorations('highlights', [
      ReaderDecoration(
        id: 'h_${DateTime.now().millisecondsSinceEpoch}',
        locator: loc,
        style: ReaderDecorationStyle(
          style: DecorationStyle.highlight,
          tint: const Color(0xFFFFFF00),
        ),
      ),
    ]);
  }

  Future<void> _goToSaved() async {
    final loc = _savedLocator;
    if (loc == null) return;
    await _flureadium.goToLocator(loc);
  }

  Future<void> _seekForward() =>
      _flureadium.audioSeekBy(const Duration(seconds: 30));

  Future<void> _nextChapter() => _flureadium.next();

  Future<void> _previousChapter() => _flureadium.previous();

  Future<void> _goToFirstChapter() async {
    final pub = _publication;
    if (pub == null) return;
    final link =
        pub.tableOfContents.firstOrNull ?? pub.readingOrder.firstOrNull;
    if (link == null) return;
    await _flureadium.goByLink(link, pub);
  }

  Future<void> _openHierarchical() async {
    try {
      await _openPublicationAsset('assets/pubs/hierarchical_toc.epub');
    } catch (e) {
      debugPrint('openHierarchical error: $e');
    }
  }

  Future<void> _dartSkipToNext() async =>
      FlureadiumPlatform.instance.currentReaderWidget?.skipToNext();

  Future<void> _dartSkipToPrevious() async =>
      FlureadiumPlatform.instance.currentReaderWidget?.skipToPrevious();

  Future<void> _loadOnly() async {
    try {
      final path = await _extractAsset('assets/pubs/moby_dick.epub');
      final pub = await _flureadium.loadPublication(path);
      debugPrint(
        'Loaded: ${pub.metadata.title} (${pub.tableOfContents.length} chapters)',
      );
    } catch (e) {
      debugPrint('loadOnly error: $e');
    }
  }

  String _fmtDuration(Duration? d) {
    if (d == null) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pub = _publication;
    return Scaffold(
      body: Stack(
        children: [
          if (pub != null)
            ReadiumReaderWidget(
              publication: pub,
              onTap: () => setState(() => _controlsVisible = !_controlsVisible),
              onReady: _subscribeToChannels,
            )
          else
            const Center(child: CircularProgressIndicator()),
          if (pub == null || _controlsVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_timebasedState case final s?)
                      Text(
                        '${_fmtDuration(s.currentOffset)} / ${_fmtDuration(s.currentDuration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    Text(
                      key: const Key('current-track'),
                      'track: ${_timebasedState?.currentLocator?.locations?.position ?? '-'} '
                      '${_timebasedState?.currentLocator?.href ?? ''}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      key: const Key('timebased-state'),
                      'state: ${_timebasedState?.state.name ?? '-'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      key: const Key('timebased-position'),
                      'pos: ${_timebasedState?.currentOffset?.inMilliseconds ?? -1} '
                      'dur: ${_timebasedState?.currentDuration?.inMilliseconds ?? -1}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      key: const Key('ended-seen'),
                      'ended-seen: $_endedSeen',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      key: const Key('audio-error'),
                      'audio-error: $_lastAudioError',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      key: const Key('locator_href'),
                      _locator?.href ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: _openEpub,
                          child: const Text('Open EPUB'),
                        ),
                        TextButton(
                          onPressed: _openHierarchical,
                          child: const Text('Open Hierarchical'),
                        ),
                        TextButton(
                          onPressed: _openAudiobook,
                          child: const Text('Open AudioBook'),
                        ),
                        TextButton(
                          onPressed: _openAudiobookUntitledChapter,
                          child: const Text('Open AudioBook NoTitle'),
                        ),
                        TextButton(
                          onPressed: _openUnreachableAudiobook,
                          child: const Text('Open AudioBook BadUrl'),
                        ),
                        TextButton(
                          onPressed: _openMidStreamFailAudiobook,
                          child: const Text('Open AudioBook BadStream'),
                        ),
                        TextButton(
                          onPressed: _openCbz,
                          child: const Text('Open CBZ'),
                        ),
                        TextButton(
                          onPressed: _openDivina,
                          child: const Text('Open DIVINA'),
                        ),
                        TextButton(
                          onPressed: _openWebPub,
                          child: const Text('Open WebPub'),
                        ),
                        TextButton(
                          onPressed: _loadOnly,
                          child: const Text('Load Only'),
                        ),
                        TextButton(
                          onPressed: _close,
                          child: const Text('Close'),
                        ),
                        TextButton(
                          onPressed: _flureadium.goLeft,
                          child: const Text('←'),
                        ),
                        TextButton(
                          onPressed: _flureadium.goRight,
                          child: const Text('→'),
                        ),
                        TextButton(
                          onPressed: _flureadium.skipToPrevious,
                          child: const Text('Skip Prev'),
                        ),
                        TextButton(
                          onPressed: _flureadium.skipToNext,
                          child: const Text('Skip Next'),
                        ),
                        TextButton(
                          onPressed: _dartSkipToPrevious,
                          child: const Text('DartSkip-'),
                        ),
                        TextButton(
                          onPressed: _dartSkipToNext,
                          child: const Text('DartSkip+'),
                        ),
                        if (pub != null)
                          TextButton(
                            onPressed: _goToSaved,
                            child: const Text('Go To Saved'),
                          ),
                        if (pub != null)
                          TextButton(
                            onPressed: _goToFirstChapter,
                            child: const Text('Ch.1'),
                          ),
                        TextButton(
                          onPressed: _setNightPreferences,
                          child: const Text('Night'),
                        ),
                        TextButton(
                          onPressed: _addHighlight,
                          child: const Text('Highlight'),
                        ),
                        TextButton(
                          onPressed: _showSystemVoices,
                          child: const Text('OS TTS'),
                        ),
                        TextButton(
                          onPressed: _toggleTts,
                          child: Text(_ttsEnabled ? 'TTS Off' : 'TTS On'),
                        ),
                        if (_ttsEnabled && _ttsPlaybackState != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'TTS: ${_ttsPlaybackState!.name}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        if (_ttsEnabled &&
                            _ttsPlaybackState == TimebasedState.playing)
                          TextButton(
                            onPressed: _ttsPause,
                            child: const Text('Pause TTS'),
                          ),
                        if (_ttsEnabled &&
                            _ttsPlaybackState == TimebasedState.paused)
                          TextButton(
                            onPressed: _ttsResume,
                            child: const Text('Resume TTS'),
                          ),
                        if (_ttsErrorType == TtsErrorType.languageMissingData)
                          TextButton(
                            onPressed: _installVoice,
                            child: const Text('Install Voice'),
                          ),
                        if (_ttsEnabled && _voices.isNotEmpty)
                          TextButton(
                            onPressed: _nextVoice,
                            child: Text(
                              'Voice ${_voiceIndex + 1}/${_voices.length}',
                            ),
                          ),
                        if (_ttsEnabled) ...[
                          TextButton(
                            onPressed: _flureadium.previous,
                            child: const Text('Prev Sentence'),
                          ),
                          TextButton(
                            onPressed: _flureadium.next,
                            child: const Text('Next Sentence'),
                          ),
                        ],
                        if (_ttsEnabled)
                          SizedBox(
                            width: 200,
                            child: Slider(
                              value: _ttsSpeed,
                              min: 0.5,
                              max: 2.0,
                              divisions: 6,
                              label: '${_ttsSpeed}x',
                              onChanged: (value) async {
                                setState(() => _ttsSpeed = value);
                                if (_ttsEnabled) {
                                  await _flureadium.ttsSetPreferences(
                                    TTSPreferences(speed: value),
                                  );
                                }
                              },
                            ),
                          ),
                        TextButton(
                          onPressed: _toggleAudio,
                          child: Text(
                            !_audioEnabled
                                ? 'Audio Play'
                                : _audioPaused
                                ? 'Audio Resume'
                                : 'Audio Pause',
                          ),
                        ),
                        if (_audioEnabled)
                          TextButton(
                            onPressed: _seekForward,
                            child: const Text('+30s'),
                          ),
                        if (_audioEnabled)
                          TextButton(
                            onPressed: _previousChapter,
                            child: const Text('Audio Prev Chapter'),
                          ),
                        if (_audioEnabled)
                          TextButton(
                            onPressed: _nextChapter,
                            child: const Text('Audio Next Chapter'),
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
}
