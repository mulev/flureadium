## 0.13.0

### New Features

- **Android Auto**: Audiobooks now show up as a browsable media app on Android Auto head units. `PluginMediaService` runs as a media3 `MediaLibraryService` and serves a one-level browse tree: a root whose children are the open publication's chapters (its `readingOrder`). Picking a chapter on the head unit seeks the same audiobook navigator the in-app controls use, and play/pause/skip plus now-playing metadata reuse the existing media session. Needs no host manifest changes — the plugin declares the `com.google.android.gms.car.application` meta-data and ships the `automotive_app_desc.xml` descriptor, which manifest merging pulls into the host app (the example app adds nothing), and there are no Dart API changes. See `docs/platform-specific/android.md`.
- **CarPlay (iOS)**: Audiobooks expose a chapter list and transport controls on CarPlay. `CarPlayChapterList` builds one row per `readingOrder` entry (titles fall back to a localized "Chapter N"); selecting a row routes through `CarPlayPlaybackBridge` to the active audio navigator. Now-playing metadata and transport reuse the existing `NowPlayingInfoUpdater`. Host apps add a CarPlay scene to their scene manifest and the `com.apple.developer.carplay-audio` entitlement, which needs a per-app Apple grant, so plan for that lead time. See `docs/platform-specific/ios.md`.
- **Audiobook end-of-book state**: Reaching the natural end of the last track now emits a single `TimebasedState.ended` on both platforms, so hosts can show a completion screen. It fires only at a real end of book; closing or disposing the reader mid-playback no longer produces a phantom `ended` (iOS previously emitted one from `dispose()`).
- **Audiobook error events**: Streamed audio failures now reach `Flureadium.onErrorEvent` as a `ReadiumError` with code `TimebasedError`, instead of the player stalling silently at 0:00. Android forwards every timebased failure, load-time and mid-stream. iOS catches load-time track failures deterministically: during opening an `onCreatePublication` transform (`AudioResourceLoadFailureReporter` + `LoadFailureObservingResource`) wraps each audio track resource and reports a failed read, one error per track. Post-load decode/status failures and healthy-URL stalls stay best-effort on iOS (a KVO-only signal on Readium's private `AVPlayer`), and benign cancelled reads are filtered out. See `docs/guides/error-handling.md`.

### Bug Fixes

- **Audiobook previous/next chapter (Android & iOS)**: `Flureadium.previous()` / `next()` now move one track along the reading order on both platforms, instead of performing a 30-second seek that made the chapter buttons identical to skip-back / skip-forward. Bounded at the first and last track. TTS still maps these to previous/next sentence, and `audioSeekBy` (skip) behaviour is unchanged.
- **iOS audiobook transition freeze**: Changing chapter, seeking to a locator, or auto-advancing at end of track no longer freezes the UI. The audio delegate callbacks used to read `_audioNavigator.playbackInfo` synchronously, which re-entered the `AVPlayer` lock that `AudioNavigator.go(to:)` already held on the same thread — a self-deadlock. They now serve state from the playback info and locator Readium delivers off-lock, so a transition never reads back into the live player.
- **iOS error channel ownership**: The `error` `EventChannel` is now owned once by `FlureadiumPlugin` instead of being re-registered by each reader view. Closing a reader view no longer end-streams the Dart subscription, the audio path (which has no reader view) can send on the same channel, and `FlureadiumError` is serialized to a codec-safe map — sending the object itself crashed the Flutter standard codec. The PDF reader keeps its separate `pdf-error` channel.
- **iOS navigator teardown race**: `stop` now disposes the navigator captured at call time and clears the shared slot only if it still holds that navigator. A straggler teardown from a previous session no longer nils a navigator a newer session installed, which had surfaced as a spurious "TTS Navigator not initialized".
- **Android method-channel cancellation**: A coroutine cancelled mid-call — for example a `play` still suspended when the publication closes — unwinds normally instead of surfacing to Dart as a spurious `PlatformException(JobCancellationException)`. `CancellationException` is re-thrown rather than reported.

### Testing

- Android JVM tests for the Android Auto path: `AudiobookBrowseTree`, `PluginLibrarySessionCallback` (browse tree and chapter-pick seek-to-index), `PluginMediaService` library session, `PluginSimpleBasePlayer` (next/previous seek remap), and `TrackNavigation`; plus `AudiobookNavigatorEnded`, `ReadiumReaderTimebasedError`, and `PublicationChannelCancellation`.
- iOS XCTests for the CarPlay and error paths: `CarPlayChapterList`, `CarPlayPlaybackBridge`, `FlureadiumPluginChapterNav`, `FlureadiumPluginErrorChannel`, `FlutterAudioNavigator`, `AudioResourceLoadFailureReporter`, and `LoadFailureObservingResource`.
- Integration coverage: audiobook end-of-book `ended`, chapter and previous-chapter navigation (the same navigator path a head unit drives), unreachable and partial streamed-audio error surfacing, and an untitled-chapter audiobook. Adds the `untitled_chapter.audiobook` fixture and an `audio_stream_fixtures` harness for mid-stream failure.
- Example integration harness: `pumpUntil` bounded polling and an `ensureAppShowing` shared-boot helper so each test group boots once and reuses the app; TTS readiness is polled instead of waited out on a fixed timer.
- Test runners: `run_native_unit_tests.sh` gains `--rerun` for a clean Android rebuild, and `run_integration_tests.sh` pins the default Android TTS engine before the EPUB TTS leg so a cold emulator does not report an empty voice list.

### Documentation

- Android Auto setup and the browse-tree implementation, including Desktop Head Unit testing (`docs/platform-specific/android.md`).
- CarPlay setup — entitlement, scene manifest, simulator testing — and the chapter-list implementation (`docs/platform-specific/ios.md`).
- Audiobook end-of-book, transition safety, playback-error handling, and in-car sections (`docs/guides/audiobook-playback.md`).
- The `onErrorEvent` stream and the audiobook streaming-failure platform matrix, with the iOS post-load limitation (`docs/guides/error-handling.md`).
- Error channel single-ownership platform notes (`docs/api-reference/streams-events.md`).
- Troubleshooting entries for the iOS transition freeze, the "TTS Navigator not initialized" teardown race, and the Android cancellation `PlatformException` (`docs/troubleshooting.md`).
- Testing conventions: `pumpUntil`, `ensureAppShowing` shared boot, the `--rerun` runner flag, and the Android TTS prerequisite (`docs/05-testing/`).

## 0.12.1

### Bug Fixes

- **readingOrder href format**: `pub.readingOrder` hrefs now match what the `Locator` stream emits — bare paths as the native Readium parser produced them, with no synthetic leading slash (`001.jpg`, not `/001.jpg`). This fixes silent failures in code that compares a `Locator.href` against `readingOrder[i].href`, or round-trips an href through a native API, where the leading slash made the two never match. Comes from `flureadium_platform_interface` 0.7.1.

### Testing

- Add a CBZ integration regression that asserts `pub.readingOrder.first.href` equals the live `Locator.href` for the same resource.

### Documentation

- Note in the publication API reference that `readingOrder` hrefs share the `Locator` stream's format.

## 0.12.0

### New Features

- Add `flattenToc(List<Link> toc) → List<Link>`. Collects every TOC entry — including `link.children` at any depth — into a flat list in reading order. Exported from the `flureadium` barrel. Use it when you need a flat chapter sequence for a progress indicator or jump-to-chapter picker.

### Bug Fixes

- **Chapter skip / hierarchical EPUB3 TOC**: Fix `skipToNext` and `skipToPrevious` on `ReadiumReaderWidget` skipping over entire nested chapter groups. For books where `toc.xhtml` stores chapters as children of a parent entry (`link.children`), both methods previously searched only the top-level list — nested chapters were invisible, skip buttons disappeared, and "next chapter" jumped straight to the next top-level entry. Both now use the flattened TOC.
- **Chapter skip / non-TOC spine items**: Fix `skipToNext` and `skipToPrevious` giving up when the current page has no TOC entry (a cover, interstitial page, or back matter). Both now scan the reading order to find the nearest TOC entry before or after.

### Testing

- Unit tests for `flattenToc`: empty input, flat list, one level of nesting, multiple levels.
- Between-entries unit tests for `decideSkipToNext` and `decideSkipToPrevious`: a spine item between two TOC entries resolves to the adjacent chapter in each direction.
- `ReadiumReaderWidget` unit tests confirming `skipToNext` from a nested chapter reaches the next sibling, not the next top-level entry.
- `hierarchical_toc.epub` — a synthetic EPUB3 fixture with a two-level TOC (Part I → [Ch1, Ch2, Ch3]; Part II → Section 1 → [Ch4, Ch5]) and three non-TOC spine items.
- Navigation smoke tests parameterized to run against both `moby_dick.epub` and `hierarchical_toc.epub`.

### Documentation

- Document `flattenToc` in the publication API reference and the EPUB reading guide.
- Update `skipToNext` / `skipToPrevious` in the ReaderWidget reference with hierarchical TOC behavior.

## 0.11.0

### New Features

- Add `Flureadium.extractPageThumbnail(href, maxHeight, quality)` for downscaled JPEG thumbnails from image resources in the currently open publication.
- Add native thumbnail extraction on Android and iOS. Android uses `BitmapFactory` downsampling and JPEG compression; iOS uses ImageIO thumbnail decoding and JPEG compression.
- Add the `extractPageThumbnail` web override, returning `null` until a web decoder is wired up.

### Bug Fixes

- **iOS / CBZ and PDF navigation**: Route `goToLocator` to image-based readers and PDF readers, not just EPUB and time-based navigators.
- **iOS / early CBZ navigation**: Wait for the image navigator to become ready before programmatic `goToLocator`, returning `false` instead of hanging indefinitely when readiness never arrives.
- **Android / CBZ and PDF navigation**: Dispatch `goToLocator` to image and PDF navigators and return the native navigation result to Dart.
- **Android / thumbnail href lookup**: Resolve thumbnail hrefs through Readium legacy-href URL normalization so manifest hrefs with leading slashes or encoded characters resolve consistently.
- **Android / TTS service startup**: Enter the foreground immediately with a startup media notification so background playback startup is not killed before the real media notification is ready.

### Testing

- Add Dart facade tests and platform-interface method-channel tests for `extractPageThumbnail`.
- Add Android JVM tests for `PageThumbnailExtractor` and foreground-service startup behavior.
- Add iOS XCTest coverage for `PageThumbnailExtractor` and image-reader `goToLocator` readiness/routing.
- Extend CBZ integration coverage for `goToLocator`, successful thumbnail extraction, missing hrefs, and closed-publication behavior.

### Documentation

- Document `extractPageThumbnail` in the Flureadium API reference, concepts, platform docs, READMEs, and example README.
- Update README and docs format matrices for CBZ/DIVINA support and remove stale "not implemented" claims.
- Document Android and iOS thumbnail implementation details and the web `null` behavior.

### Dependencies

- Requires `flureadium_platform_interface` ^0.7.0.

## 0.10.0

### New Features

- **CBZ and DIVINA support**: `ReadiumReaderWidget` renders image-based publications on Android and iOS. Format detection is automatic — same widget, same API, no Dart-side changes.
- **Android**: `ImageNavigator` wraps Readium Kotlin's `ImageNavigatorFragment` with lifecycle management, state persistence, and locator tracking.
- **iOS**: `ImageReaderView` wraps Readium Swift's `CBZNavigatorViewController` with edge-tap and swipe navigation, same UX as the PDF reader.

### Bug Fixes

- **iOS CBZ navigation crash**: Fix `PlatformException(InvalidArgument, Failed to parse locator)` when navigating CBZ files with special characters in filenames. The Locator href encode/decode boundary in `flureadium_platform_interface` now normalizes hrefs correctly for native platform transport.
- **iOS CBZ page navigation performance**: Cache images from Readium's local server to eliminate redundant ZIP extraction and HTTP round-trips on every page turn. Adds `ImageCacheURLProtocol`, a URLProtocol subclass that intercepts localhost GET requests and serves cached images from NSCache. Cache is session-scoped and cleared when the reader closes.

### Performance

- **CBZ/DIVINA page turn speed**: Forward the `animated` parameter from `ReadiumReaderWidget.goLeft()`/`goRight()` through the method channel so callers can disable page turn animation. Previously the parameter was accepted but silently dropped, and the channel always animated.
- **iOS CBZ edge-tap instant page turns**: Edge-tap and swipe handlers in `ImageReaderView` now use `animated: false`, eliminating the ~300ms `UIPageViewController` transition on every tap.
- **Same-publication cache (iOS + Android)**: `openPublication` returns the already-loaded publication when called with the same URL, skipping redundant ZIP parsing and manifest construction. Eliminates ~3.9s re-open latency when resuming a CBZ/DIVINA book.

### Testing

- Android JVM tests for image navigator state, cleanup, routing detection, and saved-state persistence.
- iOS XCTest coverage for navigation state, edge-tap config, and publication routing.
- CBZ and DIVINA integration tests with bundled test fixtures, registered in `all_tests.dart` and `all_tests_android_ci.dart`.
- iOS XCTest coverage for `ImageCacheURLProtocol`: canInit filtering, cache hit/miss, enable/disable lifecycle, clearCache.
- Dart unit tests for `animated` parameter forwarding in `goLeft`/`goRight`.
- Android Robolectric tests for same-publication cache: cache hit, cache miss (different URL), cache miss (no current publication).
- DIVINA cache integration test.

### Example App

- "Open CBZ" and "Open DIVINA" buttons with bundled fixtures.
- Configurable startup asset (`initialAsset` parameter) for integration test injection.

### Documentation

- Reader widget, Android, iOS, concepts, and integration test docs updated for image-based publications.
- README format matrix now lists CBZ and DIVINA.
- Document href encoding behavior in the Locator API reference.

## 0.9.4

### Bug Fixes

- **Reader external-link callbacks**: Forward `ReadiumReaderWidget.onExternalLinkActivated` into `ReadiumReaderChannel` so Dart hosts actually receive external-link activations reported by the native reader.
- **Analyzer/test export mismatch**: Expose the widget-test channel-construction helper consistently across the conditional `reader_widget_*` exports so `dart analyze` and `flutter test` resolve the same public surface.

### Testing

- Add Dart regressions for the native `onExternalLinkActivated` method-call path and the widget/channel construction seam.
- Verify `dart analyze`, `flureadium/flutter test`, `flureadium_platform_interface/flutter test`, and the example EPUB integration smoke test pass.

### Documentation

- Document `onExternalLinkActivated` as a delivered integration callback and clarify that host apps can hand external links off to the OS browser for restricted-content flows.

## 0.9.3

### Bug Fixes

- **iOS / EPUB reader locator crash**: Replace the force-unwrapped `getLocatorFragments()` parse path with safe optional handling so `null` JavaScript results no longer crash the reader.
- **iOS / reader disposal race**: Guard async page-change callbacks with a disposal flag and `MainActor` state reads so page-change work does not outlive a torn-down reader view.

### Testing

- Add iOS regression coverage for locator-fragment result parsing in `ReadiumExtensionsTests`.
- Verify Flutter tests, native iOS `RunnerTests`, and example integration tests pass for the fix.

### Documentation

- Add a troubleshooting entry covering the locator-fragment crash symptoms, cause, and remediation.

## 0.9.2

### Bug Fixes

- **Android / sync audiobook saved-state crash**: `SyncAudiobookNavigator.storeState()` put `FlutterMediaOverlay` objects into the Bundle via `putSerializable`, but those objects contain non-serializable Readium types (`Url`, `MediaType`). Android's activity state save hit `BadParcelableException` → `NotSerializableException` during synchronized audiobook playback. The data was never actually read back — `restoreState()` re-derives overlays from the publication — so the fix drops the dead `putSerializable` call and removes `Serializable` from both model classes.

## 0.9.1

### Bug Fixes

- **Android / TTS and audiobook background playback**: Start `PluginMediaService` with `startForegroundService()` instead of `startService()` so Android 15 does not kill playback shortly after the app goes to the background.
- **Android / media session cleanup**: Close the media session if `TTSNavigator.play()` or `AudiobookNavigator.play()` fails while opening the session, preventing a dangling foreground-service start from timing out.
- **Android / saved-state background crash**: Persist `FlutterDecorationPreferences` as primitive `Bundle` data instead of Java serialization so pressing Home does not crash activity state saving with `BadParcelableException` on devices where Readium decoration styles are not serializable.

### Testing

- Add Android JVM regression tests for foreground-service startup and `openSession()` failure cleanup in TTS and audiobook navigators.
- Add Android JVM regression tests for `FlutterDecorationPreferences` bundle round-tripping and `ReadiumReader.storeState()` parcel-safe saved-state persistence.

### Documentation

- Document the Android foreground-service permissions required for background TTS and audiobook playback.
- Update the Android troubleshooting note to cover both the foreground-service startup fix and the saved-state crash fix for playback stopping when the app is backgrounded.

## 0.9.0

### New Features

- **iOS / EPUB**: Add `Copy` to the long-press text selection menu. EPUB selection actions now use `EditingAction.copy`, `EditingAction.lookup`, and `EditingAction.translate`, replacing the old placeholder custom action.

### Testing

- Add iOS XCTest coverage for EPUB editing actions in `EpubEditingActionsTests`.
- Add an EPUB integration smoke test that long-presses the reader surface and verifies the reader remains mounted.

### Documentation

- Document text-selection copy behavior on iOS and Android, including the existing PDF behavior and the Android PDF limitation.

## 0.8.3

### Bug Fixes

- **Android**: Fix NullPointerException crash when opening PDF files. Inside `PdfNavigator.initNavigator()`, a Kotlin scope resolution bug caused `engineProvider` to resolve to the uninitialized `PdfReaderViewModel` property instead of the outer `PdfNavigator` property.

## 0.8.2

### Bug Fixes

- **iOS**: Fix SIGABRT crash on hot reload with an active EPUB or PDF reader. The crash was a Swift runtime exclusivity violation — `deinit` wrote to a global variable that was already mid-write during ARC deallocation triggered by the new view's `init`. Global reader view references are now `weak var` (matching Android's `WeakReference` pattern), and `deinit` no longer touches them.
- **iOS**: Make PdfReaderView dispose handler comprehensive — stream disposal and channel cleanup were previously only in `deinit`, meaning they never ran when the Dart `dispose` call arrived while the engine was still alive.

