# God-Tier Test Runner

`scripts/run_all_tests.sh` runs every Flureadium test suite in one pass and prints a single consolidated summary. It ties the three test toolchains together so you don't invoke them one at a time:

1. **Unit / widget tests** — the Dart suites: `flutter test` in the plugin (`flureadium/`), the platform interface (`flureadium_platform_interface/`), and the example app (`example/`), plus `dart test` in the analyzer-plugin package (`flureadium_lints/`). Headless and fastest, so they run first.
2. **Native unit tests** — delegates to [`run_native_unit_tests.sh`](native-unit-tests.md): Android Kotlin/Robolectric on the JVM and iOS Swift/XCTest on a simulator.
3. **Integration tests** — delegates to [`run_integration_tests.sh`](integration-tests.md): the example app's full flows on Android, iOS, and Web.

Suites run fastest-first (unit → native → integration). By default every suite runs even if an earlier one fails, so one command shows the whole picture; the exit code is non-zero if any suite that ran failed.

The unit step is four separate rows in the summary — one per package — so a failure points at the exact package rather than a single lumped "unit" result.

## Usage

```bash
cd flureadium/flureadium
./scripts/run_all_tests.sh                 # everything
./scripts/run_all_tests.sh --unit-only     # just the headless Dart suites
./scripts/run_all_tests.sh --skip-ios      # drop iOS from native + integration
./scripts/run_all_tests.sh --skip-web      # drop the Web integration leg
./scripts/run_all_tests.sh --fail-fast --verbose
```

### Options

Suite selection:

| Option | Effect |
|--------|--------|
| `--skip-unit` | Skip the Dart unit/widget suites |
| `--skip-native` | Skip the native (Android + iOS) unit tests |
| `--skip-integration` | Skip the integration tests |
| `--unit-only` | Run only the Dart unit/widget suites |
| `--native-only` | Run only the native unit tests |
| `--integration-only` | Run only the integration tests |

Platform selection (forwarded to the delegated runners):

| Option | Effect |
|--------|--------|
| `--skip-android` | Skip every Android suite (native + integration) |
| `--skip-ios` | Skip every iOS suite (native + integration) |
| `--skip-web` | Skip the Web integration suite (integration only; the native runner has no web leg) |
| `--android-device <id>` | Android device/emulator id (integration) |
| `--ios-device <id>` | iOS simulator UDID (native + integration) |
| `--ios-class <Class>` | Run a single XCTest class (native iOS) |

Behaviour:

| Option | Effect |
|--------|--------|
| `--fail-fast` | Stop after the first failing suite |
| `--no-rerun` | Reuse the Android Gradle build cache (default: clean rebuild + fresh re-run) |
| `--verbose` | Stream full tool output for every suite |
| `--help`, `-h` | Print usage and exit |

## What needs a device

The four Dart unit suites are headless, so `--unit-only` runs with no device. Native Android (Robolectric) runs on the JVM with no emulator. Everything else needs hardware:

- Native iOS and the iOS integration leg need macOS with a booted simulator (auto-booted if none is running).
- The Android integration leg needs an emulator or connected device.
- The Web integration leg needs Chrome plus ChromeDriver (the integration runner starts ChromeDriver for you).

Drop what you can't run with `--skip-android` / `--skip-ios` / `--skip-web`, or use `--unit-only` for a device-free pass.

By default the Android native tests do a clean rebuild for a guaranteed real result; pass `--no-rerun` to reuse the Gradle build cache and finish faster.

## Intentionally skipped tests

A full run reports a handful of skips. These five are the only ones that belong there: each names an OS version or a platform its assertion cannot hold on. Any other skip is a defect, not a gate.

| Site | Gate | Why it stays |
|---|---|---|
| `example/ios/RunnerTests/CarTemplateRendererTests.swift` — `testTypedSearchRowAppearsOnlyWithIOS27AndKeyboard` | `guard #available(iOS 27.0, *) else { throw XCTSkip(…) }` | Typed CarPlay search is an iOS 27+ API. The project simulator runs 18.3.1, so the case reports skipped there and runs on any iOS 27+ device |
| `example/integration_test/audiobook_test.dart` — cancelled-read case | `skip: !Platform.isIOS` | The churn it pins is iOS AVFoundation behaviour; on Android there is no cancellation to be benign about |
| `example/integration_test/audiobook_test.dart` — mid-stream failure case | `skip: Platform.isIOS` | Android-specific failure mode |
| `example/integration_test/error_handling_test.dart` — no-publication case | `skip: Platform.isIOS` | Android-specific failure mode, written up in [integration-tests.md](integration-tests.md) |
| `example/integration_test/epub_tts_web_test.dart` | WIP web publication loading / navigator init | Publication loading on web waits on the Readium JS navigator — see [web.md](../platform-specific/web.md). Not a TTS gap: TTS is supported on web; the navigator is the unfinished part |

