## 0.10.1

### Documentation

- **Voice query contract**: `ttsGetAvailableVoices()` now documents that it does not throw merely because TTS is disabled. Android and iOS return an empty list; Web queries the browser's speech synthesis directly and may return voices either way. To populate a voice picker before enabling TTS, use `ttsGetSystemVoices()`.

### Testing

- The method-channel decode path surfaces an empty native voice response as an empty list, never a throw and never null.

---

## 0.10.0

### New Features

- **Car content refresh**: Add `FlureadiumPlatform.refreshCarContent()` (with a throwing default) and its method-channel implementation, so the host can tell a connected CarPlay / Android Auto surface that the browsable library changed and it should re-query.

### Testing

- Default-throws and method-channel invocation tests for `refreshCarContent()`.

---

## 0.9.0

### New Features

- **Car content contract**: Add the car-integration types the flureadium plugin's CarPlay and Android Auto renderers consume: `CarContentProvider` (the host-implemented `rootTabs`/`children`/`search`/`play`/`nowPlayingChapters`/`addBookmark`/`cycleSpeed` contract), `CarBrowseNode` with `CarNodeKind`, `CarTab`, `CarContentStrings`, and the `CarContentTransport` method-channel router. `FlureadiumPlatform` gains `registerCarContentProvider`/`unregisterCarContentProvider`. All exported from the package barrel.

### Testing

- Unit tests for the car value types (`CarBrowseNode`/`CarTab`/`CarContentStrings` validation + JSON round-trips), the `CarContentProvider` contract, and `CarContentTransport` method-channel routing.

---

## 0.8.0

### Changed

- Validated against Flutter 3.44.7 (Dart 3.12.2). No code changes; the public API is identical to 0.7.1. Bumped so it releases alongside the flureadium package's Flutter 3.44 update.

---

## 0.7.1

### Bug Fixes

- **Relative href normalisation**: `Publication.fromJson` no longer adds a leading slash to relative hrefs when a manifest is unpackaged and has no `self` link. A bare href like `001.jpg` used to come back as `/001.jpg`, while `Locator.fromJson` left it untouched — so `pub.readingOrder.first.href` and the `Locator` stream disagreed about the same resource, and any caller passing an href between the two and a native API hit a format mismatch. Such hrefs now keep the form the native Readium parser produced. Packaged manifests, and manifests with a `self` link, behave as before.

### Testing

- Cover all three `Publication.fromJson` base-URL branches: no self link and not packaged (hrefs verbatim), self link present (resolved against the self URL), and packaged (leading slash kept).

---

## 0.7.0

### New Features

- Add `extractPageThumbnail(href, maxHeight, quality)` to `FlureadiumPlatform` and `MethodChannelFlureadium`.
- The method-channel implementation sends `extractPageThumbnail` with `[href, maxHeight, quality]` and returns nullable `Uint8List` JPEG bytes.

### Bug Fixes

- **Locator href encoding**: `Locator.fromJson` now decodes percent-encoded hrefs so the internal representation is always in decoded form. `Locator.toJson` encodes hrefs for safe transport to native platforms. Fixes `PlatformException(InvalidArgument, Failed to parse locator)` on iOS when navigating CBZ files with special characters (spaces, brackets) in filenames.

### Testing

- Add method-channel integration tests for thumbnail argument forwarding, nullable byte results, and native exception propagation.
- Add 8 unit tests for href encoding: fromJson decoding, toJson encoding, roundtrip idempotency, and edge cases (spaces-only, brackets-only, mixed special characters).

---

## 0.6.0

### New Features

- Add `ttsCanSpeak()` to `FlureadiumPlatform` and `MethodChannelFlureadium` — checks whether the device TTS engine can speak for the current publication's language.
- Add `ttsRequestInstallVoice()` — opens the platform voice-data installer when the required language pack is missing.
- Add `TtsErrorType` enum to `ReadiumTimebasedState` — surfaces structured TTS errors (`languageMissingData`, `languageNotSupported`, `synthesisError`, `networkError`).
- Add `ttsGetSystemVoices()` — returns all system-level TTS voices, independent of publication language.
- Add optional `fromLocator` parameter to `ttsEnable()` — allows restoring TTS playback position after re-enabling.

### Testing

- Add regression test for `ttsSetPreferences` with null `voiceIdentifier` in method channel integration tests.

---

## 0.5.0

### Breaking Changes

- **EPUBPreferences**: Remove navigation config fields `enableEdgeTapNavigation`, `enableSwipeNavigation`, `edgeTapAreaPoints`. Use `setNavigationConfig(ReaderNavigationConfig)` instead.
- **PDFPreferences**: Remove navigation config fields `enableEdgeTapNavigation`, `enableSwipeNavigation`, `edgeTapAreaPoints`, `disableDoubleTapZoom`, `disableTextSelection`, `disableDragGestures`, `disableDoubleTapTextSelection`. Use `setNavigationConfig(ReaderNavigationConfig)` instead.

### New Features

- Add `ReaderNavigationConfig` — dedicated type for app-developer navigation UX settings (edge tap, swipe, gesture disabling). These are separate from Readium user reading preferences.
- Add `setNavigationConfig(ReaderNavigationConfig)` to `FlureadiumPlatform`, `MethodChannelFlureadium`, `ReadiumReaderWidgetInterface`, `_ReadiumReaderWidgetState`, and `ReadiumReaderChannel`.

## 0.4.0

### Breaking Changes

- **PDFPreferences**: Rename `disableTextSelectionMenu` to `disableDoubleTapTextSelection`. The old name
  was misleading — this preference removes `UITextNonEditableInteraction` from `PDFTextInputView`,
  preventing double-tap word selection entirely. Long-press text selection and the Look Up/Translate/
  Search Web menu remain fully functional.

## 0.3.1

- Add `edgeTapAreaPoints` to `EPUBPreferences` — configures the edge tap zone width in absolute points (44–120pt). iOS only. Defaults to 44pt (iOS HIG minimum tap target) when null.
- Add `edgeTapAreaPoints` to `PDFPreferences` — same control for the PDF reader.

## 0.3.0

- Add `renderFirstPage` method to `FlureadiumPlatform` and `MethodChannelFlureadium` — renders the first page of a PDF as a JPEG image for cover generation.

## 0.2.0

- Add `enableEdgeTapNavigation` and `enableSwipeNavigation` to `PDFPreferences` — allows independently controlling edge tap and swipe page navigation on iOS.
- Add `enableEdgeTapNavigation` and `enableSwipeNavigation` to `EPUBPreferences` — same controls for EPUB reader on iOS.

## 0.1.0

- Initial public release of the Flureadium platform interface.
- Abstract `FlureadiumPlatform` class with full API for EPUB, PDF, and audiobook reading.
- Method channel implementation (`MethodChannelFlureadium`).
- Readium shared models: `Publication`, `Locator`, `Metadata`, `Link`, `MediaType`, and more.
- Reader preference models: `EPUBPreferences`, `PDFPreferences`, `TTSPreferences`, `AudioPreferences`.
- Reader decoration API for highlights and annotations.
- TTS voice model and platform-specific voice name mappings.
- Exception types for structured error handling.
- OPDS feed and publication models.
- Extension utilities for colors, durations, locators, and strings.
