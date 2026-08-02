# Integration Tests

Integration tests run the example app on a real device or simulator and assert widget state and UI contracts.

## Test Files

| File | Platforms | What it asserts |
|---|---|---|
| `all_tests.dart` | Android, iOS | Combined runner — imports all files below into a single compilation unit |
| `all_tests_android_ci.dart` | Android (CI) | CI runner — excludes TTS, audiobook, and WebPub tests requiring hardware audio or network |
| `all_tests_web.dart` | Web | Web-specific runner — only includes tests that pass on web (see note below) |
| `launch_test.dart` | All | App starts, MaterialApp renders |
| `epub_test.dart` | Android, iOS | EPUB auto-opens, navigation/prefs/highlight don't crash, TTS sentence nav buttons appear, close removes widget |
| `audiobook_test.dart` | Android, iOS (`@Tags(['native'])`) | Audiobook opens, play changes button label, seek doesn't crash, pause/resume button labels cycle correctly, playing the last track to its end surfaces `TimebasedState.ended` |
| `cbz_test.dart` | Android, iOS | CBZ auto-opens, navigation works, `goToLocator` reaches an image page, `extractPageThumbnail` returns JPEG bytes/null as appropriate |
| `divina_test.dart` | Android, iOS | DIVINA auto-opens, `ReadiumReaderWidget` present, left/right navigation works |
| `webpub_test.dart` | Android, iOS | Remote WebPub manifest opens, `ReadiumReaderWidget` present |

> **Always use `all_tests.dart` (mobile) or `all_tests_web.dart` (web) when running the full suite.** Running `flutter test integration_test/` without specifying a file compiles and installs each test file as a separate APK batch. On mobile this reinstalls the app mid-run, killing in-progress tests and causing "did not complete" failures for any tests that were running when the new APK landed.

> **Web test coverage is limited.** `epub_test.dart` and `webpub_test.dart` are excluded from `all_tests_web.dart` because publication loading on web is not yet reliable (see [Web Platform](../platform-specific/web.md)). The web suite currently covers app launch only. These tests will be added back as web support matures.

## Note on EventChannel streams

### Android

All four EventChannels (`reader-status`, `error`, `text-locator`, `timebased-state`) are
registered eagerly in `ReadiumReader.attach()` at activity attach time — before
`openPublication` is called.

### iOS

`reader-status`, `text-locator`, and `error` EventChannels are registered lazily inside
`ReadiumReaderView.init()`, which is called from `_onPlatformViewCreated` in the Flutter
widget layer. This means the native handlers do not exist until the platform view has been
created and added to the widget tree.

Subscribing before this point causes `MissingPluginException`, which permanently closes
`receiveBroadcastStream()`'s internal `StreamController`, silently dropping all subsequent
events on that channel.

### Safe subscription via onReady

The example app subscribes to streams inside `_subscribeToChannels()`, which is passed as
`onReady` to `ReadiumReaderWidget`. `onReady` fires synchronously from `_onPlatformViewCreated`
on iOS and Android (after `setCurrentWidgetInterface(this)`) and via `addPostFrameCallback` on
web. Because no `Future.delayed` timers are involved, `pumpAndSettle` settles as soon as
the reader is ready — no polling, no fixed waits.

```dart
ReadiumReaderWidget(
  publication: pub,
  onReady: _subscribeToChannels,
)
```

### Integration test implications

Integration tests use widget-based assertions (widget presence, button label changes) because
streams deliver events asynchronously. Test timing does not guarantee stream delivery within
`pump()` windows. The decoration test specifically relies on `_locator` being populated within
a 5-second `pumpAndSettle` window — this works because `onReady` ensures the channel is
active before the reader starts emitting locator events.

## Bounded polling with `pumpUntil`

Most tests wait for an async signal — the reader widget mounting, a button label
flipping once native playback starts. `pumpAndSettle` can't be used here: a
`CircularProgressIndicator` or a WebView keeps scheduling frames, so it never
settles. The pattern is to pump on a fixed tick and stop once the signal shows,
with a wall-clock ceiling as a safety bound.

`integration_test/helpers/pump_until.dart` holds the shared helper:

```dart
await pumpUntil(
  tester,
  () => find.byType(ReadiumReaderWidget).evaluate().isNotEmpty,
  timeout: const Duration(seconds: 15),
);
```

