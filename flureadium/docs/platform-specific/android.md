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

Audiobook chapters and transport controls work on Android Auto with no host manifest changes. The plugin's manifest already declares Auto media support and its media service, and Android manifest merging brings both into the host app — the example app adds nothing Auto-specific and still exposes the browse tree.

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

The plugin also declares `PluginMediaService` with the `MediaLibraryService` intent filter and `foregroundServiceType="mediaPlayback"`, plus the foreground-service permissions from step 4 (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`) — all merge in too. A host only needs to act if it defines its own `automotive_app_desc.xml` or the same meta-data, in which case the standard manifest-merger conflict rules apply.

**Testing with the Desktop Head Unit (DHU):**

1. Install the Desktop Head Unit from the SDK Manager (SDK Tools → Android Auto Desktop Head Unit emulator).
2. On the device or emulator, enable Android Auto developer mode (tap the Android Auto app version 10 times) and turn on **Unknown sources**.
3. Start the head-unit server on the device: `adb forward tcp:5277 tcp:5277`, then run the DHU binary from the SDK (`extras/google/auto/desktop-head-unit`).
4. Open the audiobook in the app so a publication is loaded, then pick your app from the DHU's media launcher. The chapter list should browse and transport controls (play/pause/skip) should drive playback.

> Android Auto validates the media app before showing it. If the app does not appear, check the merged manifest (in the build output) for the `com.google.android.gms.car.application` meta-data and confirm the media service is exported.

## Implementation Details

### Android Auto Browse Tree

`PluginMediaService` runs as a media3 `MediaLibraryService` (not just `MediaSessionService`), which is what Android Auto requires to browse content. `AudiobookBrowseTree` builds the tree the head unit requests:

- The tree is **one level deep**: a browsable root whose children are the open publication's chapters (its `readingOrder` entries).
- Each chapter is a playable `MediaItem` whose id (`ch_<index>`) round-trips back to a Readium `Locator` the audiobook navigator can seek to. The index matches the audio player's timeline index, so selecting a chapter on the head unit drives a seek on the same navigator the in-app controls use.
- Chapter titles fall back to `Chapter N` when a reading-order entry has no title; the root falls back to `Audiobook` when the publication has no title.

The browse tree is kept free of Android Auto and service state so it is JVM-unit-testable with a stubbed `Publication` (see `AudiobookBrowseTreeTest.kt`).

**Files:**
- `AudiobookBrowseTree.kt` — builds the root + chapter `MediaItem`s, maps ids to locators
- `PluginLibrarySessionCallback.kt` — `MediaLibrarySession.Callback` serving the tree to Auto
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