## 0.8.1

### Bug Fixes

- **Android**: Convert `error.cause` to `String?` in `publicationError()` before passing it to `MethodChannel.Result.error()`. The Readium `Error` object was not codec-safe, causing `StandardMessageCodec` to throw `IllegalArgumentException: Unsupported value` and silently swallowing EPUB subject metadata.

## 0.8.0

### New Features

- **TTS availability check**: Add `ttsCanSpeak()` — checks whether the device TTS engine supports the current publication's language before enabling. Returns `false` when TTS is unavailable, letting you show an appropriate message instead of a silent failure.
- **TTS voice installer**: Add `ttsRequestInstallVoice()` — opens the platform voice-data installer when the required language pack is missing. Android launches the system TTS settings; on iOS and web this is a no-op.
- **TTS error reporting**: Add `TtsErrorType` to `ReadiumTimebasedState` — surfaces structured error types (`languageMissingData`, `languageNotSupported`, `synthesisError`, `networkError`) so the app can react to specific failure modes.
- **System voices**: Add `ttsGetSystemVoices()` — returns all system-level TTS voices regardless of publication language. Unlike `ttsGetAvailableVoices()` (which filters to the current publication), this gives the full list for voice-picker UI.
- **TTS position restore**: Add optional `fromLocator` parameter to `ttsEnable()` — allows resuming TTS playback from a saved position after disabling and re-enabling.
- **Android**: Add awaitable `release()` to all navigators — proper resource cleanup that can be awaited before switching publications.
- **Web**: Add TTS engine using the Web Speech API with full JS interop bridge to Dart.

