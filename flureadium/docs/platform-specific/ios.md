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

To expose a browsable library and transport controls on CarPlay, the host app adds a CarPlay scene and the CarPlay-audio entitlement. Flureadium ships the renderer that turns the host's library into CarPlay templates; the host supplies that library through a `CarContentProvider` (see [Car content](../api-reference/car-content.md)) and wires the scene into its manifest.

> **External blocker — Apple grant required.** `com.apple.developer.carplay-audio` is a *restricted* entitlement. Apple grants it per app on request (developer.apple.com → CarPlay request form). Until the grant lands, the entitlement cannot be code-signed and CarPlay will not run on device. Plan for this lead time — it gates any consumer shipping CarPlay.

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

Adopting the scene lifecycle means `AppDelegate` no longer owns the window. The example app's `AppDelegate` migrates to scene-role routing and registers Flutter plugins against the implicit engine; the `SceneDelegate` owns the Flutter window scene and the `CarPlaySceneDelegate` owns the CarPlay scene. Mirror this split in your host app. The CarPlay scene answers browse/play over its own app-scoped headless `FlutterEngine` (see [CarPlay library browse](#carplay-library-browse) below), separate from the window scene's engine, so it works even when no reader UI is alive.

**Background audio.** CarPlay playback also needs the `audio` background mode from step 3.

**Testing in the simulator:**

1. Fully quit the app, then run it on an iOS simulator.
2. Enable CarPlay: `defaults write com.apple.iphonesimulator CarPlay -bool YES`, relaunch the simulator, then choose **I/O → External Displays → CarPlay**.
3. Tap the app's icon on the CarPlay home screen. The library tabs (Continue · Library · Search) appear, populated over the car engine — you do not need to open anything in the phone app first. Selecting a container row pushes its children; selecting a playable row logs a tap round-trip back to Dart. That is the STAGE-1 proof: the cold car engine boots and the channel answers. Real playback and the now-playing transport (play/pause/skip/seek) come with a real host provider in a later phase.

> The simulator does not require the Apple entitlement grant, so it is the fastest way to verify the browse tree and the tap round-trip before the on-device grant arrives. The flureadium example registers a small stub library (`carMain` in `example/lib/car_stub.dart`) so this runs without any real content.

## Implementation Details

### CarPlay library browse

The CarPlay scene renders a host's library as CarPlay templates and routes selections back to the host over a method channel. The host answers browse, search, and play through a `CarContentProvider`; flureadium owns the rendering, the host owns the content.

- `CarTemplateRenderer` turns the node tree into templates: a `CPTabBarTemplate` of the root tabs, a `CPListTemplate` per tab, and child lists pushed on navigation. It sets a status root synchronously and fills each list asynchronously (`updateSections`) as the provider answers, so a cold connect is never blank. When the root has no tabs it shows a status-only empty view built from the host's `CarContentStrings`.
- `CarListItemFactory` builds one `CPListItem` per node — mapping `progress` → `playbackProgress`, now-playing → `isPlaying`, and cover art → an async-loaded image — and stamps the node id on `userInfo` so a selection can be traced back to its node.
- `CarPlayContentBridge` is the channel-backed data source on `dev.mulev.flureadium/car`. On a cold connect it briefly retries browse calls until the car engine's Dart handler is installed, so the startup race is not mistaken for an empty library.
- The host runs a Dart car entrypoint on an app-scoped headless `FlutterEngine` so the channel can answer with no reader UI alive. The example does this in `carMain` + `CarPlayEngine`; a host picks its own engine strategy (a dedicated car engine, or a single shared app engine) without changing the renderer.

The renderer, factory, and bridge are decoupled from the interface controller and the transport behind seams, so they are unit-tested without a live CarPlay scene (`CarTemplateRendererTests` / `CarListItemFactoryTests` / `CarContentModelsTests`). The node→template mapping is Swift, so those assertions live in the iOS XCTest suite; the provider/transport round-trip is covered in Dart.

The earlier single-audiobook chapter list (`CarPlayChapterList` / `CarPlayPlaybackBridge`) still drives the now-playing chapters path and is unchanged here; it folds into the node model in a later phase.

**Files:**
- `carplay/CarTemplateRenderer.swift` — node tree → CarPlay templates
- `carplay/CarListItemFactory.swift` — one node → one `CPListItem`
- `carplay/CarPlayContentBridge.swift` — channel-backed browse/play data source
- `carplay/CarBrowseNode.swift` — Swift mirror of the Dart car value types
- `example/lib/car_stub.dart` — example stub `CarContentProvider` (STAGE-1)
- `example/ios/Runner/CarPlayEngine.swift` — example's headless car engine
- `example/ios/Runner/CarPlaySceneDelegate.swift` — thin scene adapter → renderer
- `example/ios/Runner/Runner.entitlements` — CarPlay-audio entitlement (reference template)

### CarPlay search: Siri assistant cell and typed search

The Search tab offers two ways in, gated by iOS version and by the vehicle.

**Siri assistant cell (iOS 15+).** When the host marks a Search-tab row with `CarNodeKind.siri`, the renderer installs CarPlay's system assistant cell on that tab's list (`CarAssistantCell` builds a `CPAssistantCellConfiguration(position: .top, visibility: .always, assistantAction: .playMedia)`). CarPlay draws and owns the cell; tapping it hands off to Siri, and the app gets no tap callback. The host app must instead ship an **Intents extension** that handles `INPlayMediaIntent`, which Siri invokes with the spoken query. The `CPAssistantCellConfiguration` API ships from iOS 15, so this is the baseline search path up to the iOS 27 typed template. iOS 14 CarPlay has no assistant-cell API and shows no dedicated search row.

**Typed search (iOS 27+, keyboard-capable vehicles).** Audio apps may present the typed `CPSearchTemplate` only from iOS 27, and only when the vehicle allows a keyboard (`CPSessionConfiguration.limitedUserInterfaces` without `.keyboard`, usually off while moving). When both hold, the Search tab adds one row that pushes `CarSearchTemplate`, labeled from the tab's own title since it opens the keyboard rather than Siri. The delegate runs each keystroke through `bridge.search` and maps the results to list items (`CarListItemFactory`, node id stamped on `userInfo`); selecting a result routes that id to `bridge.select`, which calls the provider's `play`. Keyboard availability is re-checked when the row is tapped, so a row built while parked does not present search once the keyboard is disabled. On iOS 15 through pre-27, or without a keyboard, the tab shows only the Siri assistant cell, with no broken typed entry.

The renderer, the search delegate, and the assistant-cell configuration are decoupled from the interface controller and the scene, so they are unit-tested without a live CarPlay scene (`CarTemplateRendererTests` / `CarSearchTemplateTests` / `CarAssistantCellTests`). The example scene delegate supplies keyboard availability from its `CPSessionConfiguration`.

`CarNodeKind.siri` is an iOS-only affordance marker. Android Auto has no browse-row equivalent (voice search there is Google Assistant), so the Android browse mapping drops `siri` nodes rather than showing a dead row.

**Files:**
- `carplay/CarSearchTemplate.swift` — iOS 27+ typed `CPSearchTemplate` delegate → bridge
- `carplay/CarAssistantCell.swift` — Siri assistant-cell configuration for the Search tab

### Plugin Structure

