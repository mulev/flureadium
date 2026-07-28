# Android Platform

Android-specific setup and implementation details.

## Requirements

- Android SDK 24+ (Android 7.0 Nougat)
- Kotlin 1.8+
- Gradle 8.0+

## Setup

### 1. Add JitPack Repository

The Readium Pdfium adapter requires dependencies from JitPack. Add JitPack to your `android/build.gradle`:

```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' }  // Required for Readium PDF support
    }
}
```

### 2. Minimum SDK Version

In `android/app/build.gradle`:

```groovy
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

### 3. FlutterFragmentActivity

Change your `MainActivity` to extend `FlutterFragmentActivity`:

```kotlin
// android/app/src/main/kotlin/.../MainActivity.kt
package com.example.myapp

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {
}
```

**Why?** Flureadium uses platform views that require Fragment support.

### 4. Permissions

For TTS and audiobook features, add to `AndroidManifest.xml`:

```xml
<manifest>
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <!-- Required for TTS and audiobook background playback on Android 14+ -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

    <!-- For network-based publications -->
    <uses-permission android:name="android.permission.INTERNET" />
</manifest>
```

### 5. ProGuard Rules (Optional)

If using ProGuard/R8, add to `android/app/proguard-rules.pro`:

```proguard
# Readium
-keep class org.readium.** { *; }
-keep class org.joda.time.** { *; }

# Flureadium
-keep class dev.mulev.flureadium.** { *; }
```

### 6. Android Auto (Optional)

The plugin's manifest already declares Android Auto media support and its media service, and Android manifest merging brings both into the host app with **no host manifest changes**. What the browse tree *shows*, though, comes from a `CarContentProvider` the host registers in Dart (see [car content](../api-reference/car-content.md)) and reaches over an app-scoped car engine — so the host's whole library appears, not just the open book. The example app wires this for the demo in `CarStubApplication`, which boots a headless engine running the `carMain` entrypoint and serves stub nodes.

For reference, this is what the plugin declares and merges into your app. The `<application>` meta-data points at the automotive descriptor:

```xml
<!-- Declares Android Auto media support; points at the automotive descriptor. -->
<meta-data
    android:name="com.google.android.gms.car.application"
    android:resource="@xml/automotive_app_desc"/>
```

The descriptor it ships at `res/xml/automotive_app_desc.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<automotiveApp>
    <uses name="media"/>
</automotiveApp>
```

The plugin also declares `PluginMediaService` with an intent filter that advertises both the media3 `MediaLibraryService` action and the legacy `android.media.browse.MediaBrowserService` action that Android Auto scans for when it enumerates media apps, along with `foregroundServiceType="mediaPlayback"` and the foreground-service permissions from step 4 (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`); all of these merge in too. A host only needs to act if it defines its own `automotive_app_desc.xml` or the same meta-data, in which case the standard manifest-merger conflict rules apply.

**Testing with the Desktop Head Unit (DHU):**

1. Install the Desktop Head Unit from the SDK Manager (SDK Tools → Android Auto Desktop Head Unit emulator).
2. On the device or emulator, enable Android Auto developer mode (tap the Android Auto app version 10 times) and turn on **Unknown sources**.
3. Start the head-unit server on the device: `adb forward tcp:5277 tcp:5277`, then run the DHU binary from the SDK (`extras/google/auto/desktop-head-unit`).
4. Pick your app from the DHU's media launcher. The browse tree lists the registered `CarContentProvider`'s nodes — the example serves stub tabs and books via `CarStubApplication`, so it browses without opening anything in the phone app first — and search works from the head unit. Selecting a playable row forwards it to the provider; selecting a chapter of the currently open audiobook seeks the same navigator the in-app controls use, and transport (play/pause/skip) stays in sync.

> Android Auto validates the media app before showing it. If the app does not appear, check the merged manifest (in the build output) for the `com.google.android.gms.car.application` meta-data, confirm the media service is exported, and confirm its intent-filter advertises the `android.media.browse.MediaBrowserService` action Android Auto scans for.

