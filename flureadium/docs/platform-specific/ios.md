# iOS Platform

iOS-specific setup and implementation details.

## Requirements

- iOS 13.0+
- Xcode 14+
- CocoaPods

## Setup

### 1. Podfile Configuration

Add Readium pods to `ios/Podfile`:

```ruby
platform :ios, '13.0'

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  # PromiseKit dependency
  pod 'PromiseKit', '~> 8.1'

  # Readium toolkit pods (version 3.5.0)
  pod 'ReadiumShared', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumShared.podspec'
  pod 'ReadiumInternal', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumInternal.podspec'
  pod 'ReadiumStreamer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumStreamer.podspec'
  pod 'ReadiumNavigator', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumNavigator.podspec'
  pod 'ReadiumOPDS', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumOPDS.podspec'
  pod 'ReadiumAdapterGCDWebServer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumAdapterGCDWebServer.podspec'
  pod 'ReadiumZIPFoundation', podspec: 'https://raw.githubusercontent.com/readium/podspecs/refs/heads/main/ReadiumZIPFoundation/3.0.1/ReadiumZIPFoundation.podspec'

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
```

Then run:
```bash
cd ios
pod install
```

### 2. App Transport Security

Add to `ios/Runner/Info.plist` for local content server:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

**Why?** Readium uses a local web server to serve EPUB content.

### 3. Background Audio (Optional)

For audiobook background playback, add to `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### 4. CarPlay (Optional)

To expose audiobook chapters and transport controls on CarPlay, the host app adds a CarPlay scene and the CarPlay-audio entitlement. Flureadium ships the scene delegate and chapter-list builder; the host wires them into its scene manifest.

> **External blocker — Apple grant required.** `com.apple.developer.carplay-audio` is a *restricted* entitlement. Apple grants it per app on request (developer.apple.com → CarPlay request form). Until the grant lands, the entitlement cannot be code-signed and CarPlay will not run on device. Plan for this lead time — it gates any consumer (including Fablum) shipping CarPlay.

**Entitlement.** Add to `ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.carplay-audio</key>
<true/>
```

Set `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` in the target's build settings once the grant is approved. (The flureadium example ships this file as a reference template but does **not** wire it into `CODE_SIGN_ENTITLEMENTS`, so the example builds without the grant.)

**Scene manifest.** CarPlay uses the UIScene lifecycle, so the app declares both a window scene and a CarPlay scene in `Info.plist`:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <true/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>UIWindowScene</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
                <key>UISceneConfigurationName</key>
                <string>flutter</string>
                <key>UISceneStoryboardFile</key>
                <string>Main</string>
            </dict>
        </array>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>CPTemplateApplicationScene</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
                <key>UISceneConfigurationName</key>
                <string>carplay</string>
            </dict>
        </array>
    </dict>
</dict>
```

Adopting the scene lifecycle means `AppDelegate` no longer owns the window. The example app's `AppDelegate` migrates to scene-role routing and registers Flutter plugins against the implicit engine; the `SceneDelegate` owns the Flutter window scene and the `CarPlaySceneDelegate` owns the CarPlay scene. Mirror this split in your host app.

**Background audio.** CarPlay playback also needs the `audio` background mode from step 3.

**Testing in the simulator:**

1. Run the app on an iOS simulator.
2. From the simulator menu, choose **I/O → External Displays → CarPlay** to open the CarPlay window.
3. Open an audiobook in the app so a publication is loaded. The app's chapter list appears in the CarPlay window; selecting a row plays that chapter, and the now-playing transport (play/pause/skip/seek) works.

> The simulator does not require the Apple entitlement grant, so it is the fastest way to verify the chapter list and transport wiring before the on-device grant arrives.

## Implementation Details

### CarPlay Chapter List

The CarPlay scene presents the open audiobook's chapters and routes selections back to the active navigator:

- `CarPlayChapterList.chapters(from:)` derives one row per `readingOrder` entry. Titles fall back to a localized `Chapter N` (English, Danish, Swedish, Norwegian, Icelandic) using the publication's language when an entry has no title.
- `CarPlaySceneDelegate` builds a `CPListTemplate` of those chapters and, on row selection, calls `CarPlayPlaybackBridge.playChapter(at:)` to seek the same audiobook navigator the in-app controls drive.
- Transport controls and now-playing metadata come for free from the plugin's `NowPlayingInfoUpdater`, which already drives `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` for the lockscreen. CarPlay reuses that state — no separate wiring.

`CarPlayChapterList` is a pure function over a `Publication`, so it is unit-testable without a CarPlay scene (see `CarPlayChapterListTests.swift` / `CarPlayPlaybackBridgeTests.swift`).

