# Flureadium

A cross-platform Flutter plugin for reading ebooks, audiobooks, and comics, built on top of the [Readium](https://readium.org/) toolkits.

Flureadium wraps **Readium Kotlin Toolkit 3.1.2** (Android), **Readium Swift Toolkit 3.5.0** (iOS/macOS), and the **Readium TypeScript Toolkit** (Web) behind a unified Dart API using Flutter's federated plugin architecture.

This project is a fork of [Notalib/flutter_readium](https://github.com/Notalib/flutter_readium), modernized with Readium 3.x support, Dart 3.8+ null safety, the Preferences API, and the Decorator API.

## Key Features

- **EPUB 2 & 3 reading** — paginated and scrolling modes with customizable typography
- **WebPub support** — web publication format alongside EPUB
- **PDF support** — native rendering on Android (Pdfium) and iOS
- **CBZ and DIVINA support** — native image-based publication rendering on Android and iOS
- **Text-to-Speech** — platform-native TTS with voice selection, speed, and pitch control
- **Audiobook playback** — pre-recorded audio with track navigation, seeking, and variable speed
- **Media Overlays** — synchronized audio with text highlighting (read-along)
- **Highlights and annotations** — visual decorations with custom colors and styles
- **Reader preferences** — fonts, font sizes, colors, margins, themes (night/sepia), scroll modes
- **Progress saving** — position persistence and restoration via Locators
- **Page thumbnails** — downscaled JPEG thumbnails for image resources in open publications
- **Table of contents** — hierarchical navigation through publication structure
- **Real-time event streams** — position changes, playback state, reader status, and errors

## Supported Formats

| Format | Visual Reading | TTS | Audio | Media Overlays |
|--------|----------------|-----|-------|----------------|
| EPUB 2 | Yes | Yes | — | Yes |
| EPUB 3 | Yes | Yes | Yes | Yes |
| WebPub | Yes | Yes | Yes | Yes |
| PDF | Android, iOS | — | — | — |
| CBZ | Android, iOS | — | — | — |
| DIVINA | Android, iOS | — | — | — |

## Minimum Requirements

| Requirement | Version |
|-------------|---------|
| Flutter | 3.3.0+ |
| Dart SDK | 3.8.0+ |
| Android | minSdkVersion 24 |
| iOS | 13.0+ |
| macOS | 10.15+ |

## Getting Started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flureadium: ^0.16.2
```

Then follow the platform-specific setup below. For full details, see the [Installation Guide](flureadium/docs/getting-started/installation.md).

### Android

- Set `minSdkVersion` to 24 or higher in `android/app/build.gradle`.
- Change your main activity to extend `FlutterFragmentActivity` instead of `FlutterActivity`.
- If using TTS or audiobook background playback, add to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

### iOS

Add the Readium pods to your `ios/Podfile`:

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!
  pod 'PromiseKit', '~> 8.1'

  pod 'ReadiumShared', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumShared.podspec'
  pod 'ReadiumInternal', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumInternal.podspec'
  pod 'ReadiumStreamer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumStreamer.podspec'
  pod 'ReadiumNavigator', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumNavigator.podspec'
  pod 'ReadiumOPDS', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumOPDS.podspec'
  pod 'ReadiumAdapterGCDWebServer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.5.0/Support/CocoaPods/ReadiumAdapterGCDWebServer.podspec'
  pod 'ReadiumZIPFoundation', podspec: 'https://raw.githubusercontent.com/readium/podspecs/refs/heads/main/ReadiumZIPFoundation/3.0.1/ReadiumZIPFoundation.podspec'

  # ...
end
```

Allow the local content server in `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true />
</dict>
```

### Web

1. Copy the plugin's JavaScript file to your web directory:

```bash
dart run flureadium:copy_js_file <destination_directory>
```

2. Add the script to your `index.html`:

```html
<script src="flutter.js" defer></script>
<script src="readiumReader.js" defer></script>
```

For Web preferences documentation, see the [Readium CSS docs](https://github.com/readium/css?tab=readme-ov-file#docs) and the [TypeScript Toolkit preferences types](https://github.com/readium/ts-toolkit/blob/develop/navigator/src/preferences/Types.ts).

## Documentation

Full documentation is available in the [docs](flureadium/docs/) folder.

| Section | Description |
|---------|-------------|
| [Getting Started](flureadium/docs/getting-started/) | Installation, quick start, and core concepts |
| [EPUB Reading](flureadium/docs/guides/epub-reading.md) | Visual EPUB navigation and customization |
| [Text-to-Speech](flureadium/docs/guides/text-to-speech.md) | TTS integration and voice selection |
| [Audiobook Playback](flureadium/docs/guides/audiobook-playback.md) | Playing pre-recorded audio |
| [Highlights & Annotations](flureadium/docs/guides/highlights-annotations.md) | Adding visual decorations |
| [Saving Progress](flureadium/docs/guides/saving-progress.md) | Persisting reading position |
| [Preferences](flureadium/docs/guides/preferences.md) | Customizing reader appearance |
| [Error Handling](flureadium/docs/guides/error-handling.md) | Exception types and best practices |
| [API Reference](flureadium/docs/api-reference/) | Flureadium class, ReaderWidget, models |
| [Architecture](flureadium/docs/architecture/overview.md) | High-level design and platform channels |
| [Troubleshooting](flureadium/docs/troubleshooting.md) | Common issues and solutions |

## Feature Parity Analysis

### Flureadium Platform Support

What Flureadium supports on each platform:

| Feature | Android | iOS | macOS | Web |
|---------|---------|-----|-------|-----|
| EPUB Visual Reading | Yes | Yes | Yes | Yes |
| PDF | Yes | Yes | Yes | No |
| CBZ / DIVINA | Yes | Yes | No | No |
| Page Thumbnails | Yes | Yes | No | No |
| Text-to-Speech | Yes | Yes | Yes | Limited&sup1; |
| Audiobook Playback | Yes | Yes | Yes | Partial&sup2; |
| Media Overlays | Yes | Yes | Yes | No |
| Highlights & Annotations | Yes | Yes | Yes | Yes |
| Reader Preferences | Yes | Yes | Yes | Yes |
| Progress Saving | Yes | Yes | Yes | Yes |
| Background Audio | Yes | Yes | Yes | No |

&sup1; Web TTS uses the browser's Web Speech API — voice availability and quality vary by browser.
&sup2; Web audio uses HTML5 `<audio>` — no background playback or lock screen controls.

### Readium Native Toolkit Capabilities

What each Readium toolkit supports natively, independent of Flureadium:

| Feature | Kotlin 3.1.2 (Android) | Swift 3.5.0 (iOS/macOS) | TypeScript (Web) |
|---------|------------------------|--------------------------|------------------|
| EPUB 2 & 3 | Yes | Yes | Yes |
| PDF | Yes (Pdfium adapter) | Yes | No |
| Audiobooks | Yes | Yes | Partial |
| CBZ Comics | Yes | Yes | No |
| Divina (Visual Narratives) | Yes | Yes | No |
| LCP DRM | Yes | Yes | No |
| OPDS Catalogs (1.x & 2.0) | Yes | Yes | Partial |
| Search in Content | Yes | Yes | Limited |
| Text-to-Speech | Yes | Yes | Limited |
| Media Overlays | Yes | Yes | No |
| Fixed Layout EPUB | Yes | Yes | Yes |
| RTL Language Support | Yes | Yes | Yes |
| Annotations | Yes | Yes | Yes |

### Readium Features Not Yet Exposed in Flureadium

Native Readium features that exist in the underlying toolkits but are not yet surfaced through Flureadium's API:

| Readium Feature | Available In | Flureadium Status |
|-----------------|--------------|-------------------|
| LCP DRM | Kotlin, Swift | Not integrated (infrastructure exists, can be enabled) |
| OPDS Catalog Browsing | Kotlin, Swift | Not exposed in API |
| Content Search | Kotlin, Swift | Not exposed in API |

## Architecture

Flureadium follows Flutter's federated plugin pattern:

```
Flutter Application
    |
Flureadium API (singleton + ReaderWidget)
    |
Platform Interface (FlureadiumPlatform abstract class)
    |
Platform Implementations
    |-- Android: Kotlin + Readium Kotlin Toolkit 3.1.2
    |-- iOS:     Swift + Readium Swift Toolkit 3.5.0
    |-- macOS:   Swift + Readium Swift Toolkit 3.5.0
    |-- Web:     TypeScript + Readium TypeScript Toolkit
```

| Component | Readium Version |
|-----------|----------------|
| Android | Readium Kotlin Toolkit 3.1.2 (Maven Central) |
| iOS / macOS | Readium Swift Toolkit 3.5.0 (CocoaPods) |
| Web | Readium TypeScript Toolkit (npm) |

For more details, see the [Architecture Overview](flureadium/docs/architecture/overview.md).