## Implementation Details

### Android Auto Browse Tree

`PluginMediaService` runs as a media3 `MediaLibraryService` (not just `MediaSessionService`) and advertises the legacy `android.media.browse.MediaBrowserService` action in its intent filter. Android Auto connects as a platform `MediaBrowser` client, so it needs both: the `MediaLibraryService` to browse content and the legacy browse action to discover the app in the first place.

Browse and search content come from the host's registered `CarContentProvider` (see [car content](../api-reference/car-content.md)), reached over the car engine through a `MethodChannel`, so the tree is the host's whole library — not just the open publication:

- `onGetLibraryRoot`'s children are the provider's root tabs (for example Continue / Library / Search). Selecting a tab or container calls `children(nodeId)` for the next level.
- `NodeBrowseTree` turns each `CarBrowseNode` into a `MediaItem`: containers are browsable, audiobook/read-aloud rows are playable, `artworkPath` becomes the artwork URI, and `progress` becomes the media3 completion-percentage extra the head unit shows as a progress bar.
- An empty tree shows a single non-selectable status row carrying the host's `CarContentStrings` (`emptyRootTitle`/`emptyRootSubtitle`), so the head unit shows the host's copy instead of a blank screen.
- Search is first-class on Android Auto: `onSearch`/`onGetSearchResult` run `search(query)` on the provider and return matching nodes, with no OS-version caveat.
- A `siri`-kind node (the iOS Siri assistant marker) is dropped from the Android tree. Android Auto has no browse-row voice affordance (voice input there is Google Assistant), so rendering it would leave a dead row.
- Selecting a playable row forwards it to the provider (`play(nodeId)`). Picking a chapter of the currently open audiobook still seeks the loaded timeline via `AudiobookBrowseTree`, driving the same navigator the in-app controls use.
- On the Now Playing screen the callback's custom layout adds rewind, forward, and **bookmark** buttons; the bookmark button routes to the provider's `addBookmark()`. Android Auto surfaces no playback-speed control, so `cycleSpeed` is an iOS-only Now Playing button.

On a cold connect the car engine's Dart handler may still be starting, so `MethodChannelCarContentSource` retries a browse call a bounded number of times until it gets an array back, rather than mistaking the startup race for an empty library.

The mapping and the source are kept free of Android Auto and service state so they are JVM-unit-testable — `NodeBrowseTree` and the car value types with plain values, and the callback with a stub `CarContentSource` (see `NodeBrowseTreeTest.kt`, `PluginLibrarySessionCallbackTest.kt`, `MethodChannelCarContentSourceTest.kt`).

**Files:**
- `car/CarBrowseNode.kt`, `car/CarTab.kt`, `car/CarContentStrings.kt` — value types decoded from the car channel
- `car/CarContentSource.kt` + `car/MethodChannelCarContentSource.kt` — the browse/search/play seam and its method-channel adapter
- `car/NodeBrowseTree.kt` — maps car nodes/tabs to media3 `MediaItem`s
- `car/FlureadiumCarEngine.kt` — app-scoped holder the host publishes its car source into
- `AudiobookBrowseTree.kt` — maps the open audiobook's chapters to timeline indices for the chapter-pick seek
- `PluginLibrarySessionCallback.kt` — `MediaLibrarySession.Callback` serving browse, search, and the seek
- `PluginMediaService.kt` — hosts the `MediaLibrarySession`
- `res/xml/automotive_app_desc.xml` — Android Auto media descriptor

### Plugin Structure