**Files:**
- `carplay/CarPlayChapterList.swift` — derives chapter rows from the reading order
- `carplay/CarPlayPlaybackBridge.swift` — bridges row selection to the navigator
- `example/ios/Runner/CarPlaySceneDelegate.swift` — CarPlay scene: builds the list template
- `example/ios/Runner/SceneDelegate.swift` — window scene owning the Flutter view
- `example/ios/Runner/Runner.entitlements` — CarPlay-audio entitlement (reference template)

### Plugin Structure

```
ios/Sources/flureadium/
├── FlureadiumPlugin.swift       # Plugin registration
├── ReadiumReaderViewFactory.swift # Platform view factory
├── ReadiumReaderView.swift      # EPUB reader view
├── PdfReaderView.swift          # PDF reader view
├── ImageReaderView.swift        # CBZ / DIVINA reader view
├── EdgeTapInterceptView.swift   # Edge tap and swipe overlay
└── PageThumbnailExtractor.swift # Downscaled JPEG thumbnails for image resources
```

### Platform View

Uses `UiKitView` for embedding UIKit views:

```swift
class ReadiumReaderViewFactory: NSObject, FlutterPlatformViewFactory {
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return ReadiumReaderView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            messenger: messenger
        )
    }
}
```

### Readium Integration

Uses Readium Swift Toolkit 3.5.0:
- `Streamer` for EPUB parsing
- `EPUBNavigatorViewController` for content display
- `AVSpeechSynthesizer` for TTS
- `AVPlayer` for audio

### Audiobook End of Book

`FlutterAudioNavigator` emits `TimebasedState.ended` when an audiobook reaches
its natural end. Readium calls the `shouldPlayNextResource` delegate hook each
time a resource finishes; at the last resource (`resourceIndex` is the final
index of `publication.readingOrder`) the navigator emits one `.ended` state and
returns `false` to stop playback. Earlier resources return `true` and emit
nothing, so the next track plays as usual. This is the signal hosts listen for
to show an end-of-book completion screen.

### Local Server

Uses GCDWebServer to serve EPUB resources:
- Runs on localhost (127.0.0.1)
- Requires NSAppTransportSecurity exception
- Automatically starts/stops with publication

### Edge Tap and Swipe Navigation

The flureadium iOS plugin supports both edge tap and swipe gesture navigation for EPUB, PDF, and image-based readers.

**How It Works:**

The `EdgeTapInterceptView` is a transparent UIView overlay that:
- Intercepts single taps on the left/right edges of the screen → triggers `goLeft()` / `goRight()`
- Intercepts swipe left/right gestures → triggers `goRight()` / `goLeft()`
- Passes through all other touches to the underlying reader view

**Note:** In EPUB scroll mode, both gestures are automatically disabled regardless of configuration.

**Configuring from Dart:**

Navigation behavior is configured via `setNavigationConfig()`, which is separate from Readium reading preferences:

```dart
// EPUB: disable edge taps but keep swipes
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(
    enableEdgeTapNavigation: false,
    enableSwipeNavigation: true,
  ),
);

// PDF: wider tap zones
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(
    enableEdgeTapNavigation: true,
    edgeTapAreaPoints: 80,
  ),
);
```

Both default to enabled (`true`) when not set. The `edgeTapAreaPoints` value is in absolute iOS points (44–120, clamped automatically) and defaults to 44pt (iOS HIG minimum tap target).

**iOS 26 touch routing — `interceptEdgeTaps`:**

On iOS 26+, Flutter changed how platform view touches are routed. Edge-zone touches now fall through `EdgeTapInterceptView` to the underlying WKWebView when there are no intercept callbacks set, which lets Readium's `DirectionalNavigationAdapter` see those touches — even when edge tap navigation is turned off.

To fix this, `EdgeTapInterceptView` has an `interceptEdgeTaps: Bool` property (default `false`) that is independent of callback presence:

- **EPUB paginated mode** — `interceptEdgeTaps = true` always. The view absorbs all edge-zone touches regardless of whether callbacks are configured. `DirectionalNavigationAdapter` never sees them.
- **EPUB scroll mode** — `interceptEdgeTaps = false`. WKWebView receives all touches natively for scrolling.
- **PDF reader** — `interceptEdgeTaps = enableEdgeTapNavigation`. PDF has no scroll mode on this path, so the view only intercepts when the feature is on.
- **Image reader** — `interceptEdgeTaps = enableEdgeTapNavigation`. CBZ and DIVINA use the same edge-tap/swipe overlay pattern as the PDF path.

This is a native iOS layer change only. No Dart or Flutter changes are required.