"Flaky" and "needs integration testing" are not reasons. Both of those were removed. The platform-interface stream test was fed a `Locator` object where the getter decodes a JSON string, so it timed out on every run; the wakelock tests never needed a device at all, because `wakelock_plus` exposes its platform instance for tests. A skip that names neither an OS version nor a platform is a test nobody finished — fix it or delete it.

Skipping is also not an escape from [Assertions must be able to fail](#assertions-must-be-able-to-fail): the wakelock group hid three of the banned forms behind a `skip:` for as long as it existed.

## Lockfile safety

The runner never lets `flutter test` silently rewrite a `pubspec.lock`. Left to itself, `flutter test` runs an implicit `pub get` that downgrades a committed lock whenever the resolving SDK differs — for example, an unmaterialized FVM pin falling back to the global SDK. For each Dart package the runner instead:

- resolves strictly to a **version-controlled** lock with `flutter pub get --enforce-lockfile`, failing the row loudly if the lock would change rather than rewriting it; then
- runs the tests with `flutter test --no-pub`, so nothing can mutate the lock.

A package whose lock is gitignored (the plugin itself) needs its dependencies resolved beforehand. If they aren't, that row fails and asks you to resolve them first and commit any lock changes intentionally — the runner won't re-resolve for you, because resolving a plugin can also update the example app's committed lock.

`flureadium_lints/` follows the same rule with the Dart toolchain: its `pubspec.lock` is version-controlled, so the runner does `dart pub get --enforce-lockfile` and then `dart test`. The test command must never be `flutter test` — the analyzer rule harness pulls `test_reflective_loader`, which imports `dart:mirrors`, and the Flutter test runtime rejects that import. Worse than failing, it then retries the load indefinitely instead of exiting, so a run wired to the wrong tool hangs the whole suite rather than reporting a red row.

## Logs

Each run writes to `test_logs/all_tests/run_<timestamp>/` (gitignored):

| File | Contents |
|---|---|
| `summary.log` | The consolidated pass/fail table printed to the terminal |
| `unit_plugin.log` | `flutter test` output for the plugin package |
| `unit_platform_interface.log` | `flutter test` output for the platform interface package |
| `unit_example.log` | `flutter test` output for the example app |
| `unit_lints.log` | `dart test` output for the analyzer-plugin package (`flureadium_lints/`) |
| `native.log` | Output from the delegated native runner |
| `integration.log` | Output from the delegated integration runner |

The delegated runners also write their own detailed logs under `test_logs/` — see [native-unit-tests.md](native-unit-tests.md) and [integration-tests.md](integration-tests.md). The terminal shows a trimmed view by default; the full output always lands in these files. Use `--verbose` to stream everything live.

## When to use it

Reach for `run_all_tests.sh` when you want the whole picture in one command — before a commit, or to confirm a change in one package didn't break another. For focused iteration on a single platform or a single XCTest class, call the delegated runner directly ([native-unit-tests.md](native-unit-tests.md), [integration-tests.md](integration-tests.md), [ios-unit-tests.md](ios-unit-tests.md)); when a suite fails, the summary names the log to open.

## Assertions must be able to fail

Every assertion has to be able to go red. A sweep across the Dart suites removed 56 that could not: each restated something the compiler, null safety, or the test itself had already settled. These forms are banned:

| Banned form | Always passes because |
|---|---|
| `expect(x, isA<T>())` where `x`'s static type is already `T` | the compiler proved it. `expect(voices, isA<List<ReaderTTSVoice>>())` on a method declared `Future<List<ReaderTTSVoice>>` is a no-op. **Machine-enforced** — `vacuous_type_assertion` |
| `expect(x, isNotNull)` on a non-nullable declared type | null safety already rules the failure out. **Machine-enforced** — `vacuous_not_null_assertion` |
| `expect(c, equals(c))` on the same canonicalized `const` | Equatable's `==` short-circuits on `identical`, and both operands are the same object |
| a finder asserted before an action, then the identical finder asserted after it | the widget was mounted before the action and nothing in the action unmounts it, so only a crash fails it |
| key presence or non-emptiness where the test name promises a value | `expect(json['metadata'], isNotNull)` in a test called "serializes publication to JSON" passes on `{}` |
| a latch asserted to be transiently cleared, when the feature under test refills it | `LiveTestWidgetsFlutterBinding` gives the refill the same frame the clear happened in, so the intermediate state is never observable — and the latch value cannot distinguish "refilled" from "never cleared". `expect(locatorHref(tester), isEmpty)` one pump after a resubscribe passed on a stale href |

Assert the value instead: the one the fixture or the mock actually produced. In an integration test, read the before-value from a latch, run the action, then assert that the after-value changed the way the test name claims.

### Two of the six are machine-checked

The first two rows are analyzer diagnostics now, not just a rule in this document.
`flureadium_lints`, a first-party analyzer plugin at the repo root, reports
`vacuous_type_assertion` and `vacuous_not_null_assertion` while you type and again in
CI. Both decisions come from the analyzer's type system: `isA<T>()` is flagged only
when the target's static type is already a subtype of `T`, and `isNotNull` only when
the static type is non-nullable. See [lint-rules.md](lint-rules.md) for the rules,
where they are enabled, and how to run their tests.

**The enforcing command is `dart analyze --fatal-infos`, not `flutter analyze`.**
`flutter analyze` drives the LSP server and returns the moment analysis reports itself
finished, while the plugin publishes from a separate isolate a beat later: it prints
`No issues found!` and exits 0 with a violation in front of it. Both commands are wired
up — `validators.conf`'s `static-plugin` row and the `Plugin lints` steps in
`quality.yml` run `dart analyze --fatal-infos` in all three packages, which is what
keeps these two forms out of `main`.

When a flagged assertion is genuinely the right one — a shape check on a `dynamic`
value the analyzer has narrowed for a different reason — suppress that single line:

    // ignore: flureadium_lints/vacuous_type_assertion

The prefix is the plugin name; `// ignore: vacuous_type_assertion` without it does
nothing. Reach for it rarely: the cases the rule is *supposed* to allow — `isA<T>()` on
`dynamic` or on a decoded JSON field, `throwsA(isA<…>())`, `isNotNull` on a nullable
type, a `.having(...)` chain — are not flagged at all, so a diagnostic on one of them
is a bug worth filing.

If your editor shows nothing after this landed, restart the analysis server (VS Code:
*Dart: Restart Analysis Server*). A `plugins:` section is read once per session.

The remaining four rows stay on us. `equals(c)` on the same `const`, a finder asserted
on both sides of an action, key-presence where the test name promises a value, and a
latch asserted to clear when the feature refills it are all semantic — they depend on
what the test's name claims and on dataflow across statements, which no type-level rule
can see. Those are held by review against this document and by the red state required
in "Proving a new assertion can fail" below.

### Latches, not finders

The example app publishes every fact worth asserting as a keyed debug `Text`, and `example/integration_test/helpers/` reads them back: `locatorHref`, `savedLocatorHref` and `locatorEvents` in `locator_latch.dart`, `readerStatus` in `reader_status.dart`, `currentTrackHref` in `audiobook_track.dart`. `pumpUntil` in `pump_until.dart` polls one of those until it moves. Copy that pattern: capture the latch, act, `pumpUntil` the value changes, assert `pumpUntil`'s own result with a `reason`, then assert the value.

Where the values repeat, a value latch cannot carry the assertion: the app writes the same href it wrote before, so a test cannot tell a fresh delivery from the old one. Publish a monotonic counter beside the value latch and assert it rose. `locator-events` is the worked example — the app increments it in the same `setState` that writes `_locator`, `_resetPublicationLatches` zeroes it per publication, and `locatorEvents` in `locator_latch.dart` reads it with `int.parse` so a renamed latch fails the suite instead of reading 0. Read a quiescent baseline before the action, or an event still in flight from the setup satisfies the rise.

A transient clear *is* observable in `example/test/widget_test.dart`: the mocked `text-locator` channel answers nothing on subscribe, so nothing refills the latch and the cleared state holds. Assertions about a clear belong there, not in a device suite.

Three examples already in the suites:

- `text_locator_test.dart`, `'a page turn is pushed to Dart'` — taps `→`, waits for `locatorHref` to fill, then asserts the href ends in `.xhtml`.
- `text_locator_test.dart`, `'a fresh subscriber learns the current position'` — pumps to quiescence, reads `locatorEvents`, taps `Resubscribe Locator`, waits for the count to rise.
- `epub_test.dart`, `'the load cover tracks reader status'` — waits for the open to reset `readerStatus`, then samples the loading-cover invariant on every pump until the status reads `ready`.

### Shape checks that are fine

The rule bans checks that cannot fail, not matchers. These stay:

- `isA<T>()` on a `dynamic` channel argument or a decoded JSON field, where the runtime type is the contract.
- `throwsA(isA<SomeException>())`.
- `isNotNull` immediately followed by a `!` dereference and assertions on the value.
- `findsOneWidget` on a finder that only exists after the action.
- `findsOneWidget` that turns a discarded `pumpUntil` timeout into a failure.

### Proving a new assertion can fail

Break the value it reads — the mock's return, the fixture literal, the app's write to the latch — run the test, watch it fail, restore the value, watch it pass. That red state is the check; a tautology cannot produce one. The device suites give nobody an on-demand loop for this, so write down which broken implementation the assertion would have caught instead.

### Known gaps

Three limits the rule cannot cover yet. Each one is filed:

- `flureadium-8om` — nothing reports the active EPUB theme back to Dart, so `'applying night preferences keeps status and position'` asserts status and position rather than the theme.
- `flureadium-0xb` — shape-only serialization assertions outside the sweep's census.
- `flureadium-69n` — the audio-error latch reader is copied across four integration files.