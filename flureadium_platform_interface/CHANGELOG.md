## 0.10.3

### Bug Fixes

- `Locations.tocFragment` returned an empty string when the fragment list carried a bare `toc=`. The value was present but named no heading, so two locators from unrelated chapters compared equal and a host had no way to tell them apart. An empty value now reads as absent and the getter returns `null`.

### Testing

- `LocationExtension` and `TimeFragment` had no tests. They have them now: every getter, every `copyWith*` method including the path that clears a fragment, and a parse-and-render round trip for `TimeFragment`.
- Two defects the new tests turned up are asserted as they behave today rather than fixed. A `copyWith*` call cannot clear the last remaining fragment (flureadium-vea4), and `TimeFragment.fromFragment('t=')` throws when the begin value is missing (flureadium-p2s7).

---

## 0.10.2

No API change. `lib/` is byte-identical to `0.10.1`; this release exists because the
package's analyzer configuration and its whole test suite moved, and those changes
have nowhere else to be recorded.

### Tooling

- `analysis_options.yaml` wires the `flureadium_lints` analyzer plugin, with `vacuous_type_assertion` and `vacuous_not_null_assertion` enabled. Both catch an assertion that cannot fail: an `isA<T>()` against a value whose static type is already `T`, and an `isNotNull` on something that cannot be null. `dart analyze --fatal-infos` is the only command that reports them — `flutter analyze` prints nothing — so that is what this package's analysis row runs. See `flureadium/docs/05-testing/lint-rules.md`.

### Testing

- Assertions that could not fail are corrected across twelve suites: `link_test.dart`, `localized_string_test.dart`, `locator_test.dart`, `contributor_test.dart`, `metadata_test.dart`, `publication_test.dart`, `subject_test.dart`, `format_test.dart`, `dom_range_test.dart`, `exception_test.dart`, `flureadium_platform_interface_test.dart` and `integration/method_channel_test.dart`. Most were an `isNotNull` or `isNotEmpty` standing in for the value the test meant to check, so they now assert the value: `expect(json['sortAs'], equals({'und': 'Collection, Test'}))` rather than that the key exists, and `expect(error.stackTrace.toString(), equals('at line 1\nat line 2'))` rather than that a stack trace is present.
- Two of those corrections changed what the suite says the code does. `Link.mediaType` was tested as "returns binary media type for invalid type" against `invalid/type`, asserting only `isNotNull`; that string is a syntactically valid media type and is kept verbatim, so the case is split — one for a valid-but-unknown type kept as written, one for unparseable input falling back to `MediaType.binary`. And `link.toUrl(null)` was asserted `isNotNull`; it resolves the relative href against the root, so the test says `/chapter.html`.
- `localized_string_test.dart` asked `json.containsKey(null)` of a `Map<String, String>`, which cannot hold a null key, so the check could never have found one. It compares the whole key set instead, which is what "the null language became `und` and nothing else appeared with it" actually means.
- `format_test.dart` compared `PublicationFormat.pdf` with itself, which identity satisfies before equality is ever consulted. It builds a second instance and compares that.
- The locator event-channel test was skipped as flaky and was deterministically dead: its mock pushed a Dart object where the getter decodes a JSON string. Fixed and re-enabled.
- Two suites asserted that a mock had been called without asserting what it returned. They check the returned values now.

---

## 0.10.1

### Bug Fixes

- **Packaged manifests no longer gain a leading slash on their hrefs**: `Publication.fromJson` resolved reading-order hrefs against the manifest's `self` link. For a packaged publication that link is relative (`manifest.json`), its derived base is the empty string, and `Href` treats an empty base as `/` — so every href came back as `/01_track.mp3` while the `Locator` stream kept emitting `01_track.mp3`. On Android that made a publication href impossible to compare with a locator href, breaking the guarantee `flureadium`'s `docs/api-reference/publication.md` gives. It showed up only on Android because readium-kotlin keeps a packaged manifest's `self` link while readium-swift strips it, so iOS was already taking the verbatim path. Hrefs are now resolved against the manifest's location only when that location is one — an absolute or root-relative `self` link — and left verbatim otherwise. A remote manifest still resolves against its directory. The no-`self`-link case is unchanged and now shares the same rule rather than sitting in its own branch.
- **`links` is no longer always empty**: looking up the `self` link consumed the manifest's `links` array, and the later parse re-read a key that was already gone, so `publication.links` came back empty for every caller that did not pass `packaged: true`, which is every caller outside the tests. The array is read once and used for both.

### Documentation

- **Voice query contract**: `ttsGetAvailableVoices()` now documents that it does not throw merely because TTS is disabled. Android and iOS return an empty list; Web queries the browser's speech synthesis directly and may return voices either way. To populate a voice picker before enabling TTS, use `ttsGetSystemVoices()`.

### Testing

- `Publication.fromJson` href resolution is covered per branch: a relative `self` link keeps reading-order, resource and toc hrefs verbatim; a root-relative `self` link still resolves; the declared `links` survive the self-link lookup; and a `Locator` built from a reading-order `Link` carries that link's href unchanged. The last one is a consistency check rather than a guard against this bug — it passed before the fix too, because both sides carried the slash. What the Android audiobook integration tests compare is a publication href against a locator the native side emitted, and only they cover that.
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
