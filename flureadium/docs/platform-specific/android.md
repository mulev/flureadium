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

### Decoration Payload Decoding

`applyDecorations` receives each decoration as a map of three keys: `id`, `locator`, and `style`. `locator` is the map `Locator.toJson()` produces, not a JSON string, and `style` is a nested `{style, tint}` map whose `tint` is a CSS hex colour (`#RRGGBB` or `#AARRGGBB`). `decorationFromMap` in `ReadiumExtensions.kt` reads those keys and builds the Readium `Decoration`. The locator goes through `JSONObject(Map)`, which wraps nested maps recursively, so `locations` and `text` survive the conversion and the decoration lands on the selected range instead of the top of the resource.

A decoration the decoder cannot read fails the whole `applyDecorations` call. It raises `IllegalArgumentException` naming the decoration, the method-channel handler catches it and answers `result.error`, and Dart receives a `PlatformException` whose message identifies the payload. Earlier versions logged the failure and dropped that decoration from the list, so a mismatched payload looked like a silent no-op.

An unrecognised `style` string is not a failure. `decorationStyleFromMap` maps `underline` to an underline and anything else to a highlight, so a style name Android does not know draws a highlight instead of rejecting the call.

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
- `PluginMediaService.kt` — hosts the persistent, browse-capable `MediaLibrarySession`
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
    ├── EpubNavigator.kt             # EPUB navigation controller
    ├── EpubNavigatorState.kt        # Saved-state bundle codec
    ├── EpubPageScript.kt            # window.epubPage JavaScript contract
    ├── EpubScrollRestore.kt         # Deferred restore scroll and its decision
    ├── ImageNavigator.kt            # CBZ / DIVINA navigation controller
    ├── NavigatorTapForwarder.kt     # Readium InputListener → logical-pixel taps
    ├── PdfNavigator.kt              # PDF navigation controller
    └── VisualLocatorSubscription.kt # Throttled locator reporting for all three
```

### Plugin Lifecycle

The plugin attaches twice, and each attachment owns different state.

`onAttachedToEngine` seeds `ReadiumReader`'s `Application` reference from the
plugin binding's application context. That context exists even when no Activity
does, so an engine running without a UI (the car engine behind Android Auto, a
background isolate) can still make application-only calls such as the TTS
system-voice query or navigator construction. The reference is process-scoped
and never cleared, because `Application` outlives every engine. A host can run a
UI engine and a car engine at once, and both keep resolving it after either one
detaches. The rest of `ReadiumReader`'s state is not engine-safe: `detach()`
runs on both Activity and engine detach, and it clears everything else,
including the channels below.

`onAttachedToActivity` handles the parts that need an Activity: the reader
widget, saved-state restore, and the event channels below. A headless engine
skips all of it.

### Event Channels

All four Flutter EventChannels are registered in `ReadiumReader.attach()`, which
runs at Activity attach. So registration is Activity-scoped: an engine with no
Activity gets the application context it needs for method calls, but no reader
state events.

| Channel | Kotlin class | Events |
|---|---|---|
| `dev.mulev.flureadium/reader-status` | `ReaderStatusEventChannel` | `"loading"`, `"ready"`, `"closed"` |
| `dev.mulev.flureadium/error` | `ErrorEventChannel` | `{ message, code, data }` maps |
| `dev.mulev.flureadium/text-locator` | `TextLocatorEventChannel` | Locator JSON strings |
| `dev.mulev.flureadium/timebased-state` | `TimedBasedStateEventChannel` | Playback state maps |

Reader status lifecycle:
- `"loading"` — emitted from `ReadiumReaderWidget.init` when the native view is created
- `"ready"` — emitted from `onVisualReaderIsReady()` when Readium signals the reader is ready, or directly from `ReadiumReaderWidget.init` for an audio-only publication, which has no visual navigator to signal it
- `"closed"` — emitted from `ReadiumReaderWidget.dispose()`, by the widget that still owns the registration, before it tears down the navigator

`ReadiumReaderWidget.init` runs inside the platform-view `create` call, which
finishes before Flutter replies to Dart — so `"loading"`, and the `"ready"` an
audio-only host sends from the same place, are emitted before a host app can
subscribe from `onReady`. `ReaderStatusEventChannel` holds the most recent
status while no one is listening and delivers it once, when the first
subscriber arrives. Only the latest one is held: reader status is a state, not
a log, and a status already delivered is never replayed to a later subscriber.

What a channel holds while nobody is listening differs per channel, because the
events differ. `ReaderStatusEventChannel` keeps the latest status and nothing
else: status is a state, so an older one is stale the moment a newer arrives.
`ErrorEventChannel` keeps up to eight errors in order: an error is an event, one
does not supersede another, and the first failure is usually the one that
explains the rest — hence the oldest are the ones kept when the cap is reached.
`TextLocatorEventChannel` keeps nothing at all: a locator is a page turn that
already happened, and handing it to a later subscriber would move a reader that
never went there. All three are recreated by `ReadiumReader.attach()`, and
disposing one clears whatever it was holding, so nothing survives into the next
Activity attach.

### Coroutine Failure Reporting

Every coroutine scope in the plugin either reports its failures or says in a
`// no-handler:` comment why it does not need to, and
`CoroutineScopeHandlerConventionTest` fails the build when a new scope does
neither. Four scopes report through `readerCoroutineExceptionHandler`:
`ReadiumReaderWidget.mainScope`, `ReadiumReader.mainScope`,
`BaseNavigator.mainScope` (which every navigator inherits), and the
`PluginLibrarySessionCallback` scope that runs the notification and car
transport commands.

They need it because of how a supervisor works. Each scope is built on a
`SupervisorJob`, and a supervisor's direct children are root coroutines, so a
failure is never passed up to a parent. `handleCoroutineException` looks for a
`CoroutineExceptionHandler` in the coroutine's context and, finding none, falls
through to the thread's uncaught handler — `RuntimeInit.KillApplicationHandler`
on Android, which kills the process. A failed navigator enable used to take the
whole app down that way, with nothing reaching Dart.

The handler logs the throwable, sets reader status to `error`, and sends an
error event carrying the exception message, `code: "ReaderFailure"`, and the
stack trace as `data`. The widget passes its own ownership check to the handler:
Flutter builds a replacement platform view before unmounting the one it
replaces, so a stale widget's enable can still be in flight while a newer widget
owns the reader, and its failure must not describe a session the host has
already dropped.

Three deliberate exclusions:

- `EventChannelWrapper.mainScope` logs its failures and reports nothing, through
  `channelCoroutineExceptionHandler`. It owns the channels a report travels on,
  so a channel that reported its own failure would send again, fail again, and
  never stop; the send is dispatched rather than nested, so that loop spins
  forever instead of overflowing the stack. The process survives, and the
  throwable is in logcat.
- `PublicationMethodCallHandler.onMethodCall` needs no handler. Its coroutine
  body is one `dispatchGuarded` call, which catches every exception and answers
  the call with `result.error`.
- Cancellation reports nothing. A coroutine cancelled by widget `dispose()` or
  engine `detach()` completes with a `CancellationException`, which coroutines
  never hand to a handler, so teardown stays silent by construction.

A failed reader method call is answered rather than reported: `onMethodCall`
catches the exception and replies `result.error` with the exception class,
message and stack trace, the same shape `PublicationChannel.dispatchGuarded`
returns. `CancellationException` is rethrown there too, so a call torn down by
`dispose()` does not reach Dart as a phantom failure.

### Reader Kind

`PublicationReaderKind` decides which reader can host an open publication, and
`ReadiumReaderWidget` freezes that decision when the platform view is created.
Classification comes from Readium's own profile checks, in this order:

| Kind | Matched when | What the widget mounts |
|---|---|---|
| `PDF` | `conformsTo(Profile.PDF)` | Pdfium navigator |
| `IMAGE` | `conformsTo(Profile.DIVINA)`, or every reading-order item is a bitmap | Image navigator |
| `AUDIO` | `conformsTo(Profile.AUDIOBOOK)` | Nothing — no visual navigator exists for audio |
| `EPUB` | Everything else | EPUB navigator |

`EPUB` is the fallback, so anything with an HTML reading order lands there —
including a media-overlay ("karaoke") book, whose reading order is HTML rather
than audio. Those keep their EPUB navigator and their existing audio path.

An `AUDIO` host is a live but empty platform view: it registers itself, emits
`"ready"` straight from `init`, and enables no navigator. The visual reader
operations still answer, with their inert defaults — `isLocatorVisible` returns
`false`, `isReaderReady` returns `true`, `getLocatorFragments` echoes the
locator it was given, and preference or navigation calls are no-ops. Playback
itself runs through the audio navigator and the media session, not the widget.

### Platform View

Uses `PlatformViewLink` with `AndroidViewSurface` for high-performance rendering:

```kotlin
internal class ReadiumReaderViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val creationParams = args as Map<String?, Any?>
        return ReadiumReaderWidget(context!!, viewId, creationParams, messenger)
    }
}
```

#### Teardown ownership

Flutter builds the replacement platform view before it disposes the one being
replaced: the new element's `initState` runs during `buildScope`, and the old
element is unmounted later, in `finalizeTree()`. Native therefore sees
**create new, then dispose old** — so a stale widget's `dispose()` routinely
arrives after a newer widget has already written itself to
`ReadiumReader.currentReaderWidget`.

`dispose()` guards every shared mutation on `ReadiumReader.currentReaderWidget
=== this`. Only the widget that still owns the registration emits `"closed"`,
clears the registration, and closes the navigator. A stale widget skips all
three, so it cannot sever the live widget's callbacks.

`epubClose()`, `imageClose()` and `pdfClose()` are publication-scoped: they
release the navigator and the is-ready channel the matching `*Enable` created,
and never touch the registration. `AUDIO` enables neither, so clearing the
registration is its entire shared teardown.

What a widget owns per instance — its method-call handler, its coroutine scope,
its view group — is released unconditionally, guard or no guard.

The flip side is that engine teardown can no longer lean on a widget dispose.
`ReadiumReader.detach()` clears `readerViewRef` itself, so any dispose that
arrives afterwards fails the identity check and releases nothing shared. It
therefore calls `epubClose()`, `imageClose()` and `pdfClose()` up front, on the
synchronous path. The `closePublication()` it launches is not a substitute for
that: a navigator's `release()` removes its fragment inside
`withContext(Dispatchers.Main)`, which resumes a looper turn later, against a
`FragmentManager` whose Activity is already going away. A navigator left behind
would outlive the engine, because `ReadiumReader` is process-scoped — and the
next engine's `*Enable` would attach to the dead one instead of building a
fresh navigator.

`detach()` cancels its own coroutines before any of that runs: `jobs` and
`mainScope`'s children first, teardown second. The order matters because the
publication close is launched on `mainScope`. A cancel placed after that launch
would be the function cancelling its own teardown.

In the old order it never actually cancelled anything.
`EpubNavigator.release()`, `ImageNavigator.release()` and
`PdfNavigator.release()` all suspend on a plain `withContext(Dispatchers.Main)`,
so `closePublication()` does have suspension points. The three closes above
take them out of play: they null those navigators before the launch, leaving
the three time-based ones — `ttsNavigator`, `audiobookNavigator` and
`syncAudiobookNavigator`. Those resolve to two `release()` bodies, since
`SyncAudiobookNavigator` extends `AudiobookNavigator` and does not override it,
and both switch with `withContext(Dispatchers.Main.immediate)`, which does not
dispatch when it is already on the main thread. `closeSession()` is not a
suspending call either; it launches onto the facade's queue and returns. On the
platform thread the whole close therefore completed inline, before the cancel
that used to sit at the bottom of `detach()` was reached.

That is a thin thing to rely on. It holds only while every `release()` left on
the path keeps not suspending, and while the three closes keep running first.
Cancelling up front removes the dependency: `cancelChildren()` cancels the
children the scope has and leaves its `SupervisorJob` active, so anything
launched afterwards still runs.

### Readium Integration

Uses Readium Kotlin Toolkit:
- `Streamer` for EPUB parsing
- `Navigator` for EPUB, PDF, and image-based content display; an audiobook gets no visual navigator
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

### Session Lifecycle: one session for browse and playback

`PluginMediaService` owns a single, persistent `MediaLibrarySession` for the
life of the service. It is built in `onCreate` with an idle placeholder player
(`IdleBrowsePlayer`) and the shared `libraryCallback`, so `onGetSession` returns
a browse-capable session even before anything plays. Android Auto can connect
and browse the host library from a cold, UI-less process; the idle player
reports `STATE_IDLE` with no media, so the head unit shows no phantom "now
playing". The placeholder advertises just the set/change media items, prepare,
and play commands a head-unit row tap needs to reach `onSetMediaItems`; it starts no
playback itself, because real playback is driven by `source.play` and the player
swap below.

`play(locator)` (a table-of-contents chapter tap or a bookmark resume) routes
through `Binder.openSession`, which decides what to do from the navigator
already backing the live session (`sessionActionFor`):

- **Same navigator**: reuse the session and seek; do not swap the player.
- **Different navigator**: swap in the new navigator's player (an audiobook to TTS switch, or the reverse).
- **None open**: swap the idle placeholder for the navigator's player.

Instead of building a new session per playback, `openSession` sets the
navigator-backed player on the one persistent session, and `closeSession` sets
the idle placeholder back so the browse surface survives playback teardown. The
session is released only when the service is destroyed.

media3 requires every live `MediaSession` to have a unique id, and the default
id is the empty string. An earlier version rebuilt the session on every
`play(locator)`, so a chapter jump created a second session with the same empty
id while the first was still live; media3 threw `Session ID must be unique` and
the error handler tore down the only player, freezing playback at the new
chapter's `0:00`. One persistent session removes the collision by construction.
`PluginMediaServiceFacade` mirrors the same-navigator check at the bind layer, so
a repeat `play(locator)` does not leak a session collector. Covered by
`PluginMediaServiceLibraryTest` (browse session before playback),
`IdleBrowsePlayerTest` (idle placeholder), `PluginMediaServiceReuseTest`, and the
`play(locator) to a later chapter while playing keeps playback going`
integration test.

**Files:**
- `PluginMediaService.kt` — persistent session, `onGetSession`, `Binder.openSession`/`closeSession` player swap, `sessionActionFor`
- `IdleBrowsePlayer.kt` — idle placeholder player backing the browse-only session
- `PluginMediaServiceFacade.kt` — same-navigator short-circuit before rebinding

### Android Auto refresh on library change

The browse tree is pull-based: Android Auto reads it through `onGetChildren`, so a
live browse never learns the host library changed on its own. `refreshCarContent`
is the one outbound nudge that closes that gap.

Dart `Flureadium.refreshCarContent()` invokes the `/main` method channel; the
`refreshCarContent` case in `PublicationMethodCallHandler` reaches the running
service through `PluginMediaService.instance` (a process-scoped handle set in
`onCreate` and cleared on destroy, the same app-scoped static seam the car engine
uses for its source) and calls `refreshBrowse()`.

`refreshBrowse()` posts onto the main looper (the route arrives on a background
dispatcher, while the method-channel `CarContentSource` and the `MediaLibrarySession`
must be touched on the application thread), then calls
`PluginLibrarySessionCallback.notifySubscribedParents`. The callback tracks every
`(controller, parentId, params)` subscription (`onSubscribe`/`onUnsubscribe`, plus
`onDisconnected` so a controller that drops without unsubscribing is not left
behind) and re-notifies each one with the per-controller
`notifyChildrenChanged(controller, parentId, count, params)` overload, so a browser
keeps its own `LibraryParams`. The count comes from `onGetChildren` itself, so it
matches what a re-query returns: the empty-state status row is counted, and `siri`
markers (which have no Android Auto row) are not. Android Auto then re-queries only
the parents it is actually browsing and repaints them.

The refresh is safe to fire at any time: a nudge queued just as the service is
destroyed is dropped by an instance-identity check, and a nudge with no car surface
connected notifies no one.

**Files:**
- `PublicationChannel.kt` — the `/main` `refreshCarContent` route to `PluginMediaService.instance?.refreshBrowse()`
- `PluginMediaService.kt` — `refreshBrowse()` (main-looper post) and the `instance` handle
- `PluginLibrarySessionCallback.kt` — subscription tracking and `notifySubscribedParents`


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

### Content Taps

`ReadiumReaderWidget.onTap` fires for a tap on content, meaning a tap nothing else
claimed. The plugin does not detect those taps itself. It registers an
`InputListener` on the Readium navigator and lets the toolkit decide what counts
as a content tap before the plugin hears about it.

`NavigatorTapForwarder` (`navigators/NavigatorTapForwarder.kt`) is that listener.
Each visual navigator owns one and binds it to the Readium navigator it currently
hosts: `EpubNavigator` and `PdfNavigator` bind in `onPageLoaded`, `ImageNavigator`
in `setupNavigatorListeners`, above the guard that returns early while a CBZ still
has no locator. All three unbind in `dispose` and in `release`, the teardown a
publication swap takes.

The forwarder is not the only collaborator `setupNavigatorListeners` reaches for.
`VisualLocatorSubscription` (`navigators/VisualLocatorSubscription.kt`) holds the
throttled locator reporting all three navigators used to carry a copy of, and each
navigator keeps the `Job` it returns in the list `dispose` cancels. The two are
independent, which is what lets `ImageNavigator` bind its taps and then return
early with no subscription at all: the forwarder follows the Readium navigator
instance, the subscription follows that navigator's locator flow.

**Binding is keyed on the navigator instance.** `EpubReaderFragment` and
`PdfReaderFragment` remove their Readium navigator in `onPause` and build a new one
in `onResume`, while `hasNotifiedIsReady` stops `setupNavigatorListeners` from
running a second time. Registering again on the same navigator would report every
tap twice, and skipping a recreated one would report no taps at all. Neither is
visible in a host that toggles chrome on the callback, so the forwarder compares
identity and moves its registration to whichever navigator is live.

**Coordinates cross the channel in logical pixels.** `TapEvent.point` is a `PointF`
in navigator-view pixels, so the forwarder divides by
`publicationView.resources.displayMetrics.density` before sending
`{"x": …, "y": …}`. iOS already reports points, so Dart gets one unit system from
both platforms.

**EPUB filters link taps for you.** `InputListener.onTap` is documented as "the user
tapped the content, but nothing handled the event internally (eg. by following an
internal link)". A tap on a hyperlink or a footnote navigates and reports no tap, so
a host can toggle its chrome on every `onTap`.

**PDF and CBZ have nothing to filter.** The pdfium adapter forwards the tap point and
follows no link, so a tap on a PDF link annotation is reported as a content tap and
navigates nowhere. iOS behaves differently here: PDFKit follows the annotation and
reports the tap as well. See [iOS](ios.md#content-taps).

**A tap arriving after the view is gone is dropped.** `publicationView` is
`requireView()` on every Readium navigator fragment, and an EPUB tap reaches the
forwarder from the WebView's JavaScript bridge after a hop to the main thread. If
`onPause` destroyed the view in between, the forwarder returns without reporting
rather than letting the read throw into the bridge.

`NavigatorTapForwarder.onTap` returns `false`, so it never consumes the event.
`CompositeInputListener.onTap` is `listeners.any { it.onTap(event) }`, which
short-circuits: returning `true` would starve every listener Readium registered
behind the forwarder. Edge taps have a separate owner, the overlay below, which
claims them before Readium sees them. See
[Edge Tap and Swipe Navigation](#edge-tap-and-swipe-navigation).

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
