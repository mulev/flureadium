# Flureadium Class

The main entry point for the Flureadium plugin. Provides a unified API for reading EPUB publications, playing audiobooks, and using text-to-speech.

**Source:** [flureadium.dart](../../lib/flureadium.dart)

## Overview

`Flureadium` is a singleton class. Get the instance using the factory constructor:

```dart
final flureadium = Flureadium();
```

## Publication Lifecycle

### loadPublication

Loads a publication without opening it in the reader.

```dart
Future<Publication> loadPublication(String pubUrl)
```

**Parameters:**
- `pubUrl` - Local file path (`file://`) or remote URL

**Returns:** The [Publication](publication.md) metadata

**Example:**
```dart
final pub = await flureadium.loadPublication('file:///path/to/book.epub');
print('Title: ${pub.metadata.title}');
print('Chapters: ${pub.tableOfContents.length}');
```

### openPublication

Opens a publication and prepares it for reading.

```dart
Future<Publication> openPublication(String pubUrl)
```

**Parameters:**
- `pubUrl` - Local file path (`file://`) or remote URL

**Returns:** The [Publication](publication.md) metadata

**Throws:** [ReadiumException](../../ERROR_HANDLING.md) if the publication cannot be opened

**Example:**
```dart
try {
  final pub = await flureadium.openPublication('file:///path/to/book.epub');
  print('Opened: ${pub.metadata.title}');
} on OpeningReadiumException catch (e) {
  print('Failed to open: ${e.message}');
}
```

### closePublication

Closes the currently open publication and releases resources.

```dart
Future<void> closePublication()
```

**Example:**
```dart
@override
void dispose() {
  flureadium.closePublication();
  super.dispose();
}
```

### setCustomHeaders

Sets custom HTTP headers for network requests.

```dart
Future<void> setCustomHeaders(Map<String, String> headers)
```

**Parameters:**
- `headers` - Map of header names to values

**Example:**
```dart
await flureadium.setCustomHeaders({
  'Authorization': 'Bearer your-token',
  'X-Custom-Header': 'value',
});
```

## Navigation

### goLeft

Navigates to the previous page (or left in LTR layouts).

```dart
Future<void> goLeft()
```

### goRight

Navigates to the next page (or right in LTR layouts).

```dart
Future<void> goRight()
```

### skipToNext

Skips to the next chapter or resource.

```dart
Future<void> skipToNext()
```

### skipToPrevious

Skips to the previous chapter or resource.

```dart
Future<void> skipToPrevious()
```

### goToLocator

Navigates to a specific locator position.

```dart
Future<bool> goToLocator(Locator locator)
```

**Parameters:**
- `locator` - The [Locator](locator.md) to navigate to

**Returns:** `true` when an active navigator accepted the locator. Returns `false` if no reader is active or, on image-based readers, the native navigator is not ready before its bounded wait expires.

**Example:**
```dart
final success = await flureadium.goToLocator(savedLocator);
if (!success) {
  print('Navigation failed');
}
```

### goByLink

Navigates to a link within the publication.

```dart
Future<bool> goByLink(Link link, Publication pub)
```