### Bug Fixes

- **Android**: Suppress backward scroll when calling TTS `play()` from a specific position — the navigator no longer jumps back to the start of the chapter before reading.
- **iOS**: Suppress backward scroll on TTS play from a specific position, matching the Android fix.
- **Android**: Honor `initialLocator` in `TTSNavigator.initNavigator()` — TTS now starts from the saved locator instead of the beginning of the chapter.
- **iOS**: Use optional cast in `ttsSetPreferences` to handle null `voiceIdentifier` without crashing.
- **iOS**: Make `closePublication` awaitable to prevent async race when switching publications.
- **Android**: Dispatch navigator `close()` to the main thread in `release()`, preventing `CalledFromWrongThreadException`.
- **Android**: Dispatch fragment `commitNow` on the main thread in `release()`.
- **Android**: Guard stale "closed" event from a disposed platform view.
- **Android**: Release navigators in `openPublication()` before switching to prevent resource leaks.
- **Android**: Use `release()` in `ReadiumReader` for proper resource cleanup.
- Guard `setState` with `mounted` check and cancel leaked subscription after dispose.
- Use `_initialLocator` in TTS `play()` so resume starts from the saved position.
- Pass saved TTS locator on re-enable.

### Example App

- Full TTS control UI: can-speak gating, voice cycling, system voice picker, sentence navigation, install-voice prompt on missing language data.
- Save and restore TTS position across enable/disable cycles.
- Detect navigation when re-enabling TTS to prevent backward scroll.
- Catch `PlatformException` in audio toggle.
- Use unique temp paths in asset extraction to prevent SIGBUS.
- Fix race condition in `_toggleTts` that discarded the playing state.