```
android/src/main/kotlin/dev/mulev/flureadium/
├── FlureadiumPlugin.kt          # Plugin registration
├── MethodCallHandler.kt         # Method channel handler
├── ReadiumManager.kt            # Readium lifecycle
├── ReadiumReaderViewFactory.kt  # Platform view factory
├── ReadiumReaderView.kt         # Native reader view (EPUB)
├── ReadiumReaderWidget.kt       # Widget wrapper
├── PageThumbnailExtractor.kt    # Downscaled JPEG thumbnails for image resources
├── FlutterPdfPreferences.kt     # PDF preferences mapping
├── fragments/
│   └── PdfReaderFragment.kt     # PDF reader fragment
├── models/
│   └── PdfReaderViewModel.kt    # PDF reader state
└── navigators/
    ├── ImageNavigator.kt        # CBZ / DIVINA navigation controller
    └── PdfNavigator.kt          # PDF navigation controller
```

### Event Channels

All four Flutter EventChannels are registered in `ReadiumReader.attach()`:

| Channel | Kotlin class | Events |
|---|---|---|
| `dev.mulev.flureadium/reader-status` | `ReaderStatusEventChannel` | `"loading"`, `"ready"`, `"closed"` |
| `dev.mulev.flureadium/error` | `ErrorEventChannel` | `{ message, code, data }` maps |
| `dev.mulev.flureadium/text-locator` | `TextLocatorEventChannel` | Locator JSON strings |
| `dev.mulev.flureadium/timebased-state` | `TimedBasedStateEventChannel` | Playback state maps |

Reader status lifecycle:
- `"loading"` — emitted from `ReadiumReaderWidget.init` when the native view is created
- `"ready"` — emitted from `onVisualReaderIsReady()` when Readium signals the reader is ready
- `"closed"` — emitted from `ReadiumReaderWidget.dispose()` before tearing down the navigator

### Platform View

Uses `PlatformViewLink` with `AndroidViewSurface` for high-performance rendering:

```kotlin
class ReadiumReaderViewFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ReadiumReaderView(context, viewId, messenger, args as? Map<*, *>)
    }
}
```

### Readium Integration

Uses Readium Kotlin Toolkit:
- `Streamer` for EPUB parsing
- `Navigator` for EPUB, PDF, and image-based content display
- `TTS` and `MediaPlayer` for audio
- `PdfiumNavigator` for PDF rendering (via Pdfium adapter)

### Audiobook End of Book

When an audiobook reaches the end of its last resource, `AudiobookNavigator`
forwards `TimebasedState.ended` to the listener **before** it tears down the
media session. The ordering matters: regular playback states reach Flutter
through a stacked `throttleLatest` chain, but the `Ended` tick also triggers an
un-throttled `closeSession()`/`navigator.close()`. If `ended` went through the
throttled path, a post-end state could be pushed in the same window and the
latest-wins throttle would coalesce `ended` away before it reached Flutter.

`onAudioNavigatorEnded()` handles this in a fixed order: forward `ended` to the
listener, cancel and clear the forwarding jobs, then close the session. Cancelling
the jobs first stops any late tick from racing the listener after `ended` is
delivered.

### Audiobook Streaming Errors

