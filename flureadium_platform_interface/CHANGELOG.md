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
