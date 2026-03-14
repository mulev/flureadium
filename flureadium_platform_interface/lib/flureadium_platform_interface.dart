// Copyright 2021 Mantano (BSD 3-Clause, see LICENSE.Iridium)
// Copyright 2024-2025 Notalib (LGPL v3)
// Copyright 2025-2026 mulev (LGPL v3)
// See LICENSE for details.

import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_flureadium.dart';
import 'src/index.dart';

export 'src/index.dart';

/// The interface that implementations of Flureadium must implement.
///
/// Platform implementations should extend this class rather than implement it as `Flureadium`
/// does not consider newly added methods to be breaking changes. Extending this class
/// (using `extends`) ensures that the subclass will get the default implementation, while
/// platform implementations that `implements` this interface will be broken by newly added
/// [FlureadiumPlatform] methods.
abstract class FlureadiumPlatform extends PlatformInterface {
  /// Constructs a FlureadiumPlatform.
  FlureadiumPlatform() : super(token: _token);

  static final Object _token = Object();
  static FlureadiumPlatform _instance = MethodChannelFlureadium();
  static FlureadiumPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [FlureadiumPlatform] when they register themselves.
  static set instance(final FlureadiumPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  ReadiumReaderWidgetInterface? currentReaderWidget;
  EPUBPreferences? defaultPreferences;
  PDFPreferences? defaultPdfPreferences;
  ReaderNavigationConfig? defaultNavigationConfig;

  Future<void> setCustomHeaders(Map<String, String> headers) =>
      throw UnimplementedError(
        'setCustomHeaders(headers) has not been implemented.',
      );

  void setDefaultPreferences(EPUBPreferences preferences) {
    defaultPreferences = preferences;
  }

  void setDefaultPdfPreferences(PDFPreferences preferences) {
    defaultPdfPreferences = preferences;
  }

  /// Load publication manifest from URL, which is usually a packaged ebook or direct URL to a manifest.
  /// This will NOT store a reference to the Publication and is purely meant to be used for fetching metadata/manifest
  /// for multiple books.
  Future<Publication> loadPublication(String pubUrl) =>
      throw UnimplementedError(
        'loadPublication(pubUrl) has not been implemented.',
      );

  /// Opens a publication from a URL and prepares it for reading or playback.
  /// If the URL has not already been loaded, it will implicitly do this.
  Future<Publication> openPublication(String pubUrl) =>
      throw UnimplementedError(
        'openPublication(pubUrl) has not been implemented.',
      );

  /// Close the currently open publication and its related reader or playback ressources.
  Future<void> closePublication() =>
      throw UnimplementedError('closePublication() has not been implemented.');

  /// Retrieves the content of a given link in the current Publication as a string.
  Future<String?> getLinkContent(final Link link);

  /// Navigate left/backwards visually in the current publication renderer.
  Future<void> goLeft() =>
      throw UnimplementedError('goLeft() has not been implemented.');

  /// Navigate right/forwards visually in the current publication renderer.
  Future<void> goRight() =>
      throw UnimplementedError('goRight() has not been implemented.');

  /// Skip to next chapter in the current publication.
  Future<void> skipToNext() =>
      throw UnimplementedError('skipToNext() has not been implemented.');

  /// Skip to previous chapter in the current publication.
  Future<void> skipToPrevious() =>
      throw UnimplementedError('skipToPrevious() has not been implemented.');

  /// Sets the default EPUB rendering preferences and updates preferences for the ReaderWidgetView.
  Future<void> setEPUBPreferences(EPUBPreferences preferences) =>
      throw UnimplementedError('applyDecorations() has not been implemented');

  /// Sets navigation config and forwards it to the active reader widget.
  Future<void> setNavigationConfig(ReaderNavigationConfig config) =>
      throw UnimplementedError(
        'setNavigationConfig() has not been implemented',
      );

  /// Apply reader decorations (highlights, bookmarks, etc.) to the current ReaderWidgetView.
  /// The `id` parameter is used to identify the decoration set.
  /// The `decorations` parameter is a list of [ReaderDecoration] objects to apply.
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) => throw UnimplementedError('applyDecorations() has not been implemented');

  /// Go directly to the given [Locator] in the publication, whether visual or audio.
  Future<bool> goToLocator(Locator locator) =>
      throw UnimplementedError('goToLocator() has not been implemented.');

