# Integration Tests

Integration tests run the example app on a real device or simulator and assert widget state and UI contracts.

## Test Files

| File | Platforms | What it asserts |
|---|---|---|
| `all_tests.dart` | Android, iOS | The only mobile runner — imports every file below into a single compilation unit. CI narrows it with `--exclude-tags`, never with a second import list |
| `all_tests_web.dart` | Web | Web-specific runner — only includes tests that pass on web (see note below) |
| `launch_test.dart` | All | App starts, MaterialApp renders |
| `epub_test.dart` | Android, iOS | Each case opens its own EPUB, navigation/prefs don't crash, TTS sentence nav buttons appear, close removes widget |
| `decoration_contract_test.dart` | Android, iOS | A decoration built from the reader's real current locator is accepted, a malformed one raises a `PlatformException` naming the decoration, and the example's Highlight button leaves the reader ready at the same position |
| `text_locator_test.dart` | Android, iOS | A page turn is pushed on the text-locator stream, the stream follows a publication swap, a swap to audio leaves no locator behind, and a subscriber that arrives after the reader already has a position is answered on subscribe |
| `audiobook_host_test.dart` | Android, iOS | An audio-only publication mounts and reports `ready` from a host with no navigator. Split from `audiobook_test.dart` because it needs no player, so it runs where audio does not work |
| `audiobook_test.dart` | Android, iOS (`native`) | Audiobook opens, play changes button label, seek doesn't crash, pause/resume button labels cycle correctly, playing the last track to its end surfaces `TimebasedState.ended` |
| `cbz_test.dart` | Android, iOS | CBZ auto-opens, navigation works, `goToLocator` reaches an image page, `extractPageThumbnail` returns JPEG bytes/null as appropriate |
| `divina_test.dart` | Android, iOS | DIVINA auto-opens, `ReadiumReaderWidget` present, left/right navigation works |
| `webpub_test.dart` | Android, iOS (`network`) | Remote WebPub manifest opens, `ReadiumReaderWidget` present |
| `error_handling_test.dart` | Android, iOS | A corrupted file and a missing file both raise `ReadiumException`, and (Android only) a failed native enable reports `error` instead of killing the app — see [Forcing a reader failure](#forcing-a-reader-failure) |
| `tap_test.dart` | Android | A content tap is reported once through `onTap` with a position, a hyperlink tap navigates and reports nothing, a plain page in the same book does report, and a publication swap rebinds the listener. Android only, and reflowable only — see [What a synthesized tap can reach](#what-a-synthesized-tap-can-reach) |

### Tags

A test declares what it needs; a runner declares what it has. CI excludes on
that, so a new test file is picked up by default.

| Tag | Means | Excluded by |
|---|---|---|
| `native` | Needs a real audio or TTS engine | Android CI |
| `network` | Needs the public internet | Android CI |

Tags go on the test (or on a per-file wrapper around `testWidgets`), **not** as
a library-level `@Tags` annotation. An annotation only reaches the runner when
the file *is* the suite; once `all_tests.dart` imports it, it is ignored. The
`@Tags` lines still at the top of `audiobook_test.dart` and `epub_tts_test.dart`
apply when those files are run directly and nowhere else.

Android CI ran a second aggregator with a hand-maintained import list until
2026-08. Leaving a file out of it was invisible — no error, the tests simply
never ran — and that is how the entire audiobook group, including the
audio-only readiness regression, went unrun on Android for months
(flureadium-29l).

> **Always use `all_tests.dart` (mobile) or `all_tests_web.dart` (web) when running the full suite.** Running `flutter test integration_test/` without specifying a file compiles and installs each test file as a separate APK batch. On mobile this reinstalls the app mid-run, killing in-progress tests and causing "did not complete" failures for any tests that were running when the new APK landed.

> **Web test coverage is limited.** `epub_test.dart` and `webpub_test.dart` are excluded from `all_tests_web.dart` because publication loading on web is not yet reliable (see [Web Platform](../platform-specific/web.md)). The web suite currently covers app launch only. These tests will be added back as web support matures.

## What a synthesized tap can reach

`tap_test.dart` proves the tap chain the plugin exposes as `onTap`: a real touch
on the platform view, filtered by Readium so links and other interactive
elements never surface, back into Dart. It runs on Android and on reflowable
EPUB only. Both limits were measured while writing the suite, and neither is a
preference — read this before writing a tap case for another platform or
publication type, because the two dead ends below look identical from Dart.

**Android reflowable works, and here is why.** The example app builds the reader
through `PlatformViewLink` + `AndroidViewSurface`, whose render object is a
`PlatformViewRenderBox`. With an empty `gestureRecognizers` set the platform
view is the only arena member, so it wins the tap
(`rendering/platform_view.dart:68-69`), and `AndroidViewController` converts the
pointer into a real `MotionEvent` posted over the `platform_views` channel
(`services/platform_views.dart:916-918`). From there it is an ordinary Android
touch: it lands in the Readium WebView, the JavaScript gesture layer runs, and
`InputListener.onTap` fires.

**iOS cannot be driven at all.** `UiKitView` builds a `RenderUiKitView`, whose
`handleEvent` adds the pointer to the gesture arena and, on winning, calls
`controller.acceptGesture()` (`rendering/platform_view.dart:453-460`,
`:548-550`). That releases the *real* `UITouch` sequence to the embedded view —
there is no synthesized-pointer path, and `WidgetTester` never produces a
`UITouch`. This is a Flutter injection-layer fact, not a hardware one, so the
simulator does not help. An iOS tap case needs a separate XCUITest target.

**Android fixed layout is not driven by a synthesized touch either.** This one
is easy to mistake for a broken fixture, because the touch demonstrably arrives:
`EdgeTapInterceptView.dispatchTouchEvent` logs the `ACTION_DOWN` with
`claimed=false` for a fixed-layout publication exactly as it does for a
reflowable one, so the event reached the native view and passed the edge
overlay. It is then dropped above that, inside the fixed-layout script path.
Five taps three seconds apart on `fixed_layout.epub` reported nothing, while
`adb shell input tap` at the same point reported immediately — the fixture and
the chain are both fine.

What is left is handed over as the `user | tap` row in `validators.conf`: every
iOS case, plus fixed layout and PDF on both platforms. `./validate list user`
prints it, and the checklist itself lives in the phase 5 plan slice.

A useful side effect of the measurement: `onTap`'s `Offset` is in **logical
pixels, origin at the top-left of the platform view**. A tap at raw
(540, 1200) on a 1080x2400 emulator at density 2.625 reported `205.7, 457.1`.

## Forcing a reader failure

`error_handling_test.dart`'s `Reader failure` group proves the app survives a
failed native enable and tells the host about it. Nothing in the asset set
fails on its own: an audiobook resolves to an audio host, a cbz or divina
resolves to an image reader, and every EPUB opens. The failure has to be built
from the outside, so the example app carries two debug buttons for it.

**Close Native Only** closes the publication natively and leaves `_publication`
alone, so the Dart reader widget stays mounted over a publication native has
already dropped. The existing **Close** button cannot stand in for it: it also
nulls `_publication`, which takes the reader out of the tree.

**Remount Reader** bumps a counter used as the reader widget's `ValueKey`.
`ReadiumReaderWidget.didUpdateWidget` rebuilds the native view whenever it gets
a `Publication` that is not `identical` to the previous one, but here the
instance has not changed, so it returns early and nothing reaches native.
Changing the key replaces the element, which runs native `init` again — this
time over a closed publication, where `epubEnable` throws "Publication not
opened cannot enable epub".

The group is untagged on purpose. It needs no audio engine and no network, so
Android CI runs it, and Android is the only platform where the failure exists.
On iOS, `ReadiumReaderViewFactory.create` with no publication open falls
through to `ReadiumReaderView`, which builds an empty EPUB navigator instead of
throwing, and the status would go to `ready` — hence `skip: Platform.isIOS`.

The group reopens the EPUB before it finishes. The reader widget stays mounted
between groups in `all_tests.dart`, and this file runs eighth of eleven, so
leaving a dead reader behind would break everything after it. Reopening is
enough on its own: the new publication is a different instance, so
`didUpdateWidget` rebuilds the view without a second remount tap.

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
with repeated `Audio Next Chapter` taps cost one poll per track. Take the last
link from the reading order and jump straight to it instead:

```dart
await Flureadium().goByLink(audiobookPub.readingOrder.last, audiobookPub);
```

`audiobookPub` is the publication the group already loaded in `setUpAll` through
the shared `extractAsset` helper. `goByLink` resolves the link against that
manifest and navigates — it never reopens the publication it is handed, so the
book the test is listening to is untouched. The near-end seek and natural play-out
that follow stay as they are: that tail is real audio time and is the point of the
test.

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

### Every suite opens the publication it asserts about

`app.main()` followed by a wait for the reader widget does not open anything.
`main()` is `runApp(ExampleApp(...))`, and `runApp` with an unchanged widget
type reuses the existing element, so `_ReaderPageState.initState` never runs a
second time. `initState` holds the app's only automatic open. The reader that
the wait finds is the one the previous suite left mounted, still carrying that
publication's `reader-status` and locator latches.

Run such a file on its own and it looks correct: nothing is on screen yet, so
the boot is real and the fixture is the right one. Run it inside
`all_tests.dart` and the same code asserts against whichever book ran before
it. That is what happened to `epub_test.dart`'s long-press case on iOS. Its
wait for `ready` was answered by the audiobook group's latched `ready`, the
EPUB view's own `init` reported `loading` a moment later, and the assertion
after the long press read `loading` (flureadium-5ki).

So every case opens its own fixture, with `openAfterColdBoot: true` so the
`Open …` tap happens on the cold-boot arm too:

```dart
await ensureAppShowing(
  tester,
  initialAsset: 'assets/pubs/moby_dick.epub',
  reopenButton: 'Open EPUB',
  openAfterColdBoot: true,
);
```

The open runs `_resetPublicationLatches`, so `reader-status`, the locator and
the saved locator all start empty. A test then measures the reader it opened
rather than a value it inherited.

### Audiobooks: boot the audiobook directly

On Android an audiobook mounts the reader widget as an audio-only host: no visual
navigator is enabled, and the widget reports itself ready on its own, so it is an
ordinary `initialAsset` boot. The audiobook group cold-boots the audiobook itself
on both platforms — iOS has no audio reader kind yet, so `ReaderViewKind` resolves
an audiobook to `.epub` and builds a content-less EPUB navigator over the audio
tracks. That navigator does not crash and nothing renders through it either way,
which is why iOS survives the direct boot; giving iOS the same audio-only host is
`flureadium-5wu`.

The group still passes `openAfterColdBoot`, for a different reason than before:
its tests open five publications through five buttons, and the flag makes the
cold-boot path tap the button too, so whichever test runs first gets the
publication it asked for.

```dart
await ensureAppShowing(
  tester,
  initialAsset: 'assets/pubs/38533.audiobook',
  reopenButton: 'Open AudioBook',
  openAfterColdBoot: true,
);
```

The audiobook group wraps this in a local `showAudiobook(tester, button: …)` so
variant tests (`Open AudioBook NoTitle`/`Streamed`/`BadUrl`/`BadStream`) reuse the
same boot path and just pass their own button.

The cold-boot arm only runs when the app is not already on screen, so the direct
boot happens in a standalone `flutter test integration_test/audiobook_test.dart`
run. In `all_tests.dart` the launch group boots first and the audiobook group
takes the reuse path, and Android CI excludes the group by tag — so no CI leg
exercises the audiobook boot (`flureadium-p1q`).

The same pattern covers `audiobook`, `cbz`, `divina`, `epub_tts`, `text_locator`
and `epub` — each group boots once and reuses the running app between tests.

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
- **`integration-test.yml`** — the integration suites on real emulators/simulators: Android (`all_tests.dart` with `--exclude-tags "native || network"` on an API-33 emulator), iOS (`all_tests.dart` on a booted simulator, no exclusions), and Web (`all_tests_web.dart` via `flutter drive`). Runs on push and PRs, plus on demand via `workflow_dispatch`.
- **`build-android.yml` / `build-ios.yml` / `build-web.yml`** — compile-only build verification of the example app.

Android CI drops the `native` and `network` tags because GitHub-hosted emulators have no audio or TTS engine and no route to the public internet. Those tests still run on the iOS leg and locally via `scripts/run_integration_tests.sh` — so a green Android CI run says nothing about them. The web bundle (`all_tests_web.dart`) runs the launch smoke test live and bundles `epub_tts_web_test.dart` with its tests skipped in-file until the web-reader TTS plumbing lands (tracked in [Web Platform](../platform-specific/web.md)).

The three tags in use — `native`, `network` and `web` — are declared in `example/dart_test.yaml`. Declaring a tag selects nothing; it only tells the runner the tag is intentional. A tag used in a test but missing from that file makes every device run print `Tags were used that weren't specified in dart_test.yaml` followed by a line per tagged test, which is 28 lines of noise on top of the suite output. Add a new tag there in the same run that introduces it.

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
the throw as a `ReadError`, which is what readium's own signature promises. It is deliberately
narrow: any other runtime failure belongs to our transformers or to a navigator and has to stay
loud. `ResourceClosedContainerTest` covers it, including that `CancellationException` still
propagates — it subclasses `IllegalStateException`, so a careless guard would swallow it.

`java.util.zip` reports this in two ways, and the first version of the guard only knew about one
of them. Before the entry stream opens, `ZipFile.ensureOpen` throws
`IllegalStateException("zip file closed")`. Once the read is streaming, the close has also ended
the `Inflater`, and `Inflater.ensureOpen` throws `NullPointerException("Inflater has been
closed")` instead. Same race, same container, and the second one killed a run on a build that
was supposed to be fixed.

The capture lives in `.github/scripts/android_integration_tests.sh`, not inline in the workflow. `reactivecircus/android-emulator-runner` splits its `script:` input on newlines and runs each line in a separate `sh -c`, so a multi-line body loses its variables, its `set` flags and its line continuations, and a trailing `\` arrives as a literal argument. Give that action one command. `android_integration_tests_test.sh` covers the wrapper and fails if the workflow turns the input back into a block; `Test Example (Widget)` runs it.

### Proving a race is fixed

Worth reading if you ever have to do this again, because the obvious approach does not work.

Green runs prove very little about a fault that appears in one run in fifteen: five clean runs
happen about 71% of the time with no fix at all, and reaching 95% confidence by sampling alone
would take roughly 45 runs. Five were run anyway, and the guard logged `Read after the container
closed` zero times across 105 publication closes — the suite never entered the guarded path, so
those runs said nothing either way.

Racing the real crash path from Dart did not work either. Firing `goToLocator` and closing
underneath it left a window a few milliseconds wide, and two runs on a deliberately unguarded
build both passed.

What works is `reads outliving closePublication fail soft, not fatal` in `cbz_test.dart`. It
fires sixteen unawaited `extractPageThumbnail` calls and closes the publication under them, three
times over. Each call captures the publication and then goes to the container, so enough of them
in flight guarantees some are mid-read when the close lands. It does not need the fatal variant:
the same throw reaches `dispatchGuarded` on this path and comes back as a `PlatformException`,
which fails the test just as well.

Verified by running the identical test on two branches differing by the single line that installs
the guard. Unguarded: three of three failed, all three hitting the throw, one escalating to
`FATAL EXCEPTION` and taking 32 tests with it. Guarded: three of three passed, with the guard
logging exactly twice per run. That is what closed `flureadium-pbc`.

The same fault was reported once before as `flureadium-i0s`, through the EPUB WebView rather than
the image navigator, and was closed by changing test teardown so it stopped closing publications.
That moved it rather than fixing it, and it came back through another reader four months later.

## In-car testing (CarPlay / Android Auto)

The in-car browse/search/play surface is covered automatically as far as it can be without a head unit, and the rest is a documented, reproducible manual pass.

### Automated (runs in CI)

- **Dart unit** (`flureadium_platform_interface/test/car/`) — the car value types, the `CarContentProvider` contract, and the `CarContentTransport` channel round-trip incl. the cold "app-not-ready" path.
- **Android Robolectric** (`android/src/test/.../car/` + `PluginLibrarySessionCallbackTest`) — `NodeBrowseTree` node→`MediaItem` mapping, the `MethodChannelCarContentSource` decode + cold-start retry, and the `MediaLibraryService` callback (browse tree, `onSearch`/`notifySearchResultChanged`, chapter-seek vs library-play).
- **iOS XCTest** (`example/ios/RunnerTests/Car*Tests.swift`) — the `CarTemplateRenderer`, `CarListItemFactory`, model decoders, and `CarPlayContentBridge` cold-start retry/decode.
- **Integration** (`example/integration_test/car_transport_test.dart`) — a stub `CarContentProvider` driven through the real `dev.mulev.flureadium/car` channel on a device/simulator, asserting the end-to-end transport round-trip. Untagged, so it runs on the CI Android emulator and the iOS simulator.

### Manual device surfaces

These need a head unit and are run by hand; they are not in CI.

- **iOS CarPlay** — run the example on the iOS Simulator, then **I/O ▸ External Displays ▸ CarPlay**. Requires the CarPlay audio entitlement + a development provisioning that grants it. Tap through Continue / Library / Search and confirm the `carMain` round-trip in the device log.
- **Android Auto** — requires a **physical Android phone** (Android 8+) with the real Android Auto app plus the Desktop Head Unit (DHU). The Android-Auto app shipped on Google Play emulator images is a `-stub` and the Play listing reports it "not compatible", so the emulator is a dead end for Android Auto.
- **Android Automotive OS (AAOS)** — the AAOS emulator runs media apps directly, but only recognizes an app as a media source if it is built as an **automotive** app (`<meta-data android:name="com.android.automotive">` + `automotive_app_desc`, `<uses-feature android:name="android.hardware.type.automotive">`, `android:appCategory="audio"`, and **no** `MAIN`/`LAUNCHER` activity — a separate build from the Android-Auto one). The example is an Android-Auto build, so on AAOS it appears in the app grid, not the media center. An AAOS automotive build of the example is not provided yet.

### Real device + real car

End-to-end validation on physical phones and real cars is done **downstream in the consuming app**, which integrates this plugin and is tested on real hardware. flureadium's bar is the automated coverage above plus the reproducible manual surfaces; it does not attempt to fake a real head unit in CI.