```
ios/Sources/flureadium/
├── FlureadiumPlugin.swift       # Plugin registration
├── ReadiumReaderViewFactory.swift # Platform view factory
├── ReadiumReaderView.swift      # EPUB reader view
├── PdfReaderView.swift          # PDF reader view
├── ImageReaderView.swift        # CBZ / DIVINA reader view
├── AudioReaderView.swift        # Audio-only reader host (no navigator)
├── EpubUserScripts.swift        # The WKUserScripts the EPUB WebView injects
├── EpubNavigatorConfiguration.swift # The configuration handed to the Readium EPUB navigator
├── SpineItemPositionMemory.swift # The scroll position remembered per spine item, for swipe-back
├── EpubPageBridge.swift         # Every call into the window.epubPage JavaScript API
├── EpubLocatorReporter.swift    # Publishes fragment-resolved locators to the Flutter reader channel
├── EpubReaderCommand.swift      # Decodes a reader method-channel call into a typed command
├── PdfGestureSuppression.swift  # Removes the built-in PDF gestures the host disabled
├── EdgeTapInterceptView.swift   # Edge tap and swipe overlay
├── ReaderEdgeNavigationState.swift # Host edge tap/swipe config, shared by all three visual readers
├── ReaderTapObserver.swift      # Registers Readium's tap observer on a navigator
├── PageThumbnailExtractor.swift # Downscaled JPEG thumbnails for image resources
└── utils/UIViewPinning.swift    # Adds a subview pinned to its parent's four edges
```

`ReadiumReaderView` no longer reads channel arguments itself. Every call the
EPUB reader receives goes through `EpubReaderCommand(call)` first, which turns
the method name and its argument list into a typed command — or nil for a method
the view does not implement, which the view answers with
`FlutterMethodNotImplemented`. The view's switch then only executes. Argument
order and the optional trailing flags (`isAudioBookWithText` on `go` and
`setLocation`) are covered by `EpubReaderCommandTests`.

PDF gesture suppression is one type, `PdfGestureSuppression`. It holds the four
host flags (`disableDoubleTapZoom`, `disableTextSelection`, `disableDragGestures`,
`disableDoubleTapTextSelection`) and walks the navigator's live view tree,
matching UIKit recognizers and interactions by class and by runtime type name.
`PdfReaderView` applies it in two places: the full retained state when the
navigator hands over its view (`setupPDFView`), and on a `setNavigationConfig`
call only the flags that call turned on, against the live view. So switching a
flag on takes effect while the PDF is open, but switching one off does not bring
the gesture back — nothing re-enables a disabled recognizer or re-adds a removed
interaction, so the gesture returns only once the navigator hands over a fresh
view. Because `PDFTextInputView` is attached asynchronously after a page
renders, removing double-tap word selection is retried at 0.1s, 0.5s and 1.0s.
`PdfGestureSuppressionTests` covers every
predicate against synthetic view trees.

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

### Audiobook Error Forwarding

Streamed audio load failures reach Flutter on the `onErrorEvent` stream. The
plugin owns the single `error` channel; the audio path forwards through it three
ways:

- **Container wrapper route (load-time)** — during publication opening,
  `Readium.setupWithHeaders` installs an `onCreatePublication` transform
  (`AudioResourceLoadFailureReporter`) that wraps each audiobook track resource
  in a `LoadFailureObservingResource`. `PublicationMediaLoader` reads every track
  through that container over a custom `readium://` scheme, so a failed length
  probe or byte read — the exact failure Readium otherwise hands to
  `AVAssetResourceLoadingRequest.finishLoading(with:)` and drops — is caught at
  the read boundary and routed onto the error channel as
  `sendError(code: "TimebasedError")`. One error per failed track, reset per
  publication. This makes a genuine load-time failure (unreachable host, missing
  or errored track) deterministically observable, even when playback never
  starts.
  Cancelled reads (`HTTPError.cancelled`) are filtered out in
  `AudioResourceLoadFailureReporter.report` before the per-track de-dup. A
  streamed track plays through `PublicationMediaLoader`, an
  `AVAssetResourceLoaderDelegate`; per Apple, "previously issued loading requests
  can be cancelled when data from the resource is no longer required or when a
  loading request is superseded by new requests for data from the same resource"
  (for example, to complete a seek). Readium handles that in
  `resourceLoader(_:didCancel:)`, which calls `finishRequest` to cancel the
  in-flight read task. Its HTTP client then maps the resulting
  `URLError.cancelled` ("An asynchronous load has been canceled") to
  `HTTPError.cancelled`. A cancellation is benign churn, not a load
  failure, so it is never sent; filtering ahead of the de-dup keeps a genuine
  failure that arrives later on the same track reportable. Sources: Apple —
  [`AVAssetResourceLoaderDelegate.resourceLoader(_:didCancel:)`](https://developer.apple.com/documentation/avfoundation/avassetresourceloaderdelegate/resourceloader(_:didcancel:)-3nl51)
  (Obj-C selector `resourceLoader:didCancelLoadingRequest:`) and
  [`URLError.Code.cancelled`](https://developer.apple.com/documentation/foundation/urlerror/code/cancelled);
  Readium 3.5.0 — [`DefaultHTTPClient`](https://github.com/readium/swift-toolkit/blob/8bd799d00a835248a6f5987f70c23c4c30280e48/Sources/Shared/Toolkit/HTTP/DefaultHTTPClient.swift#L533-L534)
  (`URLError.cancelled` → `HTTPError.cancelled`) and
  [`PublicationMediaLoader.finishRequest`](https://github.com/readium/swift-toolkit/blob/8bd799d00a835248a6f5987f70c23c4c30280e48/Sources/Navigator/Audiobook/PublicationMediaLoader.swift#L88-L109).
- **Delegate route** — `FlutterAudioNavigator`'s `didFailToLoadResourceAt`
  delegate routes any error Readium surfaces into the timebased navigator's
  `encounteredError` hook, which the plugin implements as
  `sendError(message:, code: "TimebasedError", data:)`.
- **NotificationCenter route** — Readium's audio stack never routes AVFoundation
  playback failures to its delegate, and its `AVPlayer` is private. So the navigator
  also registers best-effort observers for `AVPlayerItemFailedToPlayToEndTime`
  and `AVPlayerItemNewErrorLogEntry` (`object: nil`) over its lifetime, removed
  in `dispose()`. Both route through the same `handlePlaybackFailure` seam.
  Each observer closure hands off with `Task { @MainActor in … }`, because the
  closure `NotificationCenter` calls is nonisolated while `handlePlaybackFailure`
  is main-actor isolated through the `AudioNavigatorDelegate` conformance. A
  failure therefore reaches the listener one main-actor hop after the notification
  posts — see [the hop rule](../architecture/overview.md#ios-a-stored-closure-that-reads-a-navigator-is-mainactor)
  for why a hop rather than `MainActor.assumeIsolated`.

**Limitation:** the container wrapper catches resource-load failures — a track
that fails to load and never starts. It does not catch **post-load** problems:
once bytes load cleanly, an `AVPlayer` decode/status failure or a healthy-URL
stall (a well-formed stream that stops progressing) is a KVO signal on Readium's
private item and posts no notification. The NotificationCenter observers are the
best-effort net for those cases and do not fire for every one. So a stall after a
clean load may still show no `onErrorEvent`; a deterministic upstream hook for
post-load failures is a tracked follow-up. Android has no such gap:
`ReadiumReader.onTimebasedPlaybackFailure` forwards every timebased failure.

The `unreachable streamed audio surfaces an error event` integration test runs on
both platforms and covers the load-time path. The `partial stream failure`
integration test stays iOS-skipped (it exercises a mid-stream truncation iOS does
not reliably report). `ReadiumReaderTimebasedErrorTest` covers the Android
forwarding at the unit level; `LoadFailureObservingResourceTests` and
`AudioResourceLoadFailureReporterTests` cover the iOS wrapper.

### A Failed audioEnable Answers Dart

`audioEnable` runs its work in a detached `Task`, and the `Task<Void, Error>` it
returns is discarded. An error thrown inside an unobserved Task is stored there
and dropped, so before this the call would neither answer nor report: the Dart
future waited forever with nothing on `onErrorEvent`.

The body is wrapped now. A throw answers with a `ReaderFailure` `FlutterError`
and reports the same code on the error channel; a `CancellationError` answers
nothing, because a call cancelled with its reader has nobody waiting. This is
the iOS counterpart of Android's method-channel guard.

Neither `try` in that body can throw as the code stands —
`FlutterAudioPreferences.init(fromMap:)` is declared `throws` but reads every
value with a default, and both `FlutterAudioNavigator` and
`FlutterMediaOverlayNavigator` declare `initNavigator()` as `async -> Void`. The
`FlutterTimebasedNavigator` protocol declares it `async throws`, so a navigator
added later can throw, and the call site answers for it either way.
`FlureadiumPluginAudioEnableTests` covers the reachable half: the call answers,
and answers exactly once.

### Audio-Only Reader Host

An audio-only publication mounts `AudioReaderView`, not the EPUB reader view.
`readerViewKind(for:)` resolves it after the PDF and image checks, using
Readium's own predicate: `publication.conforms(to: .audiobook)` is
`readingOrder.allAreAudio` behind a non-empty guard, so the kind follows the
reading order rather than a manifest claim. A media-overlay EPUB is unaffected —
its reading order is HTML, so it keeps the EPUB navigator and the karaoke path
even when the manifest declares the audiobook profile. That is also why the
audio branch does not consult `metadata.conformsTo`, unlike the PDF and DiViNa
branches above it.

`AudioReaderView` builds no navigator: no `EPUBNavigatorViewController`, no
pagination view, no preload WKWebViews, no `httpServer.serve` routes, no
ReadiumCSS transformer. Before this routing existed, a streamed audiobook paid
for all of it — and the preloaded spreads fetched the same reading-order URLs
AVFoundation was streaming.

What the host does provide:

| Concern | Behavior |
|---------|----------|
| Reader status | `loading` then `ready`, both from `init` — with no navigator there is no `locationDidChange` to report readiness later |
| `text-locator` | Never sent on: there is no page |
| `getLocatorFragments` | Echoes its argument — no DOM to resolve a fragment against |
| `isReaderReady` / `isLocatorVisible` | `true` / `false` |
| `getCurrentLocator` | `nil` |
| Navigation, preferences, decorations | No-ops answering `nil` |
| `dispose` | Sends `closed` and clears its method-call handler; the shared channels stay open, since the plugin owns them |

`currentReaderView` stays `nil`, so the plugin paths that drive the visual
reader — `reachedLocator`, `updateReaderViewTimebasedDecorations`, the TTS
initial-location lookup — become no-ops instead of driving an invisible
navigator across audio files. This matches Android, where `ReadiumReaderWidget`
skips navigator setup for `PublicationReaderKind.AUDIO` and reports readiness
the same way.

### Local Server

Uses GCDWebServer to serve EPUB resources:
- Runs on localhost (127.0.0.1)
- Requires NSAppTransportSecurity exception
- Automatically starts/stops with publication

### Content Taps

`ReadiumReaderWidget.onTap` fires for a tap on content — a tap that nothing else
claimed. The plugin does not detect these taps itself: it registers Readium's own
observer on the navigator, so the toolkit decides what counts as a content tap
before the plugin hears about it.

`observeTaps(on:reportingTo:)` (`ReaderTapObserver.swift`) adds an
`ActivatePointerObserver` through `InputObservable.addObserver` and returns the
token the view keeps. All three visual views register in `init` and unregister in
their `dispose` handler. Coordinates come from `PointerEvent.location`, already in
points relative to the navigator view, and cross the channel as `{"x": …, "y": …}`
— the same unit Flutter calls logical pixels.

**EPUB filters link taps for you.** Inside the WebView, Readium drops a pointer
event that landed on an interactive element before any observer runs
(`EPUBSpreadView.didReceivePointerEvent` checks `interactiveElement`, fed by
`gestures.js`). A tap on a hyperlink or footnote navigates and reports no tap, so
a host can safely toggle its chrome on every `onTap`.

**PDF and CBZ do not.** That filter is WebView-specific. Tapping an internal link
annotation in a PDF both follows the link and reports a tap. PDFKit exposes no way
to ask whether an annotation consumed the touch, so the plugin does not guess —
hosts that care can ignore taps that arrive alongside a page change.

The observer returns `false`, so it never consumes the event. Registration order
still matters — the tap observer is added after
`DirectionalNavigationAdapter.bind(to:)` — but that adapter no longer registers a
pointer observer at all, so nothing behind the tap observer turns a page. See
[Edge Tap and Swipe Navigation](#edge-tap-and-swipe-navigation).

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

**One pointer edge owner:**

`EdgeTapInterceptView` is the only component on iOS that reacts to a pointer near an
edge. Readium's `DirectionalNavigationAdapter` is built with
`pointerPolicy: .init(types: [])` (`ReadiumReaderView.edgeTapPointerPolicy`), and
`bind(to:)` skips every pointer type absent from that set. It registers the key
observer unconditionally, so arrow keys and the space bar still turn pages.

Before 0.17.0 both components claimed edge taps, with two widths and one gate between
them. The overlay absorbed `edgeTapAreaPoints` — 44 pt by default — while the adapter
claimed `max(80, 0.3 × width)`, or 117.9 pt on a 393 pt iPhone, and only the overlay
was gated on `enableEdgeTapNavigation`. A tap anywhere in the 147.8 pt between the two
widths, 37.6% of that screen, turned a page while the host's preference read `false`.
Android never had a second owner, so this brings iOS in line with it.

**Touch routing — `interceptEdgeTaps`:**

Flutter delivers a platform-view touch to whatever `hitTest` returns, and on iOS 26+
an edge-zone touch falls through to the WKWebView unless the overlay claims it. That
claim turns a page when edge tap is on, and swallows a content tap when it is off —
which would keep `onTap` from firing anywhere near an edge. So the property follows
the gate rather than the mode alone.

All three visual readers run the same gate, held by one type —
`ReaderEdgeNavigationState`. It keeps the host's `enableEdgeTapNavigation`,
`enableSwipeNavigation` and `edgeTapAreaPoints`, and `configure(edgeTapView:navigator:isScrollMode:animated:)`
points the overlay's callbacks at the navigator or clears them:

- **EPUB** — passes its live scroll mode, so `interceptEdgeTaps = !isScrollMode && enableEdgeTapNavigation`,
  from the `shouldInterceptEdgeTaps` helper. Paginated with edge tap on, the overlay
  absorbs both edge zones and turns pages. With edge tap off, or in scroll mode, it
  absorbs nothing: every tap reaches the WebView, and Readium reports it as a content
  tap. Page turns are animated.
- **PDF reader** — no scroll mode on this path, so it omits the argument and the
  paginated gate always holds: `interceptEdgeTaps = enableEdgeTapNavigation`. Page
  turns are animated.
- **Image reader** — same gate as PDF. CBZ and DIVINA turn pages without animation.

Swipes follow the same rule as taps except for the threshold: the plugin's two
recognizers are wired whenever the reader is paginated and the host left
`enableSwipeNavigation` on. Swiping left advances, swiping right goes back.

What turning the flag off does **not** do is stop paging. It clears those two
callbacks — the recognizers stay attached to the overlay container and fire into
nothing — while Readium's `PaginationView`, a paging `UIScrollView` this plugin
never disables, still turns the page on a horizontal drag. Android has the same
gap for its own reason (`R2WebView` owns the drag there), so no platform can
switch EPUB swiping off through this flag.

**Files:**
- `EdgeTapInterceptView.swift` - Shared edge tap and swipe detection view
- `ReaderEdgeNavigationState.swift` - The host's gate, and the wiring all three readers share
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

**`FlureadiumPlugin` owns every shared event channel** — `error`, `reader-status`,
`text-locator` and `timebased-state`. Each handler is created once in
`register(with:)` and disposed only when the plugin's own `"dispose"` runs.
Reader views send through the plugin (`sendError`, `sendReaderStatus`,
`sendTextLocator`) instead of holding their own handlers.

That ownership is load-bearing, not tidiness. A reader view is shorter-lived
than the Dart subscription: Flutter builds the replacement platform view before
disposing the one it replaces, so a view that owned these channels would
end-stream them on teardown. `MethodChannelFlureadium` memoizes both streams,
so nothing re-opens them — one publication swap and the host stops receiving
statuses and locators for the rest of the session. Android never had this
problem; `ReaderStatusEventChannel` lives on the plugin there too. The PDF
reader keeps its separate `pdf-*` channels, which have no Dart consumer.

`reader-status` is the one stream that buffers. A reader view reports its status
from `init`, while the platform view is still being created — that runs before
Flutter replies to Dart, so before a host app can subscribe from
`ReadiumReaderWidget.onReady`. A plain `EventStreamHandler` sends straight into
its sink, which is still nil at that point, so the first status would be dropped
and a host waiting for `ready` would wait forever. `ReaderStatusEventStream`
(`utils/ReaderStatusEventStream.swift`) holds the latest status until a
subscriber attaches, then replays it once. Only the latest is kept: status is a
state, not a log, and nothing may accumulate while no one listens. This mirrors
Android's `events/ReaderStatusEventChannel.kt`.

`text-locator` deliberately does not buffer. A locator is a log, not a state,
and replaying a stale one would move the reader.

**dispose handler** owns all cleanup that needs a live Flutter engine:

| Responsibility | Why in dispose |
|----------------|----------------|
| Send "closed" status event | Needs live Flutter engine |
| Nil channel method call handler | Prevents calls after dispose |
| Remove subview | Idempotent, safe in both |
| Nil delegate | Part of explicit teardown |
| Nil global reference (identity-guarded) | Explicit lifecycle event |

A reader view's dispose does **not** end-stream the shared channels — that is
the plugin's job, and doing it here is the bug described above. The PDF reader
still disposes its own `pdf-*` handlers, since it owns them.

**deinit** retains only `removeFromSuperview()` — it handles the edge case where the native view is deallocated without the Dart `dispose` call being received (engine teardown, hot restart). All property nilling is removed because ARC handles it automatically when the object deallocates. `deinit` must not send messages on Flutter channels, as it may run during engine teardown when channels are already torn down.

### Global Reference Lifecycle

The plugin tracks the active reader view via three module-level globals in `FlureadiumPlugin.swift`:

```swift
internal weak var currentReaderView: ReadiumReaderView?
internal weak var currentPdfReaderView: PdfReaderView?
internal weak var currentImageReaderView: ImageReaderView?
```

All three are `weak var` — they do not own the view. This mirrors Android's `WeakReference<ReadiumReaderWidget>` pattern in `ReadiumReader.kt`. The weak reference prevents a Swift runtime exclusivity violation that would otherwise occur during hot reload: when a new view's `init` assigns itself to the global, ARC releases the old value, triggering the old view's `deinit` — if `deinit` also writes to the same global, Swift detects overlapping exclusive writes and aborts.

Cleanup responsibilities:

| Event | What happens |
|-------|-------------|
| `init` | View assigns itself to the global (`currentReaderView = self`) |
| `"dispose"` method call | Identity-guarded cleanup (`if currentReaderView === self { currentReaderView = nil }`) — prevents clearing a newer view that replaced this one during hot reload |
| `closePublication()` | Nils all three globals before closing the publication — correct teardown order since views reference the publication |
| `deinit` | Does not touch globals — handles only the view's own resource cleanup |

The identity guard in the dispose handler is the same rule Android applies in `ReadiumReaderWidget.dispose()`. Android guards a little more than iOS does: the whole shared teardown sits behind the check, so a stale widget also skips the `"closed"` status and the navigator release, not just the registration clear.

**Files:**
- `EventStreamHandler.swift` - Stream handler with `dispose()` that sends `FlutterEndOfEventStream`
- `FlureadiumPlugin.swift` - Global weak references and `closePublication()` cleanup
- `ReadiumReaderView.swift` - EPUB reader: init assigns global, dispose handler clears it
- `PdfReaderView.swift` - PDF reader: same pattern as EPUB
- `ImageReaderView.swift` - Image/DiViNa reader: same pattern as EPUB

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

iOS provides high-quality voices. To check what the device has installed, without needing TTS enabled:
```dart
final voices = await flureadium.ttsGetSystemVoices();
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