  // COMMON PLAYBACK API - BEGIN
  /// Play the publication from the given locator, or resume if null.
  Future<void> play(Locator? fromLocator) =>
      throw UnimplementedError('play() has not been implemented');

  /// Stop playback.
  Future<void> stop() =>
      throw UnimplementedError('stop() has not been implemented');

  /// Pause playback.
  Future<void> pause() =>
      throw UnimplementedError('pause() has not been implemented');

  /// Resume playback.
  Future<void> resume() =>
      throw UnimplementedError('resume() has not been implemented');

  /// Skip to next logical item during playback. For audiobooks this is the default seek interval. For TTS this is the next paragraph.
  Future<void> next() =>
      throw UnimplementedError('next() has not been implemented');

  /// Skip to previous logical item during playback. For audiobooks this is the default seek interval. For TTS this is the previous paragraph.
  Future<void> previous() =>
      throw UnimplementedError('previous() has not been implemented');
  // COMMON PLAYBACK API - END

  // TTS API - BEGIN
  /// Enabled TTS playback for the current publication with optional preferences.
  Future<void> ttsEnable(TTSPreferences? preferences) =>
      throw UnimplementedError('ttsEnable() has not been implemented');

  /// Check whether TTS can speak the current publication's language.
  Future<bool> ttsCanSpeak() =>
      throw UnimplementedError('ttsCanSpeak() has not been implemented');

  /// Request the system to install missing TTS voice data.
  Future<void> ttsRequestInstallVoice() => throw UnimplementedError(
    'ttsRequestInstallVoice() has not been implemented',
  );

  /// Get the list of available TTS voices on the platform.
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() =>
      throw UnimplementedError(
        'ttsGetAvailableVoices() has not been implemented',
      );

  /// Set the TTS voice by its identifier, optionally for a specific language.
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) =>
      throw UnimplementedError('ttsSetVoice() has not been implemented');

  /// Set the decoration styles for utterances and ranges.
  Future<void> setDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) =>
      throw UnimplementedError('setDecorationStyle() has not been implemented');

  /// Change the TTS preferences such as speed, pitch, and volume.
  Future<void> ttsSetPreferences(TTSPreferences preferences) =>
      throw UnimplementedError('ttsSetPreferences() has not been implemented');
  // TTS API - END

  // AUDIOBOOK API - BEGIN
  /// Enable audiobook playback with optional preferences and starting from an optional locator.
  Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator}) =>
      throw UnimplementedError('audioEnable() has not been implemented');

  /// Change the audiobook playback preferences such as speed and seek interval.
  Future<void> audioSetPreferences(AudioPreferences prefs) =>
      throw UnimplementedError(
        'audioSetPreferences() has not been implemented',
      );

  /// Seek in audio playback relative to current position by the given offset in seconds. Positive values seek forward, negative values seek backward.
  /// This is an alternative to next/previous which seeks by a fixed interval.
  Future<void> audioSeekBy(Duration offset) =>
      throw UnimplementedError('seekInAudio() has not been implemented');
  // AUDIOBOOK API - END

  /// Renders the first page of a PDF publication as a JPEG image.
  /// Returns the image bytes, or null if rendering fails.
  /// [pubUrl] is the file path or URL to the PDF.
  /// [maxWidth] and [maxHeight] constrain the output dimensions.
  Future<Uint8List?> renderFirstPage(
    String pubUrl, {
    int maxWidth = 600,
    int maxHeight = 800,
  }) => throw UnimplementedError('renderFirstPage() has not been implemented.');

  // State stream for reader status changes
  Stream<ReadiumReaderStatus> get onReaderStatusChanged {
    throw UnimplementedError('onReaderStatus stream has not been implemented.');
  }

  // State stream for text/visual position. Usually will be the top of the current page (firstVisibleLocator in Readium).
  Stream<Locator> get onTextLocatorChanged {
    throw UnimplementedError(
      'onTextLocatorChanged stream has not been implemented.',
    );
  }

  // State stream for audio position. Will be as near as possible to the currently spoken or played audio.
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged {
    throw UnimplementedError(
      'onTimebasedPlayerStateChanged stream has not been implemented.',
    );
  }

  /// State stream for error events occurring in the reader or playback.
  Stream<ReadiumError> get onErrorEvent {
    throw UnimplementedError('onErrorEvent stream has not been implemented.');
  }
}