It pumps every `interval` (250ms by default) until the condition holds or the
cumulative time reaches `timeout`, then returns whether the condition held. It
pumps first and checks after, so a caller keeps the same ceiling it had as a
hand-rolled loop — only the tick shrinks. At the old 1-second granularity a
condition met at 200ms still cost a full second; at 250ms it costs one tick.

Conventions:

- **Every bounded poll uses `pumpUntil`** with its own `timeout`. Keep the
  ceiling that the test needs (15s for a reader mount, 60s for Android TTS
  cold-start, and so on) — the helper only changes the tick, never the ceiling.
- **Settle waits stay explicit.** A fixed `await tester.pump(const Duration(seconds: 3))`
  after a tap, with no condition to break on, is a deliberate real-time wait.
  Leave those as bare `pump` calls — converting them would change timing and
  risk races.
- **A specialised poll that needs an async body** (CBZ's `_waitForCbzReaderReady`
  awaits `getCurrentLocator()` each tick and returns the `Locator`) stays a
  hand-rolled loop, but ticks at the same 250ms so its granularity matches.

## Jumping to the last track instead of skipping to it

The end-of-book audiobook test needs the last reading-order track. Stepping there
with repeated `Audio Next Chapter` taps cost one poll per track. Load the manifest
and jump straight to the end instead:

```dart
final path = await _extractAsset('assets/pubs/38533.audiobook');
final pub = await Flureadium().loadPublication(path);
await Flureadium().goByLink(pub.readingOrder.last, pub);
```

`loadPublication` only parses the manifest, so it is cheap; `goByLink` is the same
navigation the app performs. The near-end seek and natural play-out that follow
stay as they are — that tail is real audio time and is the point of the test.

Note the audiobook is still opened through the button flow (boot the default EPUB,
tap `Open AudioBook`), not a direct `initialAsset` boot. On Android the reader
widget hosts a visual navigator and an audiobook has none, so it must ride on an
EPUB host; audio plays on top. CBZ and DIVINA are image publications with their own
navigator, so those groups can and do boot directly via `initialAsset`.

## Sharing one app boot across a group with `ensureAppShowing`

Booting the app and opening a publication is the largest fixed cost each test
pays. Tests in a group open the same publication type, so they can boot once and
reuse the running app between tests instead of tearing it down and starting over.

For that, a helper needs one signal every open exposes so it can tell when the
switch to the next publication has finished. `_openPublicationAsset` in
`example/lib/main.dart` now bumps `_openGeneration` and resets `_endedSeen` in
its `setState`, matching what `_openAudiobook` already did. So whether a
publication opens at cold boot or from an `Open …` button tap, the
`open-generation` counter increments once it has loaded, and `ended-seen` starts
clean.

`integration_test/helpers/ensure_app_showing.dart` turns that into the group
helper:

```dart
await ensureAppShowing(
  tester,
  initialAsset: 'assets/pubs/sample_comic.cbz',
  reopenButton: 'Open CBZ',
);
```

The first call in a suite finds no app on screen and cold-boots via
`initialAsset`. Later calls find the app already up, tap `reopenButton`, and poll
`open-generation` until it bumps. Whether the app is already showing is read from
the widget tree — the reader view is mounted, or (after a `tearDown` that closed
the publication) the control bar with the reopen button is showing — so no
module-level flag leaks across files or suite re-runs.

Conventions:

- **`tearDown` does not close the publication.** Switching publications is the
  next test's job, done through `ensureAppShowing` tapping an `Open …` button —
  exactly what a user opening another book does. The app's own open path releases
  the previous publication on the main thread as the reader rebuilds. Closing the
  container in `tearDown` while the reader widget is still mounted is a sequence
  the app never performs; on Android it races the live WebView still reading the
  container and crashes the process (`flureadium-i0s`). Audio groups still call
  `Flureadium().stop()` in `tearDown` to halt playback — that touches the player,
  not the container.
- **A reused app carries state.** Assert that anything a test depends on is reset
  on reopen (the `open-generation` bump and `ended-seen` reset are the loaded
  signal; check any other state your test reads). Every `Open …` opener resets
  TTS, audio, `ended-seen`, and the audio-error latch in its `setState`, so a
  reopen gives each test a clean slate.

### Audiobooks: boot a host EPUB, then open the audiobook