### Developer Tools

- Harden integration test runner with signal traps, test reporter, and cleanup.
- Capture native logcat during Android integration tests.
- Clean up orphaned Chrome processes and use `web-server` device.
- Stream test output in real-time when `--verbose` is set.

### Testing

- Add Web TTS integration tests (`epub_tts_web_test.dart`).
- Add Jest test suite for the Web Speech API TTS engine.
- Replace fixed sleeps with adaptive polling and bounded pump loops in integration tests.
- Add tearDown blocks to integration tests for cleanup between tests.
- Replace stale `getPlatformVersion` template test with real `ttsCanSpeak` test.
- Add Android unit tests: `ReadiumReaderCleanupTest`, `ReadiumReaderTtsTest`, `AudiobookNavigatorReleaseTest`, `TTSNavigatorReleaseTest`, `TTSNavigatorTest`.
- Add iOS unit tests: `FlutterTTSNavigatorTests`.

### Documentation

- Document `ttsCanSpeak`, `ttsErrorType`, `ttsGetSystemVoices`, and `ttsRequestInstallVoice` in API reference.
- Document TTS position resume with `fromLocator` in the text-to-speech guide.
- Document `release()` vs `dispose()` navigator pattern.
- Document audio error handling and test isolation tearDown pattern.
- Add iOS Swift unit test documentation.
- Add troubleshooting entries for `ttsSetPreferences` iOS crash and iOS publication cleanup.

### Dependencies

- Requires `flureadium_platform_interface` ^0.6.0.

---

## 0.7.2

### Bug fixes

- **iOS / Edge tap interception (iOS 26+)**: iOS 26 changed how Flutter routes touches on
  platform views. With `enableEdgeTapNavigation = false`, no tap callbacks were set on
  `EdgeTapInterceptView`, so edge-zone touches fell through to WKWebView. Readium's
  `DirectionalNavigationAdapter` picked them up and turned the page anyway.

  Root cause: `hitTest` was gated on `onLeftEdgeTap != nil`, not on whether interception
  was wanted.

  Fix: `EdgeTapInterceptView` now has an `interceptEdgeTaps: Bool` property. `hitTest`
  checks the flag, not callbacks. `ReadiumReaderView` sets it `true` in paginated mode
  (regardless of `enableEdgeTapNavigation`) and `false` in scroll mode. `PdfReaderView`
  sets it equal to `enableEdgeTapNavigation`. When `true`, edge-zone touches never reach
  `DirectionalNavigationAdapter`; with no callbacks set, the touch does nothing. No Dart
  changes. Behaviour on iOS 13-18 is unchanged.

### Documentation

- `docs/platform-specific/ios.md`: Added the iOS 26 `interceptEdgeTaps` fix and per-mode
  behaviour (paginated always intercepts, scroll never, PDF follows
  `enableEdgeTapNavigation`).