**Files:**
- `EdgeTapInterceptView.swift` - Shared edge tap and swipe detection view
- `ReadiumReaderView.swift` - EPUB reader using EdgeTapInterceptView
- `PdfReaderView.swift` - PDF reader using EdgeTapInterceptView
- `ImageReaderView.swift` - CBZ / DIVINA reader using EdgeTapInterceptView

Programmatic `goToLocator` calls route to the active EPUB, PDF, image, or time-based navigator. For CBZ/DIVINA, `ImageReaderView` waits briefly for the Readium image navigator to report readiness before calling `go(to:)`; it returns `false` instead of hanging indefinitely if readiness never arrives.

### CBZ Image Caching

Readium's CBZ navigator creates a new `ImageViewController` for every page turn, each fetching the full image from a local HTTP server via `URLSession.shared`. The server's `ResourceResponse` sets `Cache-Control: no-cache, no-store, must-revalidate` to protect DRM-enabled content, which prevents `URLCache` from storing responses. For CBZ and DiViNa publications (which have no DRM), this causes redundant ZIP extraction and HTTP round-trips on every swipe.

`ImageCacheURLProtocol` is a `URLProtocol` subclass that transparently intercepts these localhost HTTP GET requests and caches image data in `NSCache`. On cache hit, images are served instantly from memory without any network or ZIP extraction overhead.

**Primary cache:**
- Intercepts only HTTP GET requests to `localhost` / `127.0.0.1` — EPUB (WKWebView), PDF (PDFKit), and external traffic are unaffected
- Registered when `ImageReaderView` initializes, unregistered when it disposes
- Cache is session-scoped: cleared automatically when the publication closes
- `NSCache` with explicit limits: 100 MB total cost, 30-entry count limit

**Prefetch cache:**

After each page turn, `ImageReaderView` reads adjacent pages (N-1, N+1, N+2) directly from the ZIP container via `Publication.get(link)` and stores them in a secondary prefetch dictionary inside `ImageCacheURLProtocol`. This bypasses the HTTP server entirely — for CBZ files using ZIP STORE (no compression), it's a fast memory copy.

When Readium's `ImageViewController` loads a page, `ImageCacheURLProtocol.startLoading()` checks the prefetch store after a primary cache miss. On hit, the data is served instantly, promoted to the primary `NSCache`, and removed from the prefetch store. This eliminates the visible blank flash during page transitions.

Prefetch skips:
- Pages already visited (tracked via `visitedIndices` — already in primary cache)
- Pages already prefetched (checked via `hasPrefetch(href:)`)
- Out-of-range indices

The prefetch store is a small thread-safe dictionary (typically 3 entries), synchronized with `NSLock`. URL matching uses path suffix comparison with percent-decoding to handle all encoding combinations.

Fast swiping is handled by cancelling the in-flight prefetch task on each new page turn, preventing wasted I/O on pages the user has already passed. All prefetch state (task, visited indices, store) is cleared on dispose.

**Files:**
- `ImageCacheURLProtocol.swift` — URLProtocol subclass with primary NSCache + secondary prefetch store
- `ImageReaderView.swift` — enable/disable calls in init and dispose, prefetch logic in `locationDidChange`

### Page Thumbnails

`extractPageThumbnail(href, maxHeight, quality)` reads an image resource from the currently open publication and returns a downscaled JPEG. This is primarily useful for CBZ/DIVINA page previews and TOC thumbnail UI.

The iOS implementation:
- Resolves the incoming href with `AnyURL(legacyHREF:)`, matching Readium's manifest href handling.
- Reads the resource from the active `Publication`, so the same mounted publication and Readium access path are reused.
- Uses ImageIO's thumbnail creation path (`CGImageSourceCreateThumbnailAtIndex`) with `kCGImageSourceThumbnailMaxPixelSize`, avoiding a full-size bitmap decode.
- Compresses to JPEG with the requested 0-100 quality value.
- Returns `nil` when no publication is open, the href cannot be resolved, `maxHeight <= 0`, or ImageIO cannot decode the resource.

**Files:**
- `PageThumbnailExtractor.swift` — ImageIO thumbnail decode and JPEG encode helper
- `FlureadiumPlugin.swift` — `extractPageThumbnail` method-channel handler

### Text Selection Copy

When a user long-presses text in an EPUB or PDF reader, iOS shows a native
selection menu.

**EPUB:** The menu shows Copy, Look Up, and Translate. This is configured via
Readium's `EditingAction` support with
`config.editingActions = [.copy, .lookup, .translate]` in
`EPUBNavigatorViewController.Configuration`. The `.copy` action uses the native
`copy:` responder selector and copies the current selection to
`UIPasteboard.general`.

