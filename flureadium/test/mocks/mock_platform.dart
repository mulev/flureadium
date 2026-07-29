import 'dart:async';
import 'dart:typed_data';

import 'package:flureadium/flureadium.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A complete mock implementation of [FlureadiumPlatform] for testing.
///
/// This mock tracks all method calls for verification and provides
/// configurable return values for each method.
class MockFlureadiumPlatform
    with MockPlatformInterfaceMixin
    implements FlureadiumPlatform {
  /// List of method calls made to this mock for verification.
  final List<MockMethodCall> calls = [];

  /// Clears all recorded method calls.
  void clearCalls() => calls.clear();

  // Configurable mock data
  Publication? mockPublication;
  Locator? mockLocator;
  String? mockLinkContent;
  List<ReaderTTSVoice> mockVoices = [];
  bool mockGoToLocatorResult = true;
  Uint8List? mockRenderFirstPageResult;
  Uint8List? mockExtractPageThumbnailResult;

  // Stream controllers for testing
  final StreamController<ReadiumReaderStatus> _readerStatusController =
      StreamController<ReadiumReaderStatus>.broadcast();
  final StreamController<Locator> _textLocatorController =
      StreamController<Locator>.broadcast();
  final StreamController<ReadiumTimebasedState> _timebasedStateController =
      StreamController<ReadiumTimebasedState>.broadcast();
  final StreamController<ReadiumError> _errorController =
      StreamController<ReadiumError>.broadcast();

  /// Emits a reader status event for testing.
  void emitReaderStatus(ReadiumReaderStatus status) =>
      _readerStatusController.add(status);

  /// Emits a text locator event for testing.
  void emitTextLocator(Locator locator) => _textLocatorController.add(locator);

  /// Emits a timebased player state event for testing.
  void emitTimebasedState(ReadiumTimebasedState state) =>
      _timebasedStateController.add(state);

  /// Emits an error event for testing.
  void emitError(ReadiumError error) => _errorController.add(error);

  /// Dispose all stream controllers.
  void dispose() {
    _readerStatusController.close();
    _textLocatorController.close();
    _timebasedStateController.close();
    _errorController.close();
  }

  /// Creates a default test publication.
  Publication get defaultPublication => Publication(
    links: [],
    metadata: Metadata(
      localizedTitle: LocalizedString.fromStrings({'en': 'Test Book'}),
    ),
    readingOrder: [],
  );

  // Platform interface properties
  @override
  ReadiumReaderWidgetInterface? currentReaderWidget;

  @override
  EPUBPreferences? defaultPreferences;

  @override
  PDFPreferences? defaultPdfPreferences;

  @override
  ReaderNavigationConfig? defaultNavigationConfig;

  // Publication Management
  @override
  Future<void> setCustomHeaders(Map<String, String> headers) async {
    calls.add(MockMethodCall('setCustomHeaders', {'headers': headers}));
  }

  @override
  void setDefaultPreferences(EPUBPreferences preferences) {
    calls.add(
      MockMethodCall('setDefaultPreferences', {'preferences': preferences}),
    );
    defaultPreferences = preferences;
  }

  @override
  void setDefaultPdfPreferences(PDFPreferences preferences) {
    calls.add(
      MockMethodCall('setDefaultPdfPreferences', {'preferences': preferences}),
    );
    defaultPdfPreferences = preferences;
  }

  @override
  Future<Publication> loadPublication(String pubUrl) async {
    calls.add(MockMethodCall('loadPublication', {'pubUrl': pubUrl}));
    return mockPublication ?? defaultPublication;
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    calls.add(MockMethodCall('openPublication', {'pubUrl': pubUrl}));
    return mockPublication ?? defaultPublication;
  }

  @override
  Future<void> closePublication() async {
    calls.add(MockMethodCall('closePublication'));
  }

  @override
  Future<String?> getLinkContent(Link link) async {
    calls.add(MockMethodCall('getLinkContent', {'link': link}));
    return mockLinkContent;
  }

  // Navigation
  @override
  Future<void> goLeft() async {
    calls.add(MockMethodCall('goLeft'));
  }

  @override
  Future<void> goRight() async {
    calls.add(MockMethodCall('goRight'));
  }

  @override
  Future<void> skipToNext() async {
    calls.add(MockMethodCall('skipToNext'));
  }

  @override
  Future<void> skipToPrevious() async {
    calls.add(MockMethodCall('skipToPrevious'));
  }

  @override
  Future<bool> goToLocator(Locator locator) async {
    calls.add(MockMethodCall('goToLocator', {'locator': locator}));
    return mockGoToLocatorResult;
  }

  // Preferences
  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    calls.add(
      MockMethodCall('setEPUBPreferences', {'preferences': preferences}),
    );
  }

  @override
  Future<void> setNavigationConfig(ReaderNavigationConfig config) async {
    calls.add(MockMethodCall('setNavigationConfig', {'config': config}));
    defaultNavigationConfig = config;
  }

  @override
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) async {
    calls.add(
      MockMethodCall('applyDecorations', {
        'id': id,
        'decorations': decorations,
      }),
    );
  }

  @override
  Future<void> setDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) async {
    calls.add(
      MockMethodCall('setDecorationStyle', {
        'utteranceDecoration': utteranceDecoration,
        'rangeDecoration': rangeDecoration,
      }),
    );
  }

  // Common Playback API
  @override
  Future<void> play(Locator? fromLocator) async {
    calls.add(MockMethodCall('play', {'fromLocator': fromLocator}));
  }

  @override
  Future<void> stop() async {
    calls.add(MockMethodCall('stop'));
  }

  @override
  Future<void> pause() async {
    calls.add(MockMethodCall('pause'));
  }

  @override
  Future<void> resume() async {
    calls.add(MockMethodCall('resume'));
  }

  @override
  Future<void> next() async {
    calls.add(MockMethodCall('next'));
  }

  @override
  Future<void> previous() async {
    calls.add(MockMethodCall('previous'));
  }

  // TTS API
  @override
  Future<void> ttsEnable(
    TTSPreferences? preferences, {
    Locator? fromLocator,
  }) async {
    calls.add(
      MockMethodCall('ttsEnable', {
        'preferences': preferences,
        'fromLocator': fromLocator,
      }),
    );
  }

  @override
  Future<bool> ttsCanSpeak() async {
    calls.add(MockMethodCall('ttsCanSpeak'));
    return true;
  }

  @override
  Future<void> ttsRequestInstallVoice() async {
    calls.add(MockMethodCall('ttsRequestInstallVoice'));
  }

  @override
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() async {
    calls.add(MockMethodCall('ttsGetAvailableVoices'));
    return mockVoices;
  }

  @override
  Future<List<ReaderTTSVoice>> ttsGetSystemVoices() async {
    calls.add(MockMethodCall('ttsGetSystemVoices'));
    return mockVoices;
  }

  @override
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) async {
    calls.add(
      MockMethodCall('ttsSetVoice', {
        'voiceIdentifier': voiceIdentifier,
        'forLanguage': forLanguage,
      }),
    );
  }

  @override
  Future<void> ttsSetPreferences(TTSPreferences preferences) async {
    calls.add(
      MockMethodCall('ttsSetPreferences', {'preferences': preferences}),
    );
  }

  // Audiobook API
  @override
  Future<void> audioEnable({
    AudioPreferences? prefs,
    Locator? fromLocator,
  }) async {
    calls.add(
      MockMethodCall('audioEnable', {
        'prefs': prefs,
        'fromLocator': fromLocator,
      }),
    );
  }

  @override
  Future<void> audioSetPreferences(AudioPreferences prefs) async {
    calls.add(MockMethodCall('audioSetPreferences', {'prefs': prefs}));
  }

  @override
  Future<void> audioSeekBy(Duration offset) async {
    calls.add(MockMethodCall('audioSeekBy', {'offset': offset}));
  }

  @override
  Future<Uint8List?> renderFirstPage(
    String pubUrl, {
    int maxWidth = 600,
    int maxHeight = 800,
  }) async {
    calls.add(
      MockMethodCall('renderFirstPage', {
        'pubUrl': pubUrl,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
      }),
    );
    return mockRenderFirstPageResult;
  }

  @override
  Future<Uint8List?> extractPageThumbnail(
    String href,
    int maxHeight,
    int quality,
  ) async {
    calls.add(
      MockMethodCall('extractPageThumbnail', {
        'href': href,
        'maxHeight': maxHeight,
        'quality': quality,
      }),
    );
    return mockExtractPageThumbnailResult;
  }

  // State Streams
  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged =>
      _readerStatusController.stream;

  @override
  Stream<Locator> get onTextLocatorChanged => _textLocatorController.stream;

  @override
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged =>
      _timebasedStateController.stream;

  @override
  Stream<ReadiumError> get onErrorEvent => _errorController.stream;

  // Car content provider registration

  /// The provider passed to the last [registerCarContentProvider], or null.
  CarContentProvider? registeredCarProvider;

  /// The strings passed to the last [registerCarContentProvider], or null.
  CarContentStrings? registeredCarStrings;

  @override
  void registerCarContentProvider(
    CarContentProvider provider, {
    required CarContentStrings strings,
  }) {
    registeredCarProvider = provider;
    registeredCarStrings = strings;
    calls.add(MockMethodCall('registerCarContentProvider'));
  }

  @override
  void unregisterCarContentProvider() {
    registeredCarProvider = null;
    registeredCarStrings = null;
    calls.add(MockMethodCall('unregisterCarContentProvider'));
  }

  @override
  void refreshCarContent() {
    calls.add(MockMethodCall('refreshCarContent'));
  }

  // Verification helpers

  /// Returns true if a method with the given name was called.
  bool wasCalled(String methodName) =>
      calls.any((call) => call.method == methodName);

  /// Returns the number of times a method was called.
  int callCount(String methodName) =>
      calls.where((call) => call.method == methodName).length;

  /// Returns the arguments of the last call to the given method.
  Map<String, dynamic>? lastCallArgs(String methodName) {
    final matchingCalls = calls
        .where((call) => call.method == methodName)
        .toList();
    return matchingCalls.isEmpty ? null : matchingCalls.last.arguments;
  }

  /// Returns all calls to the given method.
  List<MockMethodCall> callsTo(String methodName) =>
      calls.where((call) => call.method == methodName).toList();
}

/// Represents a method call made to the mock platform.
class MockMethodCall {
  MockMethodCall(this.method, [this.arguments = const {}]);

  final String method;
  final Map<String, dynamic> arguments;

  @override
  String toString() => 'MockMethodCall($method, $arguments)';
}