---

## 0.7.1

### Bug Fixes

- **Example app**: Fix `setState() called after dispose()` in `_ReaderPageState` — all async
  methods (`_openEpub`, `_openAudiobook`, `_openWebPub`, `_toggleAudio`, `_nextVoice`) now check
  `mounted` before calling `setState` after an `await`.

### Developer Tools

- Add `scripts/run_integration_tests.sh` — runs integration tests for Android, iOS, and Web
  sequentially from a single command. Scans `flutter devices` once, auto-selects when only one
  device is found per platform, manages ChromeDriver automatically (npx version-matched first,
  system binary fallback), and writes per-platform logs to a gitignored `test_logs/` directory.

### Documentation

- `docs/05-testing/integration-tests.md`: Document the new test runner script; correct CI section
  (CI runs build verification only — integration tests are run locally with the script).
- `docs/platform-specific/web.md`: Mark web publication loading as work in progress with an
  accurate known issues table.

---

## 0.7.0

### New Features

- **Android / Edge tap & swipe navigation**: `setNavigationConfig()` now works on Android, matching iOS behaviour.
  A transparent overlay is placed on top of the Readium navigator (EPUB and PDF) and intercepts touches in
  the configurable left/right edge zones. Center touches always pass through to the reader content.
  - `enableEdgeTapNavigation` — tap the left/right edge to turn pages (default: enabled)
  - `enableSwipeNavigation` — horizontal fling to turn pages (default: enabled)
  - `edgeTapAreaPoints` — edge zone width in dp, clamped to 44–120 (default: 44)
  - In EPUB vertical scroll mode, all overlay gestures are automatically disabled so Readium's
    WebView can handle native scrolling; gestures are re-enabled when scroll mode is turned off.

