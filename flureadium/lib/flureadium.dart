import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

export 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
export 'reader_widget_switch.dart';
export 'src/utils/navigation_helper.dart';
export 'src/utils/toc_matcher.dart';

/// Main entry point for the Flureadium plugin.
///
/// Provides a unified API for reading EPUB publications, playing audiobooks,
/// and using text-to-speech across all supported platforms.
///
/// ## Getting Started
///
/// ```dart
/// final flureadium = Flureadium();
///
/// // Open a publication
/// final publication = await flureadium.openPublication('file:///book.epub');
///
/// // Listen for position changes
/// flureadium.onTextLocatorChanged.listen((locator) {
///   print('Current position: ${locator.locations?.totalProgression}');
/// });
/// ```
///
/// ## Reading Modes
///
/// Flureadium supports multiple reading modes:
/// - **Visual reading**: Navigate through EPUB pages with [goLeft]/[goRight]
/// - **Text-to-speech**: Enable with [ttsEnable], control with [play]/[pause]
/// - **Audiobook**: Enable with [audioEnable] for pre-recorded audio
///
/// See also:
/// - [Publication] for the publication data model
/// - [Locator] for position tracking
/// - [EPUBPreferences] for visual customization
class Flureadium {
  /// Constructs a singleton instance of [Flureadium].
  ///
  /// This is a factory constructor that returns the same instance
  /// every time it is called.
  factory Flureadium() {
    _singleton ??= Flureadium._();
    return _singleton!;
  }

  Flureadium._();

  static Flureadium? _singleton;

  static FlureadiumPlatform get _platform {
    return FlureadiumPlatform.instance;
  }

  /// Sets custom HTTP headers for network requests.
  ///
  /// Use this to provide authentication tokens or other custom headers
  /// when loading remote publications.
  ///
  /// ```dart
  /// await flureadium.setCustomHeaders({'Authorization': 'Bearer token'});
  /// ```
  Future<void> setCustomHeaders(Map<String, String> headers) {
    return _platform.setCustomHeaders(headers);
  }

  /// Sets default EPUB preferences for all publications.
  ///
  /// These preferences will be applied when opening new publications
  /// unless overridden by [setEPUBPreferences].
  void setDefaultPreferences(EPUBPreferences preferences) {
    _platform.setDefaultPreferences(preferences);
  }

  /// Sets default PDF preferences for all PDF publications.
  ///
  /// These preferences will be applied when opening new PDF publications.
  void setDefaultPdfPreferences(PDFPreferences preferences) {
    _platform.setDefaultPdfPreferences(preferences);
  }

  /// Loads a publication without opening it in the reader.
  ///
  /// Returns the [Publication] metadata without displaying it.
  /// Use [openPublication] to both load and display a publication.
  Future<Publication> loadPublication(String pubUrl) {
    return _platform.loadPublication(pubUrl);
  }

  /// Opens a publication and prepares it for reading.
  ///
  /// The [pubUrl] can be a local file path (file://) or a remote URL.
  /// Returns the [Publication] metadata on success.
  ///
  /// Throws [ReadiumException] if the publication cannot be opened.
  ///
  /// ```dart
  /// final pub = await flureadium.openPublication('file:///path/to/book.epub');
  /// print('Opened: ${pub.metadata.title}');
  /// ```
  Future<Publication> openPublication(String pubUrl) {
    return _platform.openPublication(pubUrl).onError((err, _) {
      throw ReadiumException.fromError(err);
    });
  }

  /// Closes the currently open publication.
  ///
  /// Should be called when done reading to release resources.
  Future<void> closePublication() {
    return _platform.closePublication();
  }

  /// Stream of reader status changes.
  ///
  /// Emits [ReadiumReaderStatus] whenever the reader state changes.
  Stream<ReadiumReaderStatus> get onReaderStatusChanged =>
      _platform.onReaderStatusChanged;

  /// Stream of text locator changes during reading.
  ///
  /// Emits [Locator] whenever the reading position changes.
  /// Use this to save reading progress or update UI.
  ///
  /// ```dart
  /// flureadium.onTextLocatorChanged.listen((locator) {
  ///   saveProgress(locator);
  /// });
  /// ```
  Stream<Locator> get onTextLocatorChanged {
    return _platform.onTextLocatorChanged;
  }

  /// Stream of timebased player state changes.
  ///
  /// Emits [ReadiumTimebasedState] for audiobook playback or TTS,
  /// including current position and duration.
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged {
    return _platform.onTimebasedPlayerStateChanged;
  }

