# iOS Unit Tests

Native Swift/XCTest unit tests for the flureadium iOS plugin. These test Swift code that runs on the iOS platform (navigators, plugin handlers, TTS logic, etc.) and are separate from `flutter test`, which only covers Dart code.

## How It Works

Flutter iOS plugins are Swift Packages, but their tests cannot run via `swift test` because:

1. The plugin imports the `Flutter` framework, which is not an SPM dependency — it is injected by the Flutter build system via the example app's Xcode workspace.
2. Readium Swift Toolkit declares iOS-only platform support, so SPM cannot resolve dependencies for a macOS host target.

Instead, tests live in the **example app's RunnerTests target** and run via `xcodebuild test`. The example app's Xcode workspace already links the plugin package and all its dependencies, so tests have full access to plugin internals via `@testable import flureadium`.

## Test File Location

```
flureadium/example/ios/RunnerTests/
├── RunnerTests.swift                  # Plugin handler dispatch
├── FlutterTTSNavigatorTests.swift     # TTS navigator lifecycle, play/suppression, dispose, initNavigator errors
├── UtilityTests.swift                 # clamp, firstMap, asyncCompactMap
├── ModelTests.swift                   # ControlPanelInfoType, NavigationConfig, TTS/Audio/PDF preferences
├── StateSerializationTests.swift      # ReadiumTimebasedState toJson, toJsonString, Equatable
├── ReadiumExtensionsTests.swift       # Locator extensions, state mappings, EPUB/PDF preferences fromMap
├── FlutterMediaOverlayTests.swift     # FlutterMediaOverlayItem parsing/matching/locators
├── ReadiumErrorTests.swift            # ReadiumError/FlureadiumError to FlutterError conversions
├── EdgeTapInterceptViewTests.swift   # hitTest geometry, edge interception, subview bypass, property behavior
├── NowPlayingInfoUpdaterTests.swift  # Chapter formatting for all ControlPanelInfoType variants
├── ScrollModeNavigationTests.swift   # strippedHref, chapterLink before/after, isBackwardNavigation
└── EventStreamHandlerTests.swift     # EventStreamHandler listen/cancel/dispose lifecycle
```

The files above are the main suites. Other tests (car surface, plugin navigation, audio, image cache, thumbnails) live in the same `RunnerTests` target and run together via `xcodebuild test`.

