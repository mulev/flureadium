import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flureadium/flureadium.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio_stream_fixtures.dart';
import 'car_stub.dart';

const _defaultInitialAsset = String.fromEnvironment(
  'FLUREADIUM_INITIAL_ASSET',
  defaultValue: 'assets/pubs/moby_dick.epub',
);

void main({String initialAsset = _defaultInitialAsset}) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ExampleApp(initialAsset: initialAsset));
}

/// Dedicated entrypoint for the app-scoped headless car engine (car bridge ADR,
/// STAGE-1). CarPlay boots this instead of the reader UI: it registers the stub
/// car provider so the `dev.mulev.flureadium/car` channel answers browse and
/// play from a cold, UI-less process.
@pragma('vm:entry-point')
void carMain() {
  WidgetsFlutterBinding.ensureInitialized();
  Flureadium().registerCarContentProvider(
    StubCarContentProvider(),
    strings: StubCarContentProvider.strings,
  );
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
  // The first position this publication reported, latched once per open and
  // cleared by _resetPublicationLatches. Deliberately not kept in step with
  // _locator: "Go To Saved" is only worth tapping if it can navigate somewhere
  // the reader is not, so the listener latches with `??=`, never `=`.
  Locator? _savedLocator;
  // The title the last loadPublication returned, or '' before any load.
  String _loadedTitle = '';
  ReadiumTimebasedState? _timebasedState;
  // Bumped each time a publication finishes opening (after openPublication
  // returns). Integration tests read this before tapping an "Open ..." button
  // and poll until it increments, so they wait exactly until the new
  // publication is loaded instead of a fixed duration.
  int _openGeneration = 0;
  // How many locators the text-locator stream has delivered since this
  // publication opened, cleared by _resetPublicationLatches. A count rather
  // than a value because the values repeat: only a number that must rise
  // proves a delivery arrived when the href it carries is the one already
  // latched.
  int _locatorEvents = 0;
  bool _endedSeen = false;
  bool _controlsVisible = true;
  // How many taps the native navigator has reported since this publication
  // opened, cleared by _resetPublicationLatches, and the position the last one
  // carried. A count rather than a flag, for the same reason as
  // _locatorEvents: only a number that must rise can tell one report from two,
  // and a double listener registration is the failure the tap wiring has to be
  // proven free of. The position is rendered as text so a units mismatch
  // between the platforms is visible instead of silent.
  int _tapEvents = 0;
  Offset? _lastTap;
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
  // Latches the last failure from an open path so integration tests can assert
  // that an open succeeded, rather than that some reader widget is on screen.
  // Cleared by _runOpen on any success and again by _resetPublicationLatches:
  // an error left latched past the next good open would fail a later test for
  // a fault that is already over. _runOpen is the one that makes that true for
  // _loadOnly, which latches failures but never reaches the reset.
  String _lastOpenError = '';
  // Local server backing the 'Open AudioBook BadStream' action: serves a WAV
  // whose Content-Length promises the full clip but drops the socket after a
  // partial body, producing a mid-stream failure both audio engines observe.
  HttpServer? _badStreamServer;
  StreamedAudioServer? _streamedServer;
  // Latched by the streamed-audio fixture when AVFoundation cancels an
  // in-flight range request (client disconnect mid-response); lets the
  // integration test confirm the benign-cancellation path actually ran.
  bool _cancelledStreamDisconnectSeen = false;
  // Latches the last reader status so integration tests can assert the reader
  // reported readiness. For an audio-only publication this is the only
  // readiness signal there is: the host has no navigator to report a page.
  String _readerStatus = '';
  // Bumped by 'Remount Reader' to change the reader widget's key. The plugin
  // rebuilds the native view by itself when it receives a different
  // Publication instance, but not when the instance is unchanged, which is
  // exactly the case 'Close Native Only' sets up.
  int _readerMountGeneration = 0;

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
  // onReady fires. No polling, no timers. Tests against this app still pump in
  // bounded steps rather than pumpAndSettle: the load cover's spinner keeps
  // scheduling frames until the reader reports `ready`.
  void _subscribeToChannels() {
    _statusSub?.cancel();
    _locatorSub?.cancel();
    _errorSub?.cancel();
    _statusSub = _flureadium.onReaderStatusChanged.listen((s) {
      debugPrint('ReaderStatus: $s');
      if (!mounted) return;
      setState(() => _readerStatus = s.name);
    });
    _locatorSub = _flureadium.onTextLocatorChanged.listen(
      (l) => setState(() {
        _locator = l;
        _savedLocator ??= l;
        // Monotonic within one publication: a delivery that repeats the href
        // already latched still moves this, which is what lets an integration
        // test prove a subscribe-time answer arrived.
        _locatorEvents++;
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
    _streamedServer?.close();
    super.dispose();
  }

  /// Runs one open path, recording any failure where a test can see it and
  /// clearing that record when one succeeds.
  ///
  /// Every opener used to carry its own `catch (e) { debugPrint(...) }`, which
  /// meant a failed open left no trace in the widget tree — a test could only
  /// observe it by noticing a reader that never appeared, and any reader
  /// already on screen hid even that. Sixteen copies of that block is also how
  /// the omission stayed invisible: there was no single place to fix.
  ///
  /// Clearing on success here rather than relying on `_resetPublicationLatches`
  /// is what makes "empty means the last attempt succeeded" true for every
  /// wrapped path. `_loadOnly` loads without opening, so it never reaches that
  /// reset — leaving it out would let a failed open stay latched across a
  /// successful load and fail a later test for a fault that was already over.
  Future<void> _runOpen(String label, Future<void> Function() body) async {
    try {
      await body();
      if (!mounted || _lastOpenError.isEmpty) return;
      setState(() => _lastOpenError = '');
    } catch (e) {
      debugPrint('$label error: $e');
      if (!mounted) return;
      setState(() => _lastOpenError = '$label: $e');
    }
  }

  Future<void> _openEpub() => _runOpen(
    'openEpub',
    () => _openPublicationAsset('assets/pubs/moby_dick.epub'),
  );

  Future<void> _openCbz() => _runOpen(
    'openCbz',
    () => _openPublicationAsset('assets/pubs/sample_comic.cbz'),
  );

  Future<void> _openDivina() => _runOpen(
    'openDivina',
    () => _openPublicationAsset('assets/pubs/sample_visual.divina'),
  );

  Future<void> _openTapTargets() => _runOpen(
    'openTapTargets',
    () => _openPublicationAsset('assets/pubs/tap_targets.epub'),
  );

  Future<void> _openFixedLayout() => _runOpen(
    'openFixedLayout',
    () => _openPublicationAsset('assets/pubs/fixed_layout.epub'),
  );

  Future<void> _openAudiobook() => _runOpen(
    'openAudiobook',
    () => _openPublicationAsset('assets/pubs/38533.audiobook'),
  );

  Future<void> _openAudiobookUntitledChapter() => _runOpen(
    'openAudiobookUntitledChapter',
    () => _openPublicationAsset('assets/pubs/untitled_chapter.audiobook'),
  );

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
    await _runOpen(
      'openUnreachableAudiobook',
      () => _openManifest(manifest, 'unreachable'),
    );
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
    final header = wavHeader(dataSize: fullDataSize, sampleRate: sampleRate);
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
    await _runOpen(
      'openMidStreamFailAudiobook',
      () => _openManifest(manifest, 'truncated'),
    );
  }

  Future<void> _openStreamedAudiobook() async {
    // A complete, valid, range-seekable WAV served by a local server that
    // trickles the tail of each range so a read-ahead request is in flight
    // during playback. Seeking supersedes it, producing the benign
    // HTTPError.cancelled the iOS reporter must swallow (see the
    // 'seeking a streamed audiobook does not surface a spurious cancelled
    // error' integration test).
    await _streamedServer?.close();
    // 10 minutes, so the test's repeated +30s seeks stay well inside the track
    // (each seek supersedes the in-flight read-ahead request without ending it).
    final server = await StreamedAudioServer.startSilentWav(seconds: 600);
    server.onClientCancel = () {
      if (mounted) setState(() => _cancelledStreamDisconnectSeen = true);
    };
    _streamedServer = server;

    final manifest =
        '''
{
  "@context": "https://readium.org/webpub-manifest/context.jsonld",
  "metadata": {
    "@type": "http://schema.org/Audiobook",
    "conformsTo": "https://readium.org/webpub-manifest/profiles/audiobook",
    "title": "Streamed Audio",
    "duration": 600
  },
  "links": [
    { "rel": "self", "href": "${server.url}", "type": "application/audiobook+json" }
  ],
  "readingOrder": [
    { "href": "${server.url}", "type": "audio/wav", "duration": 600 }
  ]
}
''';
    await _runOpen(
      'openStreamedAudiobook',
      () => _openManifest(manifest, 'streamed'),
    );
  }

  /// Opens [path] and swaps the result in as the current publication.
  ///
  /// The one place `_publication` is assigned by an open, so the latch reset
  /// below cannot be forgotten on a new open path — every opener funnels here.
  Future<void> _openPublicationPath(String path) async {
    final pub = await _flureadium.openPublication(path);
    if (!mounted) return;
    setState(() {
      _publication = pub;
      _resetPublicationLatches();
    });
  }

  Future<void> _openPublicationAsset(String assetPath) async {
    await _openPublicationPath(await _extractAsset(assetPath));
  }

  /// Writes [manifest] to a temp file named `<millis>_[name].json` and opens
  /// it. Backs the three audiobook fixtures whose manifest points at a local
  /// server, so the URL is only known at runtime and cannot ship as an asset.
  Future<void> _openManifest(String manifest, String name) async {
    final tmp = _tempFile('$name.json');
    await tmp.writeAsString(manifest);
    await _openPublicationPath(tmp.path);
  }

  /// Clears every latch that describes the publication being replaced. Called
  /// from inside each open path's `setState`.
  ///
  /// Each of these is a fact about one publication, so leaving any of them set
  /// lets an integration test poll a stale value and pass before the new
  /// reader has reported anything. That is how a swapped-in audiobook kept
  /// showing the previous EPUB's page, and how a `ready` from the outgoing
  /// view stood in for the incoming one before flureadium-5wu.
  ///
  /// The seven open paths used to clear overlapping subsets of this list. The
  /// union is applied everywhere now: no latch here outlives its publication,
  /// so there is no case where clearing one is wrong.
  void _resetPublicationLatches() {
    // The bar is chrome, not publication state, but it has to come back with
    // each open: every latch below except the tap pair lives inside it (those
    // two sit outside on purpose, see the stack), so a publication that opens
    // with the bar down reports nothing a test can read.
    _controlsVisible = true;
    _openGeneration++;
    _readerStatus = '';
    _locator = null;
    _locatorEvents = 0;
    _tapEvents = 0;
    _lastTap = null;
    _savedLocator = null;
    _loadedTitle = '';
    _lastAudioError = '';
    _lastOpenError = '';
    _cancelledStreamDisconnectSeen = false;
    _endedSeen = false;
    _ttsEnabled = false;
    _lastTtsLocator = null;
    _readerLocatorAtTtsDisable = null;
    _audioEnabled = false;
    _audioPaused = false;
    _voices = [];
    _voiceIndex = 0;
  }

  Future<void> _openWebPub() => _runOpen('openWebPub', () async {
    await _flureadium.setCustomHeaders({'X-Example': 'flureadium-demo'});
    await _openPublicationPath(
      'https://readium.org/webpub-manifest/examples/MobyDick/manifest.json',
    );
  });

  /// A temp file named `<millis>_[name]`. The timestamp keeps each open
  /// distinct: reopening the same fixture must not hand the reader a path it
  /// may still have cached from the previous open.
  File _tempFile(String name) => File(
    '${Directory.systemTemp.path}/${DateTime.now().millisecondsSinceEpoch}_$name',
  );

  Future<String> _extractAsset(String assetPath) async {
    if (kIsWeb) {
      return Uri.base.resolve(assetPath).toString();
    }
    final bytes = await rootBundle.load(assetPath);
    final tmp = _tempFile(assetPath.split('/').last);
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

  /// Closes the publication natively while the Dart reader widget stays
  /// mounted, so the next remount asks native to host a publication that is no
  /// longer open. Reproduces a host app mounting the reader after a close —
  /// the enable failure that used to kill the Android process.
  Future<void> _closeNativeOnly() => _flureadium.closePublication();

  /// Replaces the reader element so native `init` runs again over a
  /// publication Dart still holds. `_publication` is untouched, so
  /// `ReadiumReaderWidget.didUpdateWidget` returns early and only the key
  /// change reaches native.
  void _remountReader() => setState(() => _readerMountGeneration++);

  /// Drops the latched locator and re-runs the subscription path, so the app
  /// becomes a fresh subscriber to a reader that is already open and already
  /// has a position. That is the same cancel-then-listen `onReady` performs
  /// after a publication swap, made reachable without one.
  void _resubscribeLocator() {
    setState(() => _locator = null);
    _subscribeToChannels();
  }

  Future<void> _setNightPreferences() => _flureadium.setEPUBPreferences(
    EPUBPreferences(
      fontFamily: 'Georgia',
      fontSize: 100,
      fontWeight: null,
      verticalScroll: false,
      backgroundColor: const Color(0xFF1A1A1A),
      textColor: const Color(0xFFE0E0E0),
    ),
  );

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
    setState(() => _ttsEnabled = true);
    await _flureadium.play(null);
    final voices = await _flureadium.ttsGetAvailableVoices();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _voiceIndex = 0;
    });
  }

  Future<void> _ttsPause() => _flureadium.pause();

  Future<void> _ttsResume() => _flureadium.resume();

  Future<void> _installVoice() => _flureadium.ttsRequestInstallVoice();

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

  // Keeps its own try/catch rather than routing through _runOpen: a failed
  // audioEnable is reported to the user as a SnackBar, not latched as text.
  Future<void> _toggleAudio() async {
    if (_audioEnabled && !_audioPaused) {
      await _flureadium.pause();
      if (!mounted) return;
      setState(() => _audioPaused = true);
      return;
    }
    if (_audioEnabled && _audioPaused) {
      await _flureadium.resume();
      if (!mounted) return;
      setState(() => _audioPaused = false);
      return;
    }
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

  String get _audioButtonLabel {
    if (!_audioEnabled) return 'Audio Play';
    if (_audioPaused) return 'Audio Resume';
    return 'Audio Pause';
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

  Future<void> _openHierarchical() => _runOpen(
    'openHierarchical',
    () => _openPublicationAsset('assets/pubs/hierarchical_toc.epub'),
  );

  Future<void> _openFrontmatter() => _runOpen(
    'openFrontmatter',
    () => _openPublicationAsset('assets/pubs/frontmatter_toc.epub'),
  );

  Future<void> _openBacklinkChapter() => _runOpen(
    'openBacklinkChapter',
    () => _openPublicationAsset('assets/pubs/backlink_chapter.epub'),
  );

  Future<void> _dartSkipToNext() async =>
      FlureadiumPlatform.instance.currentReaderWidget?.skipToNext();

  Future<void> _dartSkipToPrevious() async =>
      FlureadiumPlatform.instance.currentReaderWidget?.skipToPrevious();

  Future<void> _loadOnly() => _runOpen('loadOnly', () async {
    final path = await _extractAsset('assets/pubs/moby_dick.epub');
    final pub = await _flureadium.loadPublication(path);
    if (!mounted) return;
    setState(() => _loadedTitle = pub.metadata.title);
  });

  /// One line of the control bar's debug readout.
  ///
  /// Integration and widget tests read these by [key] and compare `Text.data`
  /// verbatim, so [text] is spelled out at each call site rather than derived
  /// from the key: the string a test asserts on stays greppable in the source.
  Widget _latch(String key, String text) =>
      Text(text, key: Key(key), style: _latchStyle);

  static const _latchStyle = TextStyle(color: Colors.white70, fontSize: 10);

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
              key: ValueKey('reader-$_readerMountGeneration'),
              publication: pub,
              onTap: (position) {
                setState(() {
                  _tapEvents += 1;
                  _lastTap = position;
                  _controlsVisible = !_controlsVisible;
                });
              },
              onReady: _subscribeToChannels,
            )
          else
            const Center(child: CircularProgressIndicator()),
          // Readium shows no content until it reports `ready`; a host that wants
          // that window covered stacks its own cover. IgnorePointer so it only
          // paints — the reader below and the controls above stay hit-testable.
          // `error` and `closed` are terminal: no `ready` follows either, so a
          // cover left up there would sit over a dead reader forever. The
          // controls carry the status text that says which one happened.
          if (pub != null &&
              (_readerStatus.isEmpty || _readerStatus == 'loading'))
            const Positioned.fill(
              key: Key('reader-loading-cover'),
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          if (pub == null || _controlsVisible)
            Positioned(
              // Keyed so an integration test can tell whether the chrome is up:
              // this bar covers the reader's centre, so a tap aimed there would
              // hit these buttons instead of the publication.
              key: const Key('control-bar'),
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
                    _latch(
                      'open-generation',
                      'open-generation: $_openGeneration',
                    ),
                    _latch('locator-events', 'locator-events: $_locatorEvents'),
                    _latch(
                      'current-track',
                      'track: ${_timebasedState?.currentLocator?.locations?.position ?? '-'} '
                          '${_timebasedState?.currentLocator?.href ?? ''}',
                    ),
                    _latch(
                      'timebased-state',
                      'state: ${_timebasedState?.state.name ?? '-'}',
                    ),
                    _latch(
                      'timebased-position',
                      'pos: ${_timebasedState?.currentOffset?.inMilliseconds ?? -1} '
                          'dur: ${_timebasedState?.currentDuration?.inMilliseconds ?? -1}',
                    ),
                    _latch('ended-seen', 'ended-seen: $_endedSeen'),
                    _latch('audio-error', 'audio-error: $_lastAudioError'),
                    _latch('open-error', 'open-error: $_lastOpenError'),
                    _latch(
                      'publication-identifier',
                      'publication-identifier: '
                          '${_publication?.metadata.identifier ?? ''}',
                    ),
                    _latch('reader-status', 'reader-status: $_readerStatus'),
                    _latch(
                      'cancelled-stream-disconnect-seen',
                      'cancelled-stream-disconnect-seen: '
                          '$_cancelledStreamDisconnectSeen',
                    ),
                    _latch('locator_href', _locator?.href ?? ''),
                    _latch('saved_locator_href', _savedLocator?.href ?? ''),
                    _latch(
                      'locator_progression',
                      _locator?.locations?.progression?.toString() ?? '',
                    ),
                    _latch(
                      'locator_toc_fragment',
                      _locator?.locations?.tocFragment ?? '',
                    ),
                    _latch('loaded-title', 'loaded-title: $_loadedTitle'),
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
                          onPressed: _openFrontmatter,
                          child: const Text('Open Frontmatter'),
                        ),
                        TextButton(
                          onPressed: _openBacklinkChapter,
                          child: const Text('Open Backlink Chapter'),
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
                          onPressed: _openStreamedAudiobook,
                          child: const Text('Open AudioBook Streamed'),
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
                          onPressed: _openTapTargets,
                          child: const Text('Open Tap Targets'),
                        ),
                        TextButton(
                          onPressed: _openFixedLayout,
                          child: const Text('Open Fixed Layout'),
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
                        if (pub != null) ...[
                          TextButton(
                            onPressed: _goToSaved,
                            child: const Text('Go To Saved'),
                          ),
                          TextButton(
                            onPressed: _goToFirstChapter,
                            child: const Text('Ch.1'),
                          ),
                        ],
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
                          child: Text(_audioButtonLabel),
                        ),
                        if (_audioEnabled) ...[
                          TextButton(
                            onPressed: _seekForward,
                            child: const Text('+30s'),
                          ),
                          TextButton(
                            onPressed: _previousChapter,
                            child: const Text('Audio Prev Chapter'),
                          ),
                          TextButton(
                            onPressed: _nextChapter,
                            child: const Text('Audio Next Chapter'),
                          ),
                        ],
                        TextButton(
                          onPressed: _closeNativeOnly,
                          child: const Text('Close Native Only'),
                        ),
                        TextButton(
                          onPressed: _remountReader,
                          child: const Text('Remount Reader'),
                        ),
                        TextButton(
                          onPressed: _resubscribeLocator,
                          child: const Text('Resubscribe Locator'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          // Always visible: a tap flips _controlsVisible, so a tap latch inside
          // the control bar would unmount at the moment it finally has something
          // to report. The latches are wrapped in IgnorePointer — a latch that
          // swallowed the taps it exists to observe would report zero forever —
          // but the toggle beside them is deliberately hit-testable: it is the
          // only way back to the controls that does not depend on the native tap
          // working, which is exactly what the tests are proving.
          //
          // Last child of the stack is what delivers that. A Stack hit-tests in
          // reverse paint order, and the control bar above has no height cap: on
          // a short screen its Column is taller than the viewport, so as an
          // earlier sibling this block lost the tap aimed at it and the chrome
          // could never be taken down. That is what broke the tap suite on CI's
          // 682 dp emulator. Keep this block last.
          Positioned(
            top: 0,
            left: 0,
            child: ColoredBox(
              color: Colors.white70,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          key: const Key('tap-events'),
                          'tap-events: $_tapEvents',
                          style: const TextStyle(fontSize: 10),
                        ),
                        Text(
                          key: const Key('last-tap'),
                          _lastTap == null
                              ? ''
                              : '${_lastTap!.dx.toStringAsFixed(1)},${_lastTap!.dy.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('toggle-controls'),
                    onPressed: () =>
                        setState(() => _controlsVisible = !_controlsVisible),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'controls',
                      style: TextStyle(fontSize: 10),
                    ),
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