An audiobook has no visual navigator, so on Android it cannot be a direct
`initialAsset` boot — it rides on an EPUB host. `ensureAppShowing` takes
`openAfterColdBoot` for this: the group cold-boots the host EPUB and then taps
the audiobook's `Open …` button, so both the cold-boot and reuse paths finish on
a freshly opened audiobook.

```dart
await ensureAppShowing(
  tester,
  initialAsset: 'assets/pubs/moby_dick.epub',
  reopenButton: 'Open AudioBook',
  openAfterColdBoot: true,
);
```

The audiobook group wraps this in a local `showAudiobook(tester, button: …)` so
variant tests (`Open AudioBook NoTitle`/`BadUrl`/`BadStream`) reuse the same boot
path and just pass their own button.

This is applied to all four group test files (`audiobook`, `cbz`, `divina`,
`epub_tts`) — each boots once per group and reuses the running app between tests.

## Prerequisites

### Android
- Flutter SDK (stable channel)
- Android SDK with a connected device or AVD at API level ≥ 29
- A configured system TTS engine for the EPUB TTS tests. The runner pins Google
  TTS (`tts_default_synth = com.google.android.tts`) before the Android leg, so
  a cold-booted or wiped emulator doesn't report an empty voice list. If voices
  are still empty, install the engine's voice data (Settings → System →
  Languages & input → Text-to-speech output).

### iOS
- Flutter SDK (stable channel)
- Xcode ≥ 15
- CocoaPods
- A connected device or booted simulator (iOS ≥ 16)

### Web
- Flutter SDK (stable channel)
- Chrome or Chromium installed

## Test Runner Script

`scripts/run_integration_tests.sh` runs all three platforms sequentially from a single command. It continues after failures and writes logs to a gitignored `test_logs/` directory.

> To run this suite together with the Dart unit and native suites in one command, use the [God-Tier Test Runner](all-tests.md).

```bash
# Run all platforms (prompts for device IDs interactively)
./scripts/run_integration_tests.sh

# Provide device IDs upfront (non-interactive)
./scripts/run_integration_tests.sh \
  --android-device emulator-5554 \
  --ios-device "iPhone 16 Pro"

# Skip platforms you don't have available
./scripts/run_integration_tests.sh --skip-android --skip-web

# Show full flutter output instead of pass/fail summary
./scripts/run_integration_tests.sh --verbose

# ChromeDriver is managed automatically. The script will try:
#   1. npx chromedriver@<detected-chrome-major> --port=4444 (version-matched)
#   2. System chromedriver binary (if on PATH, fallback)
# If both fail, you are prompted with manual instructions and offered the
# option to skip web tests and continue with Android/iOS.

./scripts/run_integration_tests.sh --help
```

Logs are written to `test_logs/run_<timestamp>/` (gitignored, pubignored):

| File | Contents |
|---|---|
| `summary.log` | Pass/fail lines and failure output for all platforms |
| `android.log` | Full flutter output for the Android run (full suite, including `@native`) |
| `ios.log` | Full flutter output for the iOS run |
| `web.log` | Full flutter output for the Web run |

## Running Tests Manually

```bash
# Android — full suite (one build, one install, no mid-run APK swap)
cd flureadium/example
flutter test integration_test/all_tests.dart -d <device-id>

# Android — exclude audiobook tests (native-only)
flutter test integration_test/all_tests.dart -d <device-id> --exclude-tags native

# iOS simulator — full suite
cd flureadium/example
flutter test integration_test/all_tests.dart -d "iPhone 15"

# Web (Chrome) — requires ChromeDriver matching your Chrome version
# flutter test does not support web for integration tests; use flutter drive instead
cd flureadium/example
dart run flureadium:copy_js_file web/

# Start ChromeDriver in a separate terminal:
#   npx chromedriver@<your-chrome-major-version> --port=4444
# Then run:
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/all_tests_web.dart \
  -d chrome \
  --profile

# Run a single test file (for focused debugging)
flutter test integration_test/epub_test.dart -d <device-id>
```

## CI

CI runs the full test matrix on every push and pull request to `main`:

- **`test.yml`** — Dart unit tests for all three packages (`flutter test`), the Android Kotlin/Robolectric suite (`:flureadium:testDebugUnitTest`, JVM — no emulator), and the iOS Swift/XCTest suite (`RunnerTests` via `xcodebuild test` on a simulator).
- **`integration-test.yml`** — the integration suites on real emulators/simulators: Android (`all_tests_android_ci.dart` on an API-33 emulator), iOS (`all_tests.dart` on a booted simulator), and Web (`all_tests_web.dart` via `flutter drive`). Runs on push and PRs, plus on demand via `workflow_dispatch`.
- **`build-android.yml` / `build-ios.yml` / `build-web.yml`** — compile-only build verification of the example app.

The Android integration bundle (`all_tests_android_ci.dart`) intentionally omits the `@native` audiobook, EPUB-TTS, and WebPub tests because GitHub-hosted emulators lack reliable audio and network; those still run on the iOS leg and locally via `scripts/run_integration_tests.sh`. The web bundle (`all_tests_web.dart`) runs the launch smoke test live and bundles `epub_tts_web_test.dart` with its tests skipped in-file until the web-reader TTS plumbing lands (tracked in [Web Platform](../platform-specific/web.md)).

### When the iOS job stalls before any test runs

On a simulator, `flutter_tools` learns the Dart VM service URL one way only: it scrapes a single line out of `xcrun simctl spawn <udid> log stream`. There is no mDNS fallback, and the wait has no timeout. When that one log record does not reach the tool, the app boots and idles normally while the tool waits forever.

What it looks like: `flutter test` prints `Waiting for VM Service port to be available...`, nothing follows, and the run sits there until CI kills the step. Ten runs died this way between March and August 2026, most of them cancelled at GitHub's six-hour default.

Two things bound it now:

- `example/dart_test.yaml` sets `suite_load_timeout: 10m`. Loading the suite takes about six minutes on a healthy CI run, so a stalled load fails at ten with a `TimeoutException` instead of hanging. `test_core` enforced a 12-minute default here until 0.6.16 removed it. The key sits under `on_os: mac-os`, since only a macOS host runs an iOS simulator — on the Linux runners the file loads to an empty configuration.
- The iOS job retries once, and only for this failure. `.github/scripts/ios_suite_load_timed_out.sh` checks whether the timeout landed on the `loading ...` pseudo-test, which is what separates a lost VM service URL from a test that overran its own timeout. Compile errors and assertion failures are not retried, since a second run of those just costs another ten minutes.

`.github/scripts/ios_suite_load_timed_out_test.sh` covers the predicate. It replays trimmed event streams for the four failure modes that have to be told apart — suite-load timeout, compile failure, assertion failure, test-body timeout — plus a passing run, a load timeout in a later suite, and empty, truncated and missing event files. The first four came off real `flutter test` runs; the rest are written by hand. `Test Example (Widget)` runs it in CI, and it takes about a second locally.

### When the Android job stopped partway and still said everything passed

Fixed on 2026-08-02. Kept here because the shape is worth recognising: the suite would die
mid-flight in roughly one run in fifteen, everything left would flush as a pass in the same
millisecond, and `flutter test` would exit 1 after printing `N tests passed.`

That output is less contradictory than it reads. `test_core`'s GitHub reporter prints the success
line whenever nothing is in `Engine.failed`, and `Engine.success` returns null — which the runner
treats as failure — when the engine is closed before every test has finished. The pair means the
run was torn down early with nothing marked failed.

Three occurrences going back to June captured nothing, so none could be diagnosed. The fourth ran
with `logcat` and a `--file-reporter` event stream and gave up the cause immediately: the app
process was taken down by `FATAL EXCEPTION: main`, `java.lang.IllegalStateException: zip file
closed`.

Closing a publication while the image navigator is still loading a page closes the backing
`ZipFile` underneath an in-flight read. Fragment removal cancels readium's page fragment, but
cancellation is cooperative and a read already inside `withContext(Dispatchers.IO)` keeps going.
It reaches `ZipFile.ensureOpen` and throws. readium 3.1.2's `FileZipContainer.Entry.read()`
catches only `ZipException` and `IOException`, so that throw escapes the `Try` the method
declares, and it surfaces in `R2CbzPageFragment`, which reads from a parentless root coroutine —
no handler anywhere in the chain, so Android kills the process.