**Parameters:**
- `link` - The [Link](publication.md#link) to navigate to
- `pub` - The current [Publication](publication.md)

**Returns:** `true` if navigation succeeded

**Throws:** [ReadiumException](../../ERROR_HANDLING.md) if the link cannot be resolved

**Example:**
```dart
// Navigate to TOC entry
final tocLink = pub.tableOfContents[2];
await flureadium.goByLink(tocLink, pub);
```

### toPhysicalPageIndex

Navigates to a physical page by its index label.

```dart
Future<bool> toPhysicalPageIndex(String index, Publication pub)
```

**Parameters:**
- `index` - Page label (matched case-insensitively)
- `pub` - The current [Publication](publication.md)

**Returns:** `true` if navigation succeeded

**Throws:** [ReadiumException](../../ERROR_HANDLING.md) if the page is not found

**Example:**
```dart
// Go to page 42
await flureadium.toPhysicalPageIndex('42', pub);
```

## Preferences

### setDefaultPreferences

Sets default EPUB preferences for all publications.

```dart
void setDefaultPreferences(EPUBPreferences preferences)
```

**Parameters:**
- `preferences` - The [EPUBPreferences](preferences.md#epubpreferences) to apply

**Example:**
```dart
flureadium.setDefaultPreferences(EPUBPreferences(
  fontFamily: 'Georgia',
  fontSize: 120,
  fontWeight: 400,
  verticalScroll: false,
  backgroundColor: Color(0xFFF5E6D3),
  textColor: Color(0xFF333333),
));
```

### setEPUBPreferences

Applies EPUB visual preferences to the reader.

```dart
Future<void> setEPUBPreferences(EPUBPreferences preferences)
```

**Parameters:**
- `preferences` - The [EPUBPreferences](preferences.md#epubpreferences) to apply

**Example:**
```dart
await flureadium.setEPUBPreferences(EPUBPreferences(
  fontFamily: 'Helvetica',
  fontSize: 100,
  fontWeight: 400,
  verticalScroll: true,
  backgroundColor: Color(0xFFFFFFFF),
  textColor: Color(0xFF000000),
));
```

## Decorations

### applyDecorations

Applies decorations (highlights, bookmarks) to the reader.

```dart
Future<void> applyDecorations(String id, List<ReaderDecoration> decorations)
```

**Parameters:**
- `id` - Group identifier for these decorations
- `decorations` - List of [ReaderDecoration](decorations.md) objects

**Example:**
```dart
await flureadium.applyDecorations('highlights', [
  ReaderDecoration(
    id: 'highlight-1',
    locator: selectedLocator,
    style: ReaderDecorationStyle(
      style: DecorationStyle.highlight,
      tint: Color(0xFFFFFF00),
    ),
  ),
]);

// Clear decorations for a group
await flureadium.applyDecorations('highlights', []);
```

## Text-to-Speech

### ttsEnable

Enables text-to-speech mode.

```dart
Future<void> ttsEnable(TTSPreferences? preferences, {Locator? fromLocator})
```

**Parameters:**
- `preferences` - Optional [TTSPreferences](preferences.md#ttspreferences)
- `fromLocator` - Optional [Locator](locator.md) to start TTS from a saved position. When provided, TTS begins reading from this location instead of the current visible position. Useful for resuming after disabling and re-enabling TTS.

**Example:**
```dart
// Enable with default position
await flureadium.ttsEnable(TTSPreferences(speed: 1.2, pitch: 1.0));

// Resume from a saved position
await flureadium.ttsEnable(
  TTSPreferences(speed: 1.2),
  fromLocator: savedLocator,
);
```

### ttsCanSpeak

Checks whether the platform's TTS engine can speak the current publication's language.

```dart
Future<bool> ttsCanSpeak()
```

**Returns:** `true` if TTS can handle the publication's language, `false` otherwise

Call this after opening a publication and before enabling TTS to verify language support. The Web implementation runs an extra pre-check, described in [Text-to-Speech on Web](../platform-specific/web.md#text-to-speech).

**Example:**
```dart
final canSpeak = await flureadium.ttsCanSpeak();
if (!canSpeak) {
  // Offer to install voice data or show a warning
  await flureadium.ttsRequestInstallVoice();
}
```

### ttsRequestInstallVoice

Requests the system to install missing TTS voice data for the current publication's language.

```dart
Future<void> ttsRequestInstallVoice()
```

On Android, this opens the system TTS voice data installation dialog. On iOS, this is a no-op since voice downloads are managed through system settings.

**Example:**
```dart
if (!await flureadium.ttsCanSpeak()) {
  await flureadium.ttsRequestInstallVoice();
}
```

### ttsSetPreferences

Updates TTS preferences while TTS is enabled.

```dart
Future<void> ttsSetPreferences(TTSPreferences preferences)
```

**Parameters:**
- `preferences` - The [TTSPreferences](preferences.md#ttspreferences) to apply

### ttsGetAvailableVoices

Gets the list of available TTS voices on the platform.

On the platforms that implement TTS — Android, iOS, Web — `ttsGetAvailableVoices()` does not throw merely because TTS is not enabled. Android and iOS return an empty list. Web queries the browser's speech synthesis directly and may return voices whether or not TTS is enabled. To populate a voice picker before enabling TTS, use `ttsGetSystemVoices()`.

```dart
Future<List<ReaderTTSVoice>> ttsGetAvailableVoices()
```

**Returns:** List of available voices, or an empty list on Android and iOS when TTS is not enabled

**Example:**
```dart
final voices = await flureadium.ttsGetAvailableVoices();
for (final voice in voices) {
  print('${voice.name} (${voice.language})');
}
```

### ttsGetSystemVoices

Gets available TTS voices from the OS.

On the platforms that implement TTS — Android, iOS, Web — this is independent of the TTS session and reports the device's voices whether or not TTS is enabled. Prefer this for voice pickers shown before reading aloud starts; see `ttsGetAvailableVoices()` for its per-platform behavior.

```dart
Future<List<ReaderTTSVoice>> ttsGetSystemVoices()
```

**Returns:** List of available platform voices (same `ReaderTTSVoice` model as `ttsGetAvailableVoices`)

**Example:**
```dart
// Works before ttsEnable()
final voices = await flureadium.ttsGetSystemVoices();
final englishVoices = voices.where((v) => v.language.startsWith('en')).toList();
```

### ttsSetVoice

Sets the TTS voice to use.

```dart
Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage)
```

**Parameters:**
- `voiceIdentifier` - Platform-specific voice ID
- `forLanguage` - Optional language restriction

**Example:**
```dart
final voices = await flureadium.ttsGetAvailableVoices();
final englishVoice = voices.firstWhere((v) => v.language.startsWith('en'));
await flureadium.ttsSetVoice(englishVoice.identifier, 'en');
```

### setDecorationStyle

Sets decoration styles for TTS highlighting.

```dart
Future<void> setDecorationStyle(
  ReaderDecorationStyle? utteranceDecoration,
  ReaderDecorationStyle? rangeDecoration,
)
```

**Parameters:**
- `utteranceDecoration` - Style for current sentence highlight
- `rangeDecoration` - Style for current word/range highlight

**Example:**
```dart
await flureadium.setDecorationStyle(
  ReaderDecorationStyle(
    style: DecorationStyle.highlight,
    tint: Color(0xFFFFFF00),  // Yellow for sentence
  ),
  ReaderDecorationStyle(
    style: DecorationStyle.underline,
    tint: Color(0xFF0000FF),  // Blue for word
  ),
);
```

## PDF Utilities

### renderFirstPage

Renders the first page of a PDF as a JPEG image for use as a cover.

```dart
Future<Uint8List?> renderFirstPage(
  String pubUrl, {
  int maxWidth = 600,
  int maxHeight = 800,
})
```

**Parameters:**
- `pubUrl` - Local file path to the PDF
- `maxWidth` - Maximum output width in pixels (default: 600)
- `maxHeight` - Maximum output height in pixels (default: 800)

**Returns:** JPEG image bytes, or `null` if rendering fails

Does not require opening a publication first. Uses `PdfRenderer` on Android and `CGPDFDocument` on iOS — no Readium dependency needed.

**Example:**
```dart
final coverBytes = await flureadium.renderFirstPage('file:///path/to/book.pdf');
if (coverBytes != null) {
  final file = File('/path/to/cover.jpg');
  await file.writeAsBytes(coverBytes);
}
```

### extractPageThumbnail

Returns a downscaled JPEG thumbnail of an image resource in the currently open publication.

```dart
Future<Uint8List?> extractPageThumbnail(
  String href,
  int maxHeight,
  int quality,
)
```

**Parameters:**
- `href` - Resource href from `Publication.readingOrder` or `Publication.tableOfContents`
- `maxHeight` - Caps the longer side of the output image, in pixels
- `quality` - JPEG quality, 0-100

**Returns:** JPEG bytes, or `null` if the publication is closed, the href is unknown, the platform does not implement thumbnail extraction, or the resource fails to decode as an image.

The native side reuses the already-mounted publication, so LCP-decryption and streaming work without extra setup. Android handles the method call on a `Dispatchers.IO` coroutine. iOS reads and decodes in a detached user-initiated task and returns the result on the main actor.

Use this for TOC thumbnails or any UI that needs a small bitmap for an arbitrary page. Avoid `ui.instantiateImageCodec` inside `Isolate.spawn` workers: the image decoder registry is not initialised there, even with `BackgroundIsolateBinaryMessenger.ensureInitialized`.

**Platform notes:**
- iOS: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`. The thumbnail is decoded directly from the JPEG without loading the full image.
- Android: `BitmapFactory` with `inJustDecodeBounds` for the bounds pass, `inSampleSize` for the decode pass, then `Bitmap.compress(JPEG, quality, ...)`.
- Web and macOS: returns `null` or is not implemented by the current platform plugin. No decoder is wired up.

If the publication is closed while the call is in flight, the future resolves to `null` instead of throwing.

**Example:**
```dart
final href = pub.readingOrder.first.href;
final bytes = await flureadium.extractPageThumbnail(href, 80, 70);
if (bytes != null) {
  // render via Image.memory(bytes) or cache to disk
}
```

---

## Audiobook

### audioEnable

Enables audiobook playback mode.

```dart
Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator})
```

**Parameters:**
- `prefs` - Optional [AudioPreferences](preferences.md#audiopreferences)
- `fromLocator` - Optional starting position

**Example:**
```dart
await flureadium.audioEnable(
  prefs: AudioPreferences(speed: 1.0, volume: 1.0),
  fromLocator: savedPosition,
);
```

### audioSetPreferences

Updates audio playback preferences.

```dart
Future<void> audioSetPreferences(AudioPreferences prefs)
```

**Parameters:**
- `prefs` - The [AudioPreferences](preferences.md#audiopreferences) to apply

### audioSeekBy

Seeks audio playback by the given offset.

```dart
Future<void> audioSeekBy(Duration offset)
```

**Parameters:**
- `offset` - Time offset (positive = forward, negative = backward)

**Example:**
```dart
// Skip forward 30 seconds
await flureadium.audioSeekBy(Duration(seconds: 30));

// Skip backward 10 seconds
await flureadium.audioSeekBy(Duration(seconds: -10));
```

## Playback Control

These methods work for both TTS and audiobook modes.

### play

Starts playback from an optional locator position.

```dart
Future<void> play(Locator? fromLocator)
```

**Parameters:**
- `fromLocator` - Optional starting position (null = current position)

### pause

Pauses playback at the current position.

```dart
Future<void> pause()
```

### resume

Resumes playback from the paused position.

```dart
Future<void> resume()
```

### stop

Stops playback completely.

```dart
Future<void> stop()
```

### next

Moves to the next sentence (TTS) or track (audiobook).

```dart
Future<void> next()
```

### previous

Moves to the previous sentence (TTS) or track (audiobook).

```dart
Future<void> previous()
```

## Car Content

Registers the host's library with the CarPlay / Android Auto browse surface and
keeps a live surface current. The full data contract (`CarContentProvider`,
`CarBrowseNode`, `CarTab`, `CarContentStrings`) lives in
[Car content](car-content.md).

### registerCarContentProvider

Registers the [CarContentProvider](car-content.md#carcontentprovider) that
answers car browse, search, and playback requests. Call once during app start,
before a car connects.

```dart
void registerCarContentProvider(
  CarContentProvider provider, {
  required CarContentStrings strings,
})
```

**Parameters:**
- `provider` - The host's car content source
- `strings` - Already-localized status copy the renderers show verbatim

### unregisterCarContentProvider

Removes the registered provider, clearing the car surface. The channel handler
stays installed, so a car process that calls in before registration gets an
empty result rather than an error.

```dart
void unregisterCarContentProvider()
```

### refreshCarContent

Tells a connected head unit to re-fetch its browse tree after the library
changes. Fire-and-forget and a no-op when no car surface is connected, so it is
safe to call on every browsable-set mutation (a book added, deleted,
categorized, completed, or renamed).

```dart
void refreshCarContent()
```

**Example:**
```dart
// After mutating the library, repaint any live car surface.
Flureadium().refreshCarContent();
```

## Event Streams

### onReaderStatusChanged

Stream of reader status changes.

```dart
Stream<ReadiumReaderStatus> get onReaderStatusChanged
```

**Emits:** [ReadiumReaderStatus](streams-events.md#readiumreaderstatus)

### onTextLocatorChanged

Stream of text locator changes during reading.

```dart
Stream<Locator> get onTextLocatorChanged
```

**Emits:** [Locator](locator.md) whenever reading position changes

**Example:**
```dart
flureadium.onTextLocatorChanged.listen((locator) {
  final progress = locator.locations?.totalProgression ?? 0;
  print('Progress: ${(progress * 100).toStringAsFixed(1)}%');
});
```

### onTimebasedPlayerStateChanged

Stream of timebased player state changes.

```dart
Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged
```

**Emits:** [ReadiumTimebasedState](streams-events.md#readiumtimebasedstate) for audio/TTS playback

### onErrorEvent

Stream of error events from the reader.

```dart
Stream<ReadiumError> get onErrorEvent
```

**Emits:** [ReadiumError](streams-events.md#readiumerror) when errors occur

## See Also

- [ReaderWidget](reader-widget.md) - Display widget
- [Publication](publication.md) - Publication model
- [Locator](locator.md) - Position tracking
- [Preferences](preferences.md) - Configuration options