  /// Stream of error events from the reader.
  ///
  /// Emits [ReadiumError] when errors occur during reading.
  Stream<ReadiumError> get onErrorEvent {
    return _platform.onErrorEvent;
  }

  /// Navigates to the previous page (or left in LTR layouts).
  Future<void> goLeft() {
    return _platform.goLeft();
  }

  /// Navigates to the next page (or right in LTR layouts).
  Future<void> goRight() {
    return _platform.goRight();
  }

  /// Skips to the next chapter or resource.
  Future<void> skipToNext() {
    return _platform.skipToNext();
  }

  /// Skips to the previous chapter or resource.
  Future<void> skipToPrevious() {
    return _platform.skipToPrevious();
  }

  /// Sets EPUB visual preferences.
  ///
  /// Applies typography and layout settings to the reader.
  ///
  /// ```dart
  /// await flureadium.setEPUBPreferences(EPUBPreferences(
  ///   fontFamily: 'Georgia',
  ///   fontSize: 120,
  ///   backgroundColor: Color(0xFFF5E6D3),
  /// ));
  /// ```
  Future<void> setEPUBPreferences(EPUBPreferences preferences) =>
      _platform.setEPUBPreferences(preferences);

  /// Sets navigation UX configuration for the reader.
  ///
  /// Use this to configure gesture-based navigation independently of
  /// visual reading preferences.
  Future<void> setNavigationConfig(ReaderNavigationConfig config) =>
      _platform.setNavigationConfig(config);