The fix is `Resource.catchingClosedContainer()` in `ReadiumExtensions.kt`, applied outermost in
the `TransformingContainer` that `ReadiumReader.assetToPublication` already installs. It reports
that one throw as a `ReadError`, which is what readium's own signature promises. It is
deliberately narrow: any other runtime failure belongs to our transformers or to a navigator and
has to stay loud. `ResourceClosedContainerTest` covers it, including that `CancellationException`
still propagates — it subclasses `IllegalStateException`, so a careless guard would swallow it.

What no test covers is the wiring: that the guard is actually installed on the container the
navigator reads through. I first assumed the CBZ integration tests covered it. They do not.
Five green runs with diagnostics kept show the guard logging `Read after the container closed`
zero times across 105 publication closes, so the suite passes without ever entering the guarded
path. Absence of the crash in those runs is close to meaningless on its own: at the historical
rate of one abort in fifteen runs, five clean runs happen about 71% of the time with no fix at
all, and reaching 95% confidence by sampling would take roughly 45 runs.

What would settle it is a test that closes a publication while a page load is genuinely in
flight, rather than waiting for CI to roll the dice. Tracked as `flureadium-pbc`, which stays
open until then.

The capture lives in `.github/scripts/android_integration_tests.sh`, not inline in the workflow. `reactivecircus/android-emulator-runner` splits its `script:` input on newlines and runs each line in a separate `sh -c`, so a multi-line body loses its variables, its `set` flags and its line continuations, and a trailing `\` arrives as a literal argument. Give that action one command. `android_integration_tests_test.sh` covers the wrapper and fails if the workflow turns the input back into a block; `Test Example (Widget)` runs it.

## In-car testing (CarPlay / Android Auto)

The in-car browse/search/play surface is covered automatically as far as it can be without a head unit, and the rest is a documented, reproducible manual pass.

### Automated (runs in CI)

- **Dart unit** (`flureadium_platform_interface/test/car/`) — the car value types, the `CarContentProvider` contract, and the `CarContentTransport` channel round-trip incl. the cold "app-not-ready" path.
- **Android Robolectric** (`android/src/test/.../car/` + `PluginLibrarySessionCallbackTest`) — `NodeBrowseTree` node→`MediaItem` mapping, the `MethodChannelCarContentSource` decode + cold-start retry, and the `MediaLibraryService` callback (browse tree, `onSearch`/`notifySearchResultChanged`, chapter-seek vs library-play).
- **iOS XCTest** (`example/ios/RunnerTests/Car*Tests.swift`) — the `CarTemplateRenderer`, `CarListItemFactory`, model decoders, and `CarPlayContentBridge` cold-start retry/decode.
- **Integration** (`example/integration_test/car_transport_test.dart`) — a stub `CarContentProvider` driven through the real `dev.mulev.flureadium/car` channel on a device/simulator, asserting the end-to-end transport round-trip. Bundled into `all_tests.dart` and `all_tests_android_ci.dart`, so it runs on the CI Android emulator and iOS simulator.

### Manual device surfaces

These need a head unit and are run by hand; they are not in CI.

- **iOS CarPlay** — run the example on the iOS Simulator, then **I/O ▸ External Displays ▸ CarPlay**. Requires the CarPlay audio entitlement + a development provisioning that grants it. Tap through Continue / Library / Search and confirm the `carMain` round-trip in the device log.
- **Android Auto** — requires a **physical Android phone** (Android 8+) with the real Android Auto app plus the Desktop Head Unit (DHU). The Android-Auto app shipped on Google Play emulator images is a `-stub` and the Play listing reports it "not compatible", so the emulator is a dead end for Android Auto.
- **Android Automotive OS (AAOS)** — the AAOS emulator runs media apps directly, but only recognizes an app as a media source if it is built as an **automotive** app (`<meta-data android:name="com.android.automotive">` + `automotive_app_desc`, `<uses-feature android:name="android.hardware.type.automotive">`, `android:appCategory="audio"`, and **no** `MAIN`/`LAUNCHER` activity — a separate build from the Android-Auto one). The example is an Android-Auto build, so on AAOS it appears in the app grid, not the media center. An AAOS automotive build of the example is not provided yet.

### Real device + real car

End-to-end validation on physical phones and real cars is done **downstream in the consuming app**, which integrates this plugin and is tested on real hardware. flureadium's bar is the automated coverage above plus the reproducible manual surfaces; it does not attempt to fake a real head unit in CI.