When ExoPlayer reports a playback failure — a `Source error` from an unreachable
host, a 404, or a stream that drops mid-play — it reaches
`AudiobookNavigator` as `AudioNavigator.State.Failure` and is relayed through
`onTimebasedPlaybackFailure`. `ReadiumReader.onTimebasedPlaybackFailure` forwards
it to Flutter's `onErrorEvent` via `sendError`, with `code: "TimebasedError"`
and `data` set to the Readium error category. Android surfaces both load-time and
mid-stream failures; on iOS load-time failures are also caught now (via the
container wrapper — see [ios.md](ios.md#audiobook-error-forwarding)), but its
mid-stream/post-load delivery stays best-effort. Covered by `ReadiumReaderTimebasedErrorTest`.

**Files:**
- `AudiobookNavigator.kt` — `onAudioNavigatorEnded()` and the `State.Ended` branch

### Audiobook Media Session Reuse

`PluginMediaService` holds one live `MediaLibrarySession` per navigator.
`play(locator)` (the path a table-of-contents chapter tap or a bookmark resume
drives) routes through `Binder.openSession`, which decides what to do from the
navigator already backing the live session (`sessionActionFor`):

- **Same navigator**: reuse the open session and seek; do not build a new one.
- **Different navigator**: release the old session (an audiobook ↔ TTS switch), then open a new one.
- **None open**: open a fresh session.

media3 requires every live `MediaSession` to have a unique id, and the default id
is the empty string. An earlier version rebuilt the session on every
`play(locator)`, so a chapter jump created a second session with the same empty
id while the first was still live; media3 threw `Session ID must be unique` and
the error handler tore down the only player, freezing playback at the new
chapter's `0:00`. Reusing the session removes the collision.
`PluginMediaServiceFacade` mirrors the check at the bind layer: when it is
already bound with a live session for the same navigator it skips rebinding, so a
repeat `play(locator)` does not leak a session collector. Covered by
`PluginMediaServiceReuseTest` and the `play(locator) to a later chapter while
playing keeps playback going` integration test.

**Files:**
- `PluginMediaService.kt` — `Binder.openSession` reuse/replace guard, `sessionActionFor`
- `PluginMediaServiceFacade.kt` — same-navigator short-circuit before rebinding


### Audiobook Navigator Build Thread

`AudiobookNavigator.initNavigator` builds the Readium audio navigator on
`mainScope` (the main thread). media3 requires an `ExoPlayer` to be created and
accessed from a single application thread; with no `Looper` passed to the
builder, that thread is the main thread. Readium's `ExoPlayerEngine` builds the
player and immediately drives it (`setMediaItems`/`seekTo`/`prepare`), so the
whole `createNavigator` call must run on the main thread. Building it on a
background dispatcher throws `IllegalStateException: Player is accessed on the
wrong thread`.

Readium's `AudioNavigatorFactory.createNavigator` probes each track's duration
up front and, for a track whose manifest `duration` is null, reads the remote
resource synchronously. That probe is skipped when the manifest already carries
per-track durations, so the null-duration ANR seen on streamed Gutenberg
audiobooks is addressed upstream by the consuming app's Gutenberg duration mapping, not
by moving the build off the main thread.

**Files:**
- `AudiobookNavigator.kt` — `initNavigator()` builds the navigator inside `mainScope.async { }`

### Publication Open Concurrency

`ReadiumReader.openPublication(AbsoluteUrl)` guards its whole body (the
same-publication fast path, `loadPublication`, the navigator releases, and the
`_currentPublication`/`currentPublicationUrl` reassignment) with a single
`openMutex`. The method mutates singleton state, so a URL-keyed dedup alone is
not enough: different-URL opens could still interleave the state transition, so
a global mutex serializes every open. Two concurrent opens can never double-load
a publication or double-release navigators, and a second concurrent open of the
same publication waits for the first and then reuses its result through the fast
path. `loadPublicationFromUrl` (used by categorization) calls `loadPublication`
directly, mutates no navigator state, and stays outside the mutex.

**Files:**
- `ReadiumReader.kt` — `openPublication(AbsoluteUrl)` body wrapped in `openMutex.withLock { … }`

### PDF Support

PDF support is implemented using Readium's Pdfium adapter, which provides native PDF rendering via Android's Pdfium library.

**How It Works:**

The `PdfNavigator` class wraps Readium's PDF navigator and provides:
- Page-by-page navigation with edge tap detection
- Horizontal and vertical scroll modes
- Single page and double-page spread layouts
- Zoom and pan gestures

**Configuration:**

PDF preferences can be set via `setPDFPreferences()`:

```dart
await flureadium.setPDFPreferences(PDFPreferences(
  fit: PDFFit.width,
  scrollMode: PDFScrollMode.horizontal,
  pageLayout: PDFPageLayout.single,
));
```

**Files:**
- `PdfNavigator.kt` - Main PDF navigation controller
- `PdfReaderFragment.kt` - Android Fragment hosting the PDF view
- `FlutterPdfPreferences.kt` - Maps Flutter preferences to Readium

### Page Thumbnails

`extractPageThumbnail(href, maxHeight, quality)` resolves `href` against the currently open publication and returns a downscaled JPEG for image resources. It is intended for CBZ/DIVINA page previews, TOC thumbnails, and similar UI.

The Android implementation:
- Normalizes the incoming href with Readium's legacy-href URL conversion, matching the iOS `AnyURL(legacyHREF:)` path.
- Reads the resource from the active `Publication`, so mounted publications, streaming resources, and protected resources use the same Readium access path as the reader.
- Uses `BitmapFactory` with a bounds pass plus `inSampleSize`, then scales to the requested maximum pixel size and compresses to JPEG.
- Returns `null` when no publication is open, the href is missing, `maxHeight <= 0`, or the image cannot be decoded.

**Files:**
- `PageThumbnailExtractor.kt` - Decode/downscale/compress helper
- `PublicationChannel.kt` - `extractPageThumbnail` method-channel handler

## Edge Tap and Swipe Navigation

Android supports the same configurable gesture overlay as iOS via `setNavigationConfig()`.

### Overview

A transparent `EdgeTapInterceptView` overlay is placed on top of the Readium navigator
(both EPUB and PDF). It intercepts touches in the left and right edge zones and fires
navigation callbacks; center touches always pass through to the reader content.

### setNavigationConfig

```dart
await flureadium.setNavigationConfig(NavigationConfig(
  enableEdgeTapNavigation: true,   // tap left/right edges to turn pages
  enableSwipeNavigation: true,     // horizontal fling to turn pages
  edgeTapAreaPoints: 60,           // edge zone width in dp (44–120, clamped)
));
```

| Field | Type | Default | Description |
|---|---|---|---|
| `enableEdgeTapNavigation` | `bool?` | enabled | Tap in the edge zone → navigate |
| `enableSwipeNavigation` | `bool?` | enabled | Horizontal fling → navigate |
| `edgeTapAreaPoints` | `double?` | 44 dp | Edge zone width, clamped to 44–120 dp |

`null` fields are treated as **enabled** (matching iOS semantics).

### Scroll Mode (EPUB only)

When the EPUB reader switches to vertical scroll mode (via `setPreferences` with
`verticalScroll: true`), the overlay automatically disables all gesture interception
so Readium's WebView can handle native scrolling. Gestures are re-enabled when
scroll mode is turned off.

PDF is always paginated; scroll mode does not apply.

### Implementation

| File | Role |
|---|---|
| `FlutterNavigationConfig.kt` | Data class mirroring the Flutter config map |
| `EdgeTapInterceptView.kt` | Transparent FrameLayout overlay; intercepts edge touches |
| `EpubReaderFragment.kt` | Creates and tears down the overlay per lifecycle; propagates scroll mode |
| `PdfReaderFragment.kt` | Creates and tears down the overlay per lifecycle |
| `EpubNavigator.kt` / `PdfNavigator.kt` | Delegates `setNavigationConfig` / `setScrollMode` to the fragment |
| `ReadiumReader.kt` | Exposes `epubSetNavigationConfig`, `epubSetScrollMode`, `pdfSetNavigationConfig` |
| `ReadiumReaderWidget.kt` | Handles `setNavigationConfig` method call; detects scroll mode from `setPreferences` |

#### Touch dispatch design

`EdgeTapInterceptView` overrides `dispatchTouchEvent` rather than `onInterceptTouchEvent` +
`onTouchEvent`. The reason matters for future maintenance:

- `onInterceptTouchEvent` returning `true` causes the ViewGroup to call `onTouchEvent`.
- `onTouchEvent` returns `gestureDetector.onTouchEvent()`, which returns `onDown() = false`
  (the `SimpleOnGestureListener` default).
- That `false` propagates out of `dispatchTouchEvent`, so the **parent `FrameLayout` never
  records this view as the touch target** — `ACTION_UP` never arrives, and
  `onSingleTapConfirmed` never fires.

`dispatchTouchEvent` avoids this by returning `true` unconditionally for any `ACTION_DOWN`
that lands in an edge zone (claiming the gesture sequence), and `false` for centre touches
(passing them straight to the Readium WebView / PDF view).

### Text Selection Copy

**EPUB:** Copy is available through Android's native WebView text-selection
action mode. When the user long-presses EPUB content, the system selection UI
handles Copy without any plugin-specific override.

**PDF:** Text selection and copy are not supported on this path. The Pdfium
adapter renders PDF pages as bitmap content, so there is no text layer for the
system action mode to act on.

## Troubleshooting

### "MainActivity cannot be cast to FragmentActivity"

Ensure MainActivity extends `FlutterFragmentActivity`.

### Build fails with "Duplicate class"

Add to `android/app/build.gradle`:
```groovy
android {
    packagingOptions {
        exclude 'META-INF/DEPENDENCIES'
        exclude 'META-INF/LICENSE'
    }
}
```

### TTS not working

1. Check TTS engine is installed (Settings > Accessibility > TTS)
2. Download language data if prompted
3. Test with system TTS settings
4. If TTS stops when the app goes to the background, update to the latest Flureadium release. Recent Android fixes cover the media-service startup path by entering the foreground immediately with a startup media notification, and also cover an activity saved-state crash caused by serializing Readium decoration styles when the app was backgrounded.

### Edge taps not responding

If edge taps appear in Flutter's `Listener` logs but no navigation occurs:

1. Check logcat for `D/EdgeTapInterceptView: dispatchTouchEvent ACTION_DOWN x=... claimed=true`.
   If `claimed=false` for a tap at the screen edge, the tap coordinate in **dp** is outside
   the configured zone — verify `edgeTapAreaPoints` and screen density.
2. If there are no `EdgeTapInterceptView` logs at all, the overlay was not created. Confirm
   `attachNavigator()` ran and `view as? FrameLayout` succeeded (the fragment root must be a
   `FrameLayout`, which it is by default via `fragment_reader.xml`).
3. In EPUB scroll mode, all overlay gestures are intentionally disabled; check that
   `setScrollMode(false)` was called when leaving scroll mode.

### "setState() called after dispose()" in test logs

This error occurred when the native platform sent `onPageChanged` method calls after the Dart `ReadiumReaderWidget` had already been disposed. The `onPageChanged` callback called `setState()` without checking `mounted`, and the `onTextLocatorChanged` stream subscription was never cancelled.

Both issues are now fixed: `onPageChanged` checks `mounted` before calling `setState()`, and the debug stream subscription is stored and cancelled in `dispose()`. If you see this error in older versions, update the plugin.

### Integration test cascade failures

When integration tests share a process (the default for `flutter test`), a
failed test can leave native resources (ExoPlayer sessions, TTS engines,
navigator fragments) in a dirty state that causes every subsequent test to fail.

**Prevention:** Add `tearDown` blocks to every test group that uses audio or TTS:

```dart
group('Audiobook', () {
  tearDown(() async {
    final flureadium = Flureadium();
    await flureadium.stop();
    await flureadium.closePublication();
  });

  testWidgets('plays audio', (tester) async { ... });
});
```

`stop()` releases the TTS engine or ExoPlayer session. `closePublication()`
calls `release()` on all active navigators, which awaits cleanup inline instead
of firing and forgetting. Together they ensure each test starts with a clean
native state.

For EPUB-only tests (no TTS or audio), `closePublication()` alone is enough.

### WebView rendering issues

Enable hardware acceleration:
```xml
<application android:hardwareAccelerated="true">
```

## See Also

- [Installation Guide](../getting-started/installation.md)
- [Architecture Overview](../architecture/overview.md)
- [Troubleshooting](../troubleshooting.md)
