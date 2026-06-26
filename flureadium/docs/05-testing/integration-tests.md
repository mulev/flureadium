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

CI runs build verification only (`.github/workflows/build-android.yml`, `build-ios.yml`, `build-web.yml`) on every push and pull request to `main`. These jobs compile the example app but do not run integration tests.

Integration tests are run locally before releases using `scripts/run_integration_tests.sh`. They are not automated in CI because emulator jobs are slow and require connected devices or booted simulators.

- **Android CI**: builds a debug APK — does not run `flutter test`
- **iOS CI**: builds without code-signing — does not run `flutter test`
- **Web CI**: builds with `flutter build web` — does not run `flutter drive`