---

## 0.6.0

### New Features

- **iOS / EPUB scroll mode**: Swipe-back now restores the last scroll position within the previous spine item.
  Previously, swiping back always landed at the start of the item. The position is stored in memory per
  spine item and restored automatically when a backward swipe is detected.
  - Explicit navigation (TOC tap, `skipToPrevious`) is unaffected — it clears the stored position for the
    target item so restoration does not override an intentional jump.
  - History is session-only; it is not persisted across app launches.
  - `onLocatorChanged` fires after restoration, so persistent position saving always reflects the
    final restored position.

---

## 0.5.0

### Breaking Changes

- **EPUBPreferences / PDFPreferences**: Navigation config fields removed. See `flureadium_platform_interface` 0.5.0 changelog for full field list.
  Requires `flureadium_platform_interface` ^0.5.0.

### New Features

- **iOS**: Add `setNavigationConfig` method channel handler in `ReadiumReaderView` and `PdfReaderView`. Navigation UX settings (edge tap, swipe, gesture disabling) are now applied via a dedicated channel call rather than being extracted from the Readium preferences map.
- **iOS**: Remove `developerConfigKeys` filtering workaround from `ReadiumReaderView` and `PdfReaderView`. Readium's `EPUBPreferences.init(fromMap:)` / `PDFPreferences.init(fromMap:)` now receive clean maps with only Readium keys.
- **iOS**: Add `FlutterNavigationConfig` Swift model for deserializing `ReaderNavigationConfig` from the method channel.

## 0.4.0

### Breaking Changes

- **iOS / PDFPreferences**: Rename `disableTextSelectionMenu` to `disableDoubleTapTextSelection`.
  Requires `flureadium_platform_interface` ^0.4.0.

### New Features

- **iOS / PDF**: Fix double-tap word selection in PDF reader. Double-tapping on PDF text no longer
  selects the word or shows the Copy/Look Up/Translate menu. Only the reader overlay controls toggle.
  Long-press text selection with the system menu remains fully functional, matching ePub behavior.
  - Root cause: `UITextNonEditableInteraction.doubleTapInUneditable:` on the lazily-created
    `PDFTextInputView` was intercepting double taps. Previous attempts failed because `PDFTextInputView`
    does not exist at `setupPDFView` time — it is added asynchronously after page rendering.
  - Fix: Deferred traversal (0.1s / 0.5s / 1.0s after `setupPDFView` and each `locationDidChange`)
    finds `PDFTextInputView` and removes `UITextNonEditableInteraction` from it.

## 0.3.4

### Bug Fixes

- **iOS**: Fix `MissingPluginException` on channel `dev.mulev.flureadium/text-locator` (and sibling event channels) when closing a publication.
  - Root cause: `EventStreamHandler.dispose()` was calling `channel.setStreamHandler(nil)` synchronously after sending `FlutterEndOfEventStream`. Flutter's answering "cancel" message arrived after the handler was already gone, producing the exception.
  - Fix: Remove the premature `setStreamHandler(nil)` call. The handler remains registered until the "cancel" round-trip completes; `onCancel` then clears the event sink. The handler is released naturally when the view is deallocated.