  /// Applies decorations (highlights, bookmarks) to the reader.
  ///
  /// The [id] groups related decorations together.
  /// Pass a list of [ReaderDecoration] objects to display.
  ///
  /// ```dart
  /// await flureadium.applyDecorations('highlights', [
  ///   ReaderDecoration(id: 'h1', locator: loc, style: DecorationStyle.highlight),
  /// ]);
  /// ```
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) => _platform.applyDecorations(id, decorations);

  /// Enables text-to-speech mode with optional preferences.
  ///
  /// [fromLocator] optionally starts TTS from a saved position.
  /// Once enabled, use [play], [pause], [next], [previous] to control.
  Future<void> ttsEnable(TTSPreferences? preferences, {Locator? fromLocator}) =>
      _platform.ttsEnable(preferences, fromLocator: fromLocator);

  /// Checks whether TTS can speak the current publication's language.
  Future<bool> ttsCanSpeak() => _platform.ttsCanSpeak();

  /// Requests the system to install missing TTS voice data.
  Future<void> ttsRequestInstallVoice() => _platform.ttsRequestInstallVoice();

  /// Updates TTS preferences while TTS is enabled.
  Future<void> ttsSetPreferences(TTSPreferences preferences) =>
      _platform.ttsSetPreferences(preferences);

  /// Sets decoration styles for TTS highlighting.
  ///
  /// [utteranceDecoration] highlights the current sentence.
  /// [rangeDecoration] highlights the current word/range.
  Future<void> setDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) => _platform.setDecorationStyle(utteranceDecoration, rangeDecoration);

  /// Gets the list of available TTS voices on the platform.
  ///
  /// On the platforms that implement TTS — Android, iOS, Web — this does not
  /// throw merely because TTS is not enabled. Android and iOS return an empty
  /// list. Web queries the browser's speech synthesis directly and may return
  /// voices whether or not TTS is enabled. To populate a voice picker before
  /// enabling TTS, use [ttsGetSystemVoices].
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() =>
      _platform.ttsGetAvailableVoices();

  /// Gets available TTS voices from the OS.
  ///
  /// On the platforms that implement TTS — Android, iOS, Web — this is
  /// independent of the TTS session and reports the device's voices whether
  /// or not TTS is enabled. Prefer this for voice pickers shown before
  /// reading aloud starts; see [ttsGetAvailableVoices] for its per-platform
  /// behavior.
  Future<List<ReaderTTSVoice>> ttsGetSystemVoices() =>
      _platform.ttsGetSystemVoices();

  /// Sets the TTS voice to use.
  ///
  /// [voiceIdentifier] is the platform-specific voice ID.
  /// [forLanguage] optionally restricts to a specific language.
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) =>
      _platform.ttsSetVoice(voiceIdentifier, forLanguage);

  /// Starts playback from an optional locator position.
  ///
  /// Works for both TTS and audiobook modes.
  Future<void> play(Locator? fromLocator) => _platform.play(fromLocator);

  /// Stops playback completely.
  Future<void> stop() => _platform.stop();

  /// Pauses playback at the current position.
  Future<void> pause() => _platform.pause();

  /// Resumes playback from the paused position.
  Future<void> resume() => _platform.resume();

  /// Moves to the next sentence (TTS) or track (audiobook).
  Future<void> next() => _platform.next();

  /// Moves to the previous sentence (TTS) or track (audiobook).
  Future<void> previous() => _platform.previous();

  /// Navigates to a specific locator position.
  ///
  /// Returns true if navigation succeeded.
  Future<bool> goToLocator(Locator locator) => _platform.goToLocator(locator);

  /// Enables audiobook playback mode.
  ///
  /// [prefs] sets playback preferences like speed.
  /// [fromLocator] optionally starts from a saved position.
  Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator}) =>
      _platform.audioEnable(prefs: prefs, fromLocator: fromLocator);

  /// Updates audio playback preferences.
  Future<void> audioSetPreferences(AudioPreferences prefs) =>
      _platform.audioSetPreferences(prefs);

  /// Seeks audio playback by the given offset.
  ///
  /// Positive offset seeks forward, negative seeks backward.
  Future<void> audioSeekBy(Duration offset) => _platform.audioSeekBy(offset);

  /// Renders the first page of a PDF as a JPEG image for use as a cover.
  ///
  /// Returns image bytes (JPEG), or null if the publication is not a PDF
  /// or rendering fails. Does not require opening a publication first.
  ///
  /// [maxWidth] and [maxHeight] constrain the output image dimensions
  /// while preserving aspect ratio.
  ///
  /// ```dart
  /// final coverBytes = await flureadium.renderFirstPage('file:///path/to/book.pdf');
  /// if (coverBytes != null) {
  ///   // Save or display the cover image
  /// }
  /// ```
  Future<Uint8List?> renderFirstPage(
    String pubUrl, {
    int maxWidth = 600,
    int maxHeight = 800,
  }) {
    return _platform.renderFirstPage(
      pubUrl,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  /// Extracts a downscaled JPEG thumbnail of a publication resource.
  ///
  /// [href] is the resource href as it appears in [Publication.readingOrder]
  /// or [Publication.tableOfContents]. [maxHeight] caps the longest side of
  /// the output image in pixels. [quality] is the JPEG quality (0-100).
  ///
  /// Returns null if the publication is closed, the href cannot be resolved,
  /// or the resource cannot be decoded. Web always returns null.
  Future<Uint8List?> extractPageThumbnail(
    String href,
    int maxHeight,
    int quality,
  ) => _platform.extractPageThumbnail(href, maxHeight, quality);

  /// Navigates to a link within the publication.
  ///
  /// Converts the [link] to a [Locator] and navigates to it.
  /// Returns true if navigation succeeded.
  ///
  /// Throws [ReadiumException] if the link cannot be resolved.
  Future<bool> goByLink(final Link link, final Publication pub) async {
    R2Log.d(() => 'Navigating to link: $link');

    final locator = pub.locatorFromLink(link);

    R2Log.d(locator);

    if (locator == null) {
      throw const ReadiumException('Link could not be resolved to locator');
    }

    return goToLocator(locator);
  }

  /// Navigates to a physical page by its index label.
  ///
  /// Uses the publication's page-list to find the matching page.
  /// The [index] is matched case-insensitively against page titles.
  ///
  /// Throws [ReadiumException] if the page is not found.
  Future<bool> toPhysicalPageIndex(
    final String index,
    final Publication pub,
  ) async {
    final pageIndex = index.toLowerCase();
    final pageList = pub.pageList;
    final pageLink = pageList.firstWhereOrNull(
      (final link) => link.title?.toLowerCase() == pageIndex,
    );
    if (pageLink == null) {
      throw const ReadiumException('Page link not found');
    }

    return goByLink(pageLink, pub);
  }

  /// Registers the [CarContentProvider] that answers CarPlay / Android Auto
  /// browse, search, and playback requests.
  ///
  /// [strings] carries the already-localized status copy the car renderers show
  /// verbatim; flureadium owns none of that text.
  void registerCarContentProvider(
    CarContentProvider provider, {
    required CarContentStrings strings,
  }) => _platform.registerCarContentProvider(provider, strings: strings);

  /// Removes the registered car content provider, clearing the car surface.
  void unregisterCarContentProvider() =>
      _platform.unregisterCarContentProvider();

  /// Triggers a re-fetch of the car browse tree on the connected head unit so a
  /// live CarPlay / Android Auto session repaints after the library changes.
  ///
  /// Fire-and-forget and a no-op when no car surface is connected — safe to call
  /// on every browsable-set mutation.
  void refreshCarContent() => _platform.refreshCarContent();
}