The car surface adds `CarTemplateRendererTests`, `CarListItemFactoryTests`, `CarContentModelsTests`, `CarPlayPlaybackBridgeTests`, and `CarPlayContentBridgeTests` (the channel bridge's cold-start retry + node decode). All run in CI: the **`test-ios-native`** job in `.github/workflows/test.yml` runs the whole `RunnerTests` target via `xcodebuild test` on every push and PR, so a new `.swift` file registered here is exercised automatically.

All test files go in `flureadium/example/ios/RunnerTests/`. The plugin's SPM manifest (`ios/flureadium/Package.swift`) deliberately declares no test target: SPM can't run these tests (see [How It Works](#how-it-works)), so any test added there would never execute. Add tests to RunnerTests instead.

## Adding a New Test File

Two things are required when you add a new `.swift` file to RunnerTests:

### 1. Create the file

Place it in `flureadium/example/ios/RunnerTests/`. Use the standard XCTest structure:

```swift
import XCTest
import ReadiumShared      // Readium types: Publication, Locator, Manifest, etc.
import ReadiumNavigator   // Readium navigator types: PublicationSpeechSynthesizer, etc.
@testable import flureadium

final class YourTests: XCTestCase {

    func testSomething() async {
        // Arrange
        let publication = Publication(manifest: Manifest(metadata: Metadata(title: "Test")))
        // Act & Assert
        XCTAssertNotNil(publication)
    }
}
```

Available imports:
- `XCTest` — test framework
- `Flutter` — FlutterMethodCall, FlutterError, FlutterResult, etc.
- `ReadiumShared` — Publication, Locator, Manifest, Metadata, MediaType, Link, etc.
- `ReadiumNavigator` — PublicationSpeechSynthesizer, EPUBNavigatorViewController, etc.
- `@testable import flureadium` — all plugin internals (FlutterTTSNavigator, FlureadiumPlugin, etc.)

### 2. Register the file in the Xcode project

New `.swift` files are NOT automatically discovered by `xcodebuild`. You must add three entries to `flureadium/example/ios/Runner.xcodeproj/project.pbxproj`:

1. **PBXFileReference** — declares the file exists:
```
{UNIQUE_ID_1} /* YourTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = YourTests.swift; sourceTree = "<group>"; };
```

2. **PBXBuildFile** — declares the file should be compiled:
```
{UNIQUE_ID_2} /* YourTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = {UNIQUE_ID_1} /* YourTests.swift */; };
```

3. **Add to two sections**:
   - The **RunnerTests group** (search for `/* RunnerTests */` children list) — add the PBXFileReference ID
   - The **RunnerTests Sources build phase** (search for `331C807D294A63A400263BE5 /* Sources */`) — add the PBXBuildFile ID

Generate unique IDs as 24-character hex strings. They must not collide with existing IDs in the file.

Alternatively, open `Runner.xcworkspace` in Xcode once, drag the file into RunnerTests, and the project file is updated automatically.

## Running Tests

### Prerequisites — MUST BUILD BEFORE TESTING

**This step is mandatory before every test run where files or project configuration changed.** Without it, `xcodebuild test` fails silently (exit code 1, no useful error output) or with stale-artifact errors.

```bash
cd flureadium/example
flutter build ios --simulator --debug
```

**You MUST re-run this build step when:**
- New `.swift` test files are added
- `project.pbxproj` is modified (file registrations, build settings)
- Flutter dependencies change (pubspec.yaml, plugin registration)
- Pod dependencies are updated

The build regenerates all Flutter artifacts, runs `pod install`, and ensures `xcodebuild` has a consistent workspace. Skipping it after structural changes causes failures that produce no diagnostic output — just an empty error with exit code 1.

### Picking a Simulator

Use the simulator UUID rather than its name. Name-based destinations (`platform=iOS Simulator,name=iPhone 16 Pro`) fail when multiple iOS runtimes define a simulator with the same name.

```bash
# Grab the UUID of the BOOTED Flutter Sim simulator
SIM_ID=$(xcrun simctl list devices available | grep 'Flutter Sim.*Booted' | grep -oE '[A-F0-9-]{36}')
# Fallback if no booted Flutter Sim exists
[ -z "$SIM_ID" ] && SIM_ID=$(xcrun simctl list devices available | grep -m1 'iPhone 16 Pro' | grep -oE '[A-F0-9-]{36}')
```

**Critical:** Always grep for `Flutter Sim.*Booted` — never `grep -m1 'iPhone.*Flutter Sim'`. Multiple Flutter Sim devices exist across iOS runtimes, and `-m1` picks the first match which may be Shutdown. xcodebuild silently fails (exit code 1, zero output) when targeting a Shutdown simulator.

If no simulator is booted, boot one first:
```bash
xcrun simctl boot $(xcrun simctl list devices available | grep -m1 'Flutter Sim' | grep -oE '[A-F0-9-]{36}')
```

If you need a specific runtime version:

```bash
xcrun simctl list runtimes | grep iOS
xcrun simctl list devices available "iOS 18.3"
```

### Run All iOS Unit Tests

```bash
SIM_ID=$(xcrun simctl list devices available | grep 'Flutter Sim.*Booted' | grep -oE '[A-F0-9-]{36}')
[ -z "$SIM_ID" ] && SIM_ID=$(xcrun simctl list devices available | grep -m1 'iPhone 16 Pro' | grep -oE '[A-F0-9-]{36}')
cd flureadium/example/ios && \
  xcodebuild test \
    -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -destination "id=$SIM_ID" \
    -only-testing:RunnerTests \
    2>&1 | grep -E '(Test Case|TEST |Executed|error:|failed|SUCCEEDED|FAILED)' | tail -50
```

### Run a Specific Test Class

```bash
SIM_ID=$(xcrun simctl list devices available | grep 'Flutter Sim.*Booted' | grep -oE '[A-F0-9-]{36}')
[ -z "$SIM_ID" ] && SIM_ID=$(xcrun simctl list devices available | grep -m1 'iPhone 16 Pro' | grep -oE '[A-F0-9-]{36}')
cd flureadium/example/ios && \
  xcodebuild test \
    -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -destination "id=$SIM_ID" \
    -only-testing:RunnerTests/FlutterTTSNavigatorTests \
    2>&1 | grep -E '(Test Case|TEST |Executed|error:|failed|SUCCEEDED|FAILED)' | tail -50
```

### Run a Single Test Method

```bash
SIM_ID=$(xcrun simctl list devices available | grep 'Flutter Sim.*Booted' | grep -oE '[A-F0-9-]{36}')
[ -z "$SIM_ID" ] && SIM_ID=$(xcrun simctl list devices available | grep -m1 'iPhone 16 Pro' | grep -oE '[A-F0-9-]{36}')
cd flureadium/example/ios && \
  xcodebuild test \
    -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -destination "id=$SIM_ID" \
    -only-testing:RunnerTests/FlutterTTSNavigatorTests/testPlayConsumesInitialLocator \
    2>&1 | grep -E '(Test Case|TEST |Executed|error:|failed|SUCCEEDED|FAILED)' | tail -50
```

### Reading Output

The `grep` filter at the end shows pass/fail lines. Full xcodebuild output is extremely verbose. Key patterns:

- `Test case '...' passed` — test passed
- `Test case '...' failed` — test failed
- `** TEST SUCCEEDED **` — all requested tests passed
- `** TEST FAILED **` — at least one test failed

For full output (debugging build failures), drop the `grep` pipe:

```bash
SIM_ID=$(xcrun simctl list devices available | grep 'Flutter Sim.*Booted' | grep -oE '[A-F0-9-]{36}')
[ -z "$SIM_ID" ] && SIM_ID=$(xcrun simctl list devices available | grep -m1 'iPhone 16 Pro' | grep -oE '[A-F0-9-]{36}')
cd flureadium/example/ios && \
  xcodebuild test \
    -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -destination "id=$SIM_ID" \
    -only-testing:RunnerTests \
    2>&1 | tail -80
```

## Deployment Target

The RunnerTests target's `IPHONEOS_DEPLOYMENT_TARGET` must match the flureadium package's minimum (currently 13.4). If you see an error like:

```
compiling for iOS 13.0, but module 'flureadium' has a minimum deployment target of iOS 13.4
```

Add `IPHONEOS_DEPLOYMENT_TARGET = 13.4;` to all three RunnerTests build configurations (Debug, Release, Profile) in `project.pbxproj`.

## Writing Good Tests

### Test patterns established in this project

**Testing plugin internals directly** (preferred for logic tests):
```swift
// Create a minimal Publication — no ContentService, so TTS/streamer won't initialize,
// but the object is valid for testing navigator logic.
let publication = Publication(manifest: Manifest(metadata: Metadata(title: "Test")))

// Create a Locator for position-related tests
let locator = Locator(href: URL(string: "chapter1.xhtml")!, mediaType: .html)

// Instantiate the navigator directly
let navigator = FlutterTTSNavigator(publication: publication, initialLocator: locator)

// Call methods and assert
await navigator.play(fromLocator: nil)
XCTAssertNil(navigator.initialLocator)
```

**Testing plugin method handlers** (for testing the Dart-to-native boundary):
```swift
let plugin = FlureadiumPlugin()
let expectation = expectation(description: "result called")

let call = FlutterMethodCall(methodName: "ttsCanSpeak", arguments: nil)
plugin.handle(call) { response in
    XCTAssertEqual(response as? Bool, false)
    expectation.fulfill()
}

wait(for: [expectation], timeout: 2.0)
```

### Async tests

Use `async` test methods for any code that calls `async` functions:

```swift
func testSomethingAsync() async {
    await navigator.play(fromLocator: nil)
    XCTAssertNil(navigator.initialLocator)
}
```

Waiting for a callback that fires directly, like the method-handler example above, is fine with
`wait(for:timeout:)`. Waiting for a *scheduled* hop is not. Do not do this:

```swift
// Wrong: needs the main queue serviced inside a fixed cap.
let e = expectation(description: "throttle")
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { e.fulfill() }
await fulfillment(of: [e], timeout: 1.0)
```

That is a bet on main-queue latency, and it has lost: on 2026-08-03 the 200 ms block did not fire
within the 1 s cap and the test failed. It had run in about 0.21 s on the four runs before. Use
`try? await Task.sleep(nanoseconds:)` on a `@MainActor` test instead — it suspends the actor, so the
run loop keeps turning, and nothing depends on a queued block being reached in time.

### Negative assertions need a positive control

"Nothing reached the listener" also holds when the thing under test stopped emitting altogether, so
an assertion like `XCTAssertEqual(mock.calls.count, 0)` after a sleep can only fail by timeout —
never by catching the bug it was written for. Drive the pipeline to a state where output *is*
expected, wait for that, then assert the unwanted output never appeared:

```swift
// Suppressed input: must not arrive.
navigator.playingWordRangeSubject.send(makeLocator(href: "suppressed.xhtml"))
try? await Task.sleep(nanoseconds: 300_000_000)

// Control: with suppression cleared, output must arrive. Poll for it rather
// than sleeping a fixed amount, so a loaded machine costs time, not a failure.
_ = await navigator.seek(toLocator: makeLocator(href: "page3.xhtml"))
// ...send distinct locators until one is delivered, bounded...

XCTAssertFalse(mock.reachedLocatorCalls.contains { $0.locator.href.string == "suppressed.xhtml" })
```

`FlutterTTSNavigatorTests.testWordRangeSuppressedDuringFirstUtterance` is the worked example. To
check that a control actually bites, delete the production guard it depends on and confirm the test
fails on its assertion rather than on a clock.

### What NOT to test here

- Dart code — use `flutter test` for that
- Full end-to-end flows with a real reader — use integration tests (`flutter test integration_test/`)
- Android native code — use the Android unit tests (Kotlin/Robolectric)
