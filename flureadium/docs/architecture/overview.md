# Architecture Overview

This document describes the high-level architecture of the Flureadium plugin.

## Package Structure

Flureadium is organized as a monorepo with multiple packages:

```
flureadium/
├── flureadium/                    # Main Flutter plugin
│   ├── lib/                       # Dart source code
│   ├── android/                   # Android implementation (Kotlin)
│   ├── ios/                       # iOS implementation (Swift)
│   ├── macos/                     # macOS implementation (Swift)
│   ├── web/                       # Web implementation (TypeScript)
│   └── example/                   # Example Flutter app
│
├── flureadium_platform_interface/ # Platform interface
│   └── lib/                       # Shared types and contracts
│
└── project/                       # Project documentation
```

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Application                       │
├─────────────────────────────────────────────────────────────┤
│                      Flureadium API                          │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │   Flureadium     │  │  ReaderWidget    │                 │
│  │   (singleton)    │  │  (UI component)  │                 │
│  └────────┬─────────┘  └────────┬─────────┘                 │
├───────────┴─────────────────────┴───────────────────────────┤
│                 Platform Interface Layer                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              FlureadiumPlatform                       │   │
│  │  (abstract class defining platform contract)          │   │
│  └────────────────────────┬─────────────────────────────┘   │
├───────────────────────────┴─────────────────────────────────┤
│                   Platform Implementations                   │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────┐ │
│  │  Android   │ │    iOS     │ │   macOS    │ │   Web    │ │
│  │  (Kotlin)  │ │  (Swift)   │ │  (Swift)   │ │   (TS)   │ │
│  └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └────┬─────┘ │
├────────┴──────────────┴──────────────┴─────────────┴────────┤
│                    Readium Toolkits                          │
│  ┌────────────────┐ ┌────────────────┐ ┌──────────────────┐ │
│  │ Kotlin Toolkit │ │ Swift Toolkit  │ │    TS Toolkit    │ │
│  └────────────────┘ └────────────────┘ └──────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Main Package (flureadium/)

### Dart Layer

```
lib/
├── flureadium.dart           # Main singleton API
├── reader_widget.dart        # Native reader widget
├── reader_channel.dart       # Method channel for widget
├── reader_widget_switch.dart # Platform-specific widget selection
├── reader_widget_web.dart    # Web-specific widget
└── src/
    ├── reader/               # Reader lifecycle mixins
    │   ├── orientation_handler_mixin.dart
    │   ├── reader_lifecycle_mixin.dart
    │   ├── toc_skip_navigation_mixin.dart
    │   └── wakelock_manager_mixin.dart
    ├── utils/                # Utilities
    │   ├── navigation_helper.dart
    │   └── toc_matcher.dart
    └── web/                  # Web-specific code
```

### Flureadium Singleton

The main API entry point. Provides:
- Publication lifecycle (open, close)
- Navigation (goLeft, goRight, goToLocator)
- Page and cover thumbnails
- Playback (TTS, audiobook)
- Preferences and decorations

### ReaderWidget

Platform-specific native view wrapper:
- Android: `PlatformViewLink` with `AndroidViewSurface`
- iOS: `UiKitView`
- Web: Custom HTML container

Includes mixins for:
- **WakelockManagerMixin**: Keeps screen on during reading
- **ReaderLifecycleMixin**: Manages widget registration
- **OrientationHandlerMixin**: Handles orientation changes
- **TocSkipNavigationMixin**: Skips to the adjacent chapter

## Platform Interface (flureadium_platform_interface/)

Defines the contract between Dart and native code:

```
lib/
├── flureadium_platform_interface.dart  # Abstract platform class
├── method_channel_flureadium.dart      # Default implementation
└── src/
    ├── exceptions/          # Exception types
    ├── extensions/          # Utility extensions
    ├── reader/              # Reader types
    │   ├── reader_epub_preferences.dart
    │   ├── reader_tts_preferences.dart
    │   ├── reader_audio_preferences.dart
    │   ├── reader_decoration.dart
    │   └── reader_tts_voice.dart
    ├── shared/              # Shared models
    │   ├── publication/     # Publication, Locator, Link, Metadata
    │   └── mediatype.dart
    └── utils/               # Utilities (logging, JSON)
```

