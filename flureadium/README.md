# Flureadium

A comprehensive Flutter plugin for reading EPUB ebooks, audiobooks, and comics using the [Readium](https://readium.org/) toolkits.

[![pub package](https://img.shields.io/pub/v/flureadium.svg)](https://pub.dev/packages/flureadium)
[![CI](https://github.com/mulev/flureadium/actions/workflows/test.yml/badge.svg)](https://github.com/mulev/flureadium/actions)

## Features

- **EPUB Reading**: Full EPUB 2/3 support with customizable typography
- **PDF Reading**: PDF support via Readium's PDF adapters (Android via Pdfium, iOS via PDFKit)
- **CBZ and DIVINA Reading**: Image-based comics and visual narratives on Android and iOS
- **Audiobook Playback**: Native audio with background playback support
- **Text-to-Speech**: Platform TTS with voice selection, rate control, availability detection, and position restore
- **Synchronized Audio**: Media overlay support for read-along experiences
- **Highlighting**: Decoration API for bookmarks, highlights, and annotations
- **Page Thumbnails**: Downscaled JPEG thumbnails for image resources in the open publication
- **Cross-Platform**: Android, iOS, macOS, and Web (web support is work in progress — see [Web Platform](docs/platform-specific/web.md))

## Quick Start

### Installation

```yaml
dependencies:
  flureadium: ^0.16.3
```

> Developed and tested with **Flutter 3.44.7 (Dart 3.12.2)**. The `pubspec.yaml` constraints (`sdk: >=3.8.0 <4.0.0`, `flutter: >=3.3.0`) remain the source of truth for supported versions.

### Platform Setup

<details>
<summary>Android</summary>

1. Set minimum SDK version in `android/app/build.gradle`:
```groovy
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

2. Change `MainActivity` to extend `FlutterFragmentActivity`:
```kotlin
class MainActivity: FlutterFragmentActivity()
```

3. If using TTS with `AudioService`, add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

</details>

<details>
<summary>iOS</summary>

1. Add Readium pods to `ios/Podfile`:
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

  # ... rest of your Podfile
end
```

2. Add to `ios/Runner/Info.plist` to allow local server:
```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true />
</dict>
```

</details>

<details>
<summary>Web</summary>

1. Copy JavaScript file:
```bash
dart run flureadium:copy_js_file web/
```

2. Add to `index.html`:
```html
<script src="flutter.js" defer></script>
<script src="readiumReader.js" defer></script>
```

</details>

### Basic Usage

```dart
import 'package:flureadium/flureadium.dart';

// Get the singleton instance
final flureadium = Flureadium();

// Open a publication
final publication = await flureadium.openPublication('file:///path/to/book.epub');

// Display in your widget tree
ReadiumReaderWidget(
  publication: publication,
  onReady: () {
    // Native reader is ready
  },
)

// Navigate
await flureadium.goRight();
await flureadium.goToLocator(savedPosition);

// Extract a small thumbnail for an image resource in an open CBZ/DIVINA
final bytes = await flureadium.extractPageThumbnail('001.jpg', 80, 70);

// Listen for position changes
flureadium.onTextLocatorChanged.listen((locator) {
  saveReadingPosition(locator);
});
```

## Documentation

- **[Full Documentation](docs/)** - Comprehensive guides and API reference
- [API Reference](https://pub.dev/documentation/flureadium/latest/) - Generated dartdoc
- [Example App](https://github.com/mulev/flureadium/tree/main/flureadium/example)

## Supported Formats

| Format | Visual | TTS | Audio | Sync |
|--------|--------|-----|-------|------|
| EPUB 2 | Yes | Yes | - | Yes |
| EPUB 3 | Yes | Yes | Yes | Yes |
| WebPub | Yes | Yes | Yes | Yes |
| PDF | Android, iOS | - | - | - |
| CBZ | Android, iOS | - | - | - |
| DIVINA | Android, iOS | - | - | - |

PDF support is available on Android (via Pdfium) and iOS (via PDFKit). Image-based
publications use Readium's native image navigators on both platforms. See
[documentation](docs/) for details.

## Web Development

When making changes to the TypeScript files, rebuild the JavaScript:

```bash
npm run build
```

Run this from the root of the plugin directory.

## Contributing

Contributions are welcome! Please read our [Contributing Guide](https://github.com/mulev/flureadium/blob/main/CONTRIBUTING.md).

## License

This project is licensed under the LGPL v3 -- see [LICENSE](LICENSE) for details.

This project is a fork of [Notalib/flutter_readium](https://github.com/Notalib/flutter_readium).

## Acknowledgments

Built on the excellent [Readium](https://readium.org/) project.