**PDF:** Copy is available through Readium's default editing actions
(`EditingAction.defaultActions = [.copy, .share, .lookup, .translate]`). The
`PDFNavigatorViewController` path keeps those defaults.

> Note: Copy still respects DRM rights. For protected publications, Readium
> checks `UserRights.copy(text:)` before writing to the pasteboard and silently
> blocks copy when the license denies it.

### Stream and View Lifecycle

Flureadium iOS uses `EventStreamHandler` to manage Flutter EventChannel streams (text locator, reader status, errors). The `"dispose"` method call from Dart is the single comprehensive cleanup point. `deinit` is a minimal safety net.

The `error` channel is the exception to per-view ownership. `FlureadiumPlugin` owns it: the handler is created once in `register(with:)` and disposed only when the plugin's own `"dispose"` runs. Reader views forward resource-load failures through the plugin's `sendError(message:code:data:)` instead of holding their own `error` handler, so closing a reader view no longer end-streams the Dart subscription, and the audiobook player (which has no reader view) can send on the same channel. The PDF reader keeps its separate `pdf-error` channel.

**dispose handler** owns all cleanup that needs a live Flutter engine:

| Responsibility | Why in dispose |
|----------------|----------------|
| Send "closed" status event | Needs live Flutter engine |
| Stream `.dispose()` (sends `FlutterEndOfEventStream`) | Needs live Flutter engine |
| Nil stream handler references | Part of explicit teardown |
| Nil channel method call handler | Prevents calls after dispose |
| Remove subview | Idempotent, safe in both |
| Nil delegate | Part of explicit teardown |
| Nil global reference (identity-guarded) | Explicit lifecycle event |

**deinit** retains only `removeFromSuperview()` — it handles the edge case where the native view is deallocated without the Dart `dispose` call being received (engine teardown, hot restart). All property nilling is removed because ARC handles it automatically when the object deallocates. `deinit` must not send messages on Flutter channels, as it may run during engine teardown when channels are already torn down.

### Global Reference Lifecycle

The plugin tracks the active reader view via two module-level globals in `FlureadiumPlugin.swift`:

```swift
internal weak var currentReaderView: ReadiumReaderView?
internal weak var currentPdfReaderView: PdfReaderView?
```

Both are `weak var` — they do not own the view. This mirrors Android's `WeakReference<ReadiumReaderWidget>` pattern in `ReadiumReader.kt`. The weak reference prevents a Swift runtime exclusivity violation that would otherwise occur during hot reload: when a new view's `init` assigns itself to the global, ARC releases the old value, triggering the old view's `deinit` — if `deinit` also writes to the same global, Swift detects overlapping exclusive writes and aborts.

Cleanup responsibilities:

| Event | What happens |
|-------|-------------|
| `init` | View assigns itself to the global (`currentReaderView = self`) |
| `"dispose"` method call | Identity-guarded cleanup (`if currentReaderView === self { currentReaderView = nil }`) — prevents clearing a newer view that replaced this one during hot reload |
| `closePublication()` | Nils both globals before closing the publication — correct teardown order since views reference the publication |
| `deinit` | Does not touch globals — handles only the view's own resource cleanup |

The identity guard in the dispose handler matches Android's pattern at `ReadiumReaderWidget.kt:79`.

**Files:**
- `EventStreamHandler.swift` - Stream handler with `dispose()` that sends `FlutterEndOfEventStream`
- `FlureadiumPlugin.swift` - Global weak references and `closePublication()` cleanup
- `ReadiumReaderView.swift` - EPUB reader: init assigns global, dispose handler clears it
- `PdfReaderView.swift` - PDF reader: same pattern as EPUB

## Troubleshooting

### Pod Install Fails

```bash
cd ios
pod deintegrate
pod cache clean --all
pod repo update
pod install
```

### "No such module" Error

Clean build and reinstall:
```bash
cd ios
rm -rf Pods
rm Podfile.lock
pod install
flutter clean
flutter build ios
```

### Localhost Connection Refused

Ensure NSAppTransportSecurity is configured in Info.plist.

### TTS Voice Quality

iOS provides high-quality voices. To check available voices:
```dart
final voices = await flureadium.ttsGetAvailableVoices();
// Look for "Enhanced" or "Premium" voices
```

### Memory Warnings

Close publication when not in use:
```dart
@override
void dispose() {
  flureadium.closePublication();
  super.dispose();
}
```

## Privacy Manifest

For App Store submission, the plugin includes `PrivacyInfo.xcprivacy` declaring:
- No user data collection
- Local file access only

## See Also

- [Installation Guide](../getting-started/installation.md)
- [Architecture Overview](../architecture/overview.md)
- [Troubleshooting](../troubleshooting.md)