## 0.3.3

### New Features

- **iOS**: Add `edgeTapAreaPoints` preference to `EPUBPreferences` and `PDFPreferences` — configures edge tap zone width in absolute points (44–120pt). Replaces the previous percentage-based approach with a fixed-size zone that behaves consistently in split-screen and on all device sizes. Defaults to 44pt (iOS HIG minimum tap target) when null.
  - Requires `flureadium_platform_interface` ^0.3.1.

### Bug Fixes

- **iOS**: Fix spurious `"EPUBPreferences WARN: Cannot map property"` log warnings on every `setPreferences` call and at view init. Developer config keys (`enableEdgeTapNavigation`, `enableSwipeNavigation`, `edgeTapAreaPoints`) are now filtered out before passing the preference map to Readium's `EPUBPreferences.init(fromMap:)` and `PDFPreferences.init(fromMap:)`, which only understand Readium preference keys.
- **iOS**: Fix potential nil crash in `getCurrentLocator` when `currentLocation` returns nil inside the async task.

## 0.3.2

### Bug Fixes

- **iOS**: Fix crash on app close caused by stream handlers sending `FlutterEndOfEventStream` during `deinit`, after the Flutter engine has already torn down its channels.
  - Move all `EventStreamHandler.dispose()` calls from `deinit` to the Dart `"dispose"` method call handler, which runs while the engine is still alive.
  - `deinit` now only nils out references as a safety net without sending any messages.

### Testing

- Add `EventStreamHandlerTests` covering dispose lifecycle, double-dispose safety, send-after-dispose no-op, and listener registration/cancellation.

## 0.3.1

### Bug Fixes

- **Android EPUB**: Fix position restore drift where reopening a book would jump to a different location than the saved position.
  - Root cause: JavaScript `scrollToLocations()` recalculated progression from element bounding rect geometry, overwriting correct StateFlow value.
  - Solution: Skip `scrollToLocations()` during restore when already positioned correctly (within 1% delta), achieving iOS/Android parity.
  - Add grace period validation to suppress late locator emissions after restore settles.
  - Add fragment re-subscription on lifecycle changes to prevent stale listeners.
  - See [Saving Progress Guide](docs/guides/saving-progress.md#testing-restore-behavior) for testing documentation.

### Testing

- Add comprehensive unit tests for Android EPUB restore behavior ([EpubNavigatorRestoreTest.kt](android/src/test/kotlin/dev/mulev/flureadium/navigators/EpubNavigatorRestoreTest.kt)).
- Add manual reopen-loop validation procedure to documentation.
- Improve diagnostic logging for restore flow investigation.

## 0.3.0

- Add `renderFirstPage` API — renders the first page of a PDF as a JPEG image for use as a cover. Uses `PdfRenderer` on Android and `CGPDFDocument` on iOS. No Readium dependency needed.
- Requires `flureadium_platform_interface` ^0.3.0.

## 0.2.0

- Add swipe gesture navigation for EPUB and PDF readers on iOS — swipe left/right to turn pages in edge zones.
- Add `enableEdgeTapNavigation` and `enableSwipeNavigation` preference flags for independently controlling edge tap and swipe page navigation on iOS.
- Requires `flureadium_platform_interface` ^0.2.0.

## 0.1.1

- Fix `.pubignore` excluding `lib/src/web/` which prevented dartdoc generation on pub.dev.

## 0.1.0

- Initial public release of Flureadium.
- Full EPUB 2/3 reading with customizable typography and themes.
- PDF reading support on Android (Pdfium) and iOS (PDFKit).
- Text-to-speech with voice selection, speed, and pitch control.
- Audiobook playback with track navigation and variable speed.
- Media overlay support for synchronized read-along experiences.
- Decoration API for highlights, bookmarks, and annotations.
- ReaderWidget for embedding the reader in Flutter widget trees.
- Position tracking and saving via Locator streams.
- Cross-platform support: Android, iOS, macOS, and Web.
