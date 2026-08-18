# Native Unit Test Runner

`scripts/run_native_unit_tests.sh` runs the platform-native unit tests — Android (Kotlin/Robolectric) and iOS (Swift/XCTest) — in one pass. These tests are separate from `flutter test`, which only covers Dart code.

The script exists so you don't have to remember two different toolchains and their setup. It finds the tools each platform needs, and when it can't find one it asks you for a path instead of failing — so a fresh checkout works on someone else's machine, not just the original author's.

> To run these native suites together with the Dart unit and integration suites in one command, use the [God-Tier Test Runner](all-tests.md).

## Usage

```bash
cd flureadium/flureadium
./scripts/run_native_unit_tests.sh                  # both platforms
./scripts/run_native_unit_tests.sh --skip-ios       # Android only
./scripts/run_native_unit_tests.sh --ios-class ModelTests --skip-android
./scripts/run_native_unit_tests.sh --verbose        # full tool output
```

### Options

| Option | Effect |
|--------|--------|
| `--skip-android` | Skip the Android tests |
| `--skip-ios` | Skip the iOS tests |
| `--rerun` | Force the Android tests to re-execute even when Gradle marks the task up-to-date |
| `--java-home <path>` | Use this JDK for Android instead of auto-detecting |
| `--ios-device <id>` | iOS simulator UDID to use (auto-detected otherwise) |
| `--ios-class <Class>` | Run a single XCTest class, e.g. `ModelTests` |
| `--verbose` | Stream full tool output instead of the trimmed view |
| `--help` | Print usage and exit |

It runs both platforms in sequence, keeps going if one fails, and prints a pass/fail summary at the end. The exit code is non-zero if any run failed or could not start.

Gradle skips `:flureadium:testDebugUnitTest` when its inputs haven't changed, reporting the task as `UP-TO-DATE` and running no tests — so re-running on an unchanged tree looks like a pass without actually executing anything. Pass `--rerun` to force a real run; it re-executes the test task while still skipping unnecessary recompilation.

## What it detects

**Java (Android).** Gradle 8.x needs JDK 17 or newer. The script looks in this order: `$JAVA_HOME`, the `--java-home` value, the macOS `java_home` helper, the JetBrains Runtime bundled with Android Studio, and `java` on `PATH`. If none of them is a JDK 17+, it asks you to type a path (or `skip`).

**Gradle (Android).** Tests run through the example app's Gradle wrapper at `example/android/gradlew`, so no separate Gradle install is needed. The task is `:flureadium:testDebugUnitTest`. Robolectric runs on the JVM, so no device or emulator is involved.

**Simulator (iOS, macOS only).** It uses a booted simulator if one is running, otherwise it lists the installed iPhone simulators and boots the one you pick. It builds the example app for the simulator first — `flutter build ios --simulator --debug` — because XCTest fails silently without a fresh build when test files or dependencies changed. iOS is skipped with a reason on non-macOS hosts. The script leaves your simulators as it found them: one it booted itself is shut down on exit, and one that was already running is left running. `xcodebuild test` tears down its own test destination and can shut down a simulator it did not boot, so if it closes an already-running simulator the script re-boots it on exit.

## Logs

Each run writes to `test_logs/native_run_<timestamp>/`:

- `summary.log` — the pass/fail trail printed to the terminal
- `android.log` — full Gradle output
- `ios_build.log` — the `flutter build ios` output
- `ios_test.log` — full `xcodebuild test` output

The terminal shows a trimmed view by default — build verdicts, test results, and anything that looks like a failure. The full output always lands in these files. On failure the last 40 lines of the relevant log are echoed so you can see the cause without opening the file. Use `--verbose` to stream everything live.

## When to use it

Reach for the script for the common case: run all native tests, or all of one platform. For the fine-grained iOS work — a single test method, deployment-target errors, simulator-runtime selection, registering a new `.swift` file in the Xcode project — see [ios-unit-tests.md](ios-unit-tests.md), which documents the raw `xcodebuild` commands the script wraps.

Android test sources live in `android/src/test/kotlin/`. The script runs the whole `testDebugUnitTest` task; there is no single-class flag on the Android side yet.

`ReadiumExtensionsDecorationTest.kt` is the JVM guard for the decoration wire format — the happy path plus every malformed field. It pairs with the iOS `EpubReaderCommandTests` and `ReadiumExtensionsTests` decoration cases and with the format written down in [decorations.md](../api-reference/decorations.md); change one and the other two have to move with it.

## Continuous integration

These native suites also run in CI on every push and pull request (`.github/workflows/test.yml`), so a regression is caught without running them by hand:

- **`test-android-native`** (ubuntu) — `:flureadium:testDebugUnitTest` (Robolectric on the JVM, no emulator).
- **`test-ios-native`** (macOS) — the `RunnerTests` target via `xcodebuild test` on a booted simulator.

The local script stays the fast path for focused iteration and for targeting a single platform or `--ios-class`.