### FlureadiumPlatform

Abstract class defining the platform contract:

```dart
abstract class FlureadiumPlatform extends PlatformInterface {
  Future<Publication> openPublication(String pubUrl);
  Future<void> closePublication();
  Future<void> goLeft();
  Future<void> goRight();
  Future<bool> goToLocator(Locator locator);
  Future<Uint8List?> extractPageThumbnail(String href, int maxHeight, int quality);
  // ... more methods
}
```

### MethodChannelFlureadium

Default implementation using Flutter platform channels:
- Method channel for synchronous calls
- Event channels for streaming data

## Native Implementations

### Android (Kotlin)

```
android/src/main/kotlin/dev/mulev/flureadium/
├── FlureadiumPlugin.kt        # Flutter plugin registration
├── ReadiumReaderWidget.kt     # Native reader platform view
├── ReadiumReader.kt           # Reader and navigator orchestration
├── PublicationChannel.kt      # Main method-channel handler
├── PageThumbnailExtractor.kt  # Image-resource thumbnail extraction
├── fragments/                 # EPUB/PDF/image reader fragments
├── navigators/                # EPUB/PDF/image/audio/TTS navigators
└── ...
```

Uses:
- Readium Kotlin Toolkit
- Fragment-based navigation
- Platform views

### iOS (Swift)

```
ios/Sources/flureadium/
├── FlureadiumPlugin.swift     # Flutter plugin registration
├── ReadiumReaderView.swift    # EPUB reader view
├── PdfReaderView.swift        # PDF reader view
├── ImageReaderView.swift      # CBZ / DIVINA reader view
├── AudioReaderView.swift      # Audio-only reader host (no navigator)
├── EpubUserScripts.swift      # WKUserScripts injected into the EPUB WebView
├── EpubNavigatorConfiguration.swift # EPUB navigator configuration builder
├── SpineItemPositionMemory.swift # Scroll-mode position remembered per spine item
├── EpubPageBridge.swift       # The window.epubPage JavaScript API
├── EpubLocatorReporter.swift  # Fragment-resolved locators published to the reader channel
├── EpubReaderCommand.swift    # Reader method-channel calls decoded into typed commands
├── ReaderEdgeNavigationState.swift # Edge tap/swipe config shared by the three visual readers
├── PageThumbnailExtractor.swift # Image-resource thumbnail extraction
└── ...
```

Uses:
- Readium Swift Toolkit 3.5.0
- UIKit views embedded via UiKitView
- GCDWebServer for local content serving

`ReadiumReaderViewFactory` picks the view from the publication: PDF, then image
(DiViNa or an all-bitmap reading order), then audio (an all-audio reading
order), then EPUB. Only the audio host builds no navigator — it has nothing to
render. See [iOS platform notes](../platform-specific/ios.md).

### Web (TypeScript)

```
web/_scripts/
├── ReadiumReader.ts           # Main entry point
├── epubNavigator.ts           # EPUB navigation
├── webpubNavigator.ts         # WebPub navigation
└── preferences.ts             # Preference handling
```

Uses:
- Readium TypeScript Toolkit
- JavaScript interop with Dart
- CSS injection for styling

## Communication Flow

### Method Channels

```
Dart (Flureadium)
    │
    ▼ invokeMethod()
MethodChannel('dev.mulev.flureadium')
    │
    ▼
Native (FlureadiumPlugin)
    │
    ▼
Readium Toolkit
```

### Event Channels

```
Readium Toolkit
    │
    ▼ callback
Native (FlureadiumPlugin)
    │
    ▼ EventChannel
MethodChannel('dev.mulev.flureadium')
    │
    ▼ Stream
Dart (onTextLocatorChanged, etc.)
```

### Widget Channels

```
Dart (ReadiumReaderWidget)
    │
    ▼ invokeMethod()
ReadiumReaderChannel('dev.mulev.flureadium/ReadiumReaderWidget:id')
    │
    ▼
Native (ReadiumReaderView)
    │
    ▼
Readium Navigator
```

## Data Flow

### Opening a Publication

```
1. Flutter calls openPublication(path)
2. MethodChannel sends to native
3. Native uses Readium to parse EPUB
4. Publication manifest returned as JSON
5. Dart parses JSON to Publication object
6. ReaderWidget created with Publication
7. Native view renders content
```

### Position Updates

```
1. User navigates (scroll, tap, etc.)
2. Readium navigator updates position
3. Native sends Locator via EventChannel
4. Dart receives and broadcasts via Stream
5. App saves progress, updates UI
```

## Key Design Decisions

### Singleton Pattern

`Flureadium` uses singleton pattern for:
- Centralized state management
- Consistent API access
- Simplified lifecycle management

### Platform Interface Pattern

Follows Flutter plugin platform interface pattern:
- Abstract class in separate package
- Platform implementations can be swapped
- Testable with mocks

### Navigator Disposal: `release()` vs `dispose()`

Android navigators (`AudiobookNavigator`, `TTSNavigator`, `EpubNavigator`, `PdfNavigator`, `ImageNavigator`) have two disposal methods:

- **`dispose()`** — fire-and-forget. Launches cleanup in a detached coroutine and returns immediately. Safe for places where the caller doesn't need to wait for resources to be freed (e.g., widget teardown where the UI is already gone).

- **`release()`** — awaitable. Suspends until all resources (ExoPlayer sessions, MediaSessions, fragments) are fully released. Callers that need to create a new navigator afterwards *must* use `release()` instead of `dispose()`, otherwise the new navigator may fail to acquire resources still held by the previous one.

`ReadiumReader.closePublication()`, `audioEnable()`, and `stop()` all use `release()` to prevent race conditions between test runs and publication switches on emulators with limited audio HAL resources.

What `release()` does not buy you is a quiet container. It waits for our navigators, and
`ImageNavigator.release()` removes the fragment, but removing a fragment only *cancels* readium's
page fragment, and cancellation is cooperative. A read already suspended inside
`withContext(Dispatchers.IO)` runs to completion against a `ZipFile` that `closePublication()`
has since closed. Reading this paragraph as "the close is awaited, therefore nothing is still
reading" is what made that crash hard to find. The container boundary carries its own guard for
this (`Resource.catchingClosedContainer()` in `ReadiumExtensions.kt`); see the "zip file closed"
entry in [Troubleshooting](../troubleshooting.md).

### iOS Publication Cleanup: `await MainActor.run` vs fire-and-forget `Task`

iOS method channel handlers run on a background thread. Publication cleanup (nullifying navigators, closing the publication) must happen on `@MainActor` because UIKit state is involved. Two patterns exist:

- **`Task { @MainActor in ... }`** — fire-and-forget. Creates an unstructured task; the caller returns immediately. Safe only when the caller doesn't need cleanup to finish first (e.g., `pause`, `resume`).

- **`await MainActor.run { ... }`** — awaitable. Suspends the calling task until the block completes on the main actor. Required whenever the caller proceeds to use or replace the publication state (e.g., `closePublication`, `stop`, `dispose`, and the internal close-before-open in `openPublication`).

This mirrors the Android pattern where `closePublication()` uses `mainScope.async { ... }.await()` instead of `launch { ... }`.

### Car bridge (CarPlay / Android Auto)

How the native car surfaces (CarPlay scene, Android `MediaLibraryService`) obtain host library data that lives only in Dart, with no Flutter UI alive, is decided in [car-bridge-decision.md](car-bridge-decision.md): an app-scoped headless `FlutterEngine` + `MethodChannel` (variant a). The host registers a `CarContentProvider` (see [car content](../api-reference/car-content.md)) that answers browse, search, and play requests over that channel.

### Readium Integration

Wraps Readium toolkits rather than reimplementing:
- Leverages proven EPUB rendering
- Access to advanced features (TTS, audio)
- Cross-platform consistency

### JSON Serialization

All models serialize to/from JSON:
- Platform communication
- Persistence
- Debugging

## See Also

- [Platform-Specific Docs](../platform-specific/) - Platform implementation details
