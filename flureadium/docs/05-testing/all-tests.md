# God-Tier Test Runner

`scripts/run_all_tests.sh` runs every Flureadium test suite in one pass and prints a single consolidated summary. It ties the three test toolchains together so you don't invoke them one at a time:

1. **Unit / widget tests** — `flutter test` in each Dart package: the plugin (`flureadium/`), the platform interface (`flureadium_platform_interface/`), and the example app (`example/`). Headless and fastest, so they run first.
2. **Native unit tests** — delegates to [`run_native_unit_tests.sh`](native-unit-tests.md): Android Kotlin/Robolectric on the JVM and iOS Swift/XCTest on a simulator.
3. **Integration tests** — delegates to [`run_integration_tests.sh`](integration-tests.md): the example app's full flows on Android, iOS, and Web.

Suites run fastest-first (unit → native → integration). By default every suite runs even if an earlier one fails, so one command shows the whole picture; the exit code is non-zero if any suite that ran failed.

The unit step is three separate rows in the summary — one per package — so a failure points at the exact package rather than a single lumped "unit" result.

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

The three Dart unit suites are headless, so `--unit-only` runs with no device. Native Android (Robolectric) runs on the JVM with no emulator. Everything else needs hardware:

- Native iOS and the iOS integration leg need macOS with a booted simulator (auto-booted if none is running).
- The Android integration leg needs an emulator or connected device.
- The Web integration leg needs Chrome plus ChromeDriver (the integration runner starts ChromeDriver for you).

Drop what you can't run with `--skip-android` / `--skip-ios` / `--skip-web`, or use `--unit-only` for a device-free pass.

By default the Android native tests do a clean rebuild for a guaranteed real result; pass `--no-rerun` to reuse the Gradle build cache and finish faster.

## Lockfile safety

The runner never lets `flutter test` silently rewrite a `pubspec.lock`. Left to itself, `flutter test` runs an implicit `pub get` that downgrades a committed lock whenever the resolving SDK differs — for example, an unmaterialized FVM pin falling back to the global SDK. For each Dart package the runner instead:

- resolves strictly to a **version-controlled** lock with `flutter pub get --enforce-lockfile`, failing the row loudly if the lock would change rather than rewriting it; then
- runs the tests with `flutter test --no-pub`, so nothing can mutate the lock.

A package whose lock is gitignored (the plugin itself) needs its dependencies resolved beforehand. If they aren't, that row fails and asks you to resolve them first and commit any lock changes intentionally — the runner won't re-resolve for you, because resolving a plugin can also update the example app's committed lock.

## Logs

Each run writes to `test_logs/all_tests/run_<timestamp>/` (gitignored):

| File | Contents |
|---|---|
| `summary.log` | The consolidated pass/fail table printed to the terminal |
| `unit_plugin.log` | `flutter test` output for the plugin package |
| `unit_platform_interface.log` | `flutter test` output for the platform interface package |
| `unit_example.log` | `flutter test` output for the example app |
| `native.log` | Output from the delegated native runner |
| `integration.log` | Output from the delegated integration runner |

The delegated runners also write their own detailed logs under `test_logs/` — see [native-unit-tests.md](native-unit-tests.md) and [integration-tests.md](integration-tests.md). The terminal shows a trimmed view by default; the full output always lands in these files. Use `--verbose` to stream everything live.

## When to use it

Reach for `run_all_tests.sh` when you want the whole picture in one command — before a commit, or to confirm a change in one package didn't break another. For focused iteration on a single platform or a single XCTest class, call the delegated runner directly ([native-unit-tests.md](native-unit-tests.md), [integration-tests.md](integration-tests.md), [ios-unit-tests.md](ios-unit-tests.md)); when a suite fails, the summary names the log to open.

## Assertions must be able to fail

Every assertion has to be able to go red. A sweep across the Dart suites removed 53 that could not: each restated something the compiler, null safety, or the test itself had already settled. These forms are banned:

| Banned form | Always passes because |
|---|---|
| `expect(x, isA<T>())` where `x`'s static type is already `T` | the compiler proved it. `expect(voices, isA<List<ReaderTTSVoice>>())` on a method declared `Future<List<ReaderTTSVoice>>` is a no-op |
| `expect(x, isNotNull)` on a non-nullable declared type | null safety already rules the failure out |
| `expect(c, equals(c))` on the same canonicalized `const` | Equatable's `==` short-circuits on `identical`, and both operands are the same object |
| a finder asserted before an action, then the identical finder asserted after it | the widget was mounted before the action and nothing in the action unmounts it, so only a crash fails it |
| key presence or non-emptiness where the test name promises a value | `expect(json['metadata'], isNotNull)` in a test called "serializes publication to JSON" passes on `{}` |

Assert the value instead: the one the fixture or the mock actually produced. In an integration test, read the before-value from a latch, run the action, then assert that the after-value changed the way the test name claims.

### Latches, not finders

The example app publishes every fact worth asserting as a keyed debug `Text`, and `example/integration_test/helpers/` reads them back: `locatorHref` and `savedLocatorHref` in `locator_latch.dart`, `readerStatus` in `reader_status.dart`, `currentTrackHref` in `audiobook_track.dart`. `pumpUntil` in `pump_until.dart` polls one of those until it moves. Copy that pattern: capture the latch, act, `pumpUntil` the value changes, assert `pumpUntil`'s own result with a `reason`, then assert the value.

Two examples already in the suites:

- `text_locator_test.dart`, `'a page turn is pushed to Dart'` — taps `→`, waits for `locatorHref` to fill, then asserts the href ends in `.xhtml`.
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