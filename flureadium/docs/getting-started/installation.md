# Installation

This guide covers setting up Flureadium in your Flutter project for all supported platforms.

## Prerequisites

- Flutter 3.3.0 or higher
- Dart SDK 3.8.0 or higher

> **Contributor note:** this release is developed and tested with Flutter 3.44.7 (Dart 3.12.2). The package `pubspec.yaml` constraints above remain the source of truth for supported versions. Contributors may pin the toolchain locally with [fvm](https://fvm.app) (`fvm use 3.44.7`); the fvm files (`.fvmrc`, `.fvm/`) are gitignored and not required to build.
>
> CI is pinned to the same version — `flutter-version: '3.44.7'` on every `subosito/flutter-action` step in `.github/workflows/`. It used to track `channel: stable` with no version, which meant a Flutter release could turn every required check red on a branch that had not changed, and did: Dart 3.13 reserves `final` on normal parameters for primary constructors, and `flutter drive -d chrome` hangs on 3.47.1 (`flureadium-itgt`). Moving the toolchain is now a reviewed commit that edits those 14 lines, not a surprise.

## Add Dependency

Add Flureadium to your `pubspec.yaml`:

```yaml
dependencies:
  flureadium: ^0.17.1
```

Run:

```bash
flutter pub get
```

## Platform-Specific Setup

### Android

#### 1. Add JitPack Repository

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

#### 2. Set Minimum SDK Version

In `android/app/build.gradle`, set:

```groovy
android {
    defaultConfig {
        minSdkVersion 24  // Required for Readium
    }
}
```

#### 3. Use FlutterFragmentActivity

If your `MainActivity` extends `FlutterActivity`, change it to extend `FlutterFragmentActivity`:

```kotlin
// android/app/src/main/kotlin/.../MainActivity.kt
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {
}
```

This fixes the error: `MainActivity cannot be cast to androidx.fragment.app.FragmentActivity`

#### 4. Add Playback Permissions (Optional)

If using TTS or audiobook features, add to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest>
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <!-- ... -->
</manifest>
```

### iOS

#### 1. Configure Podfile

Add the Readium pods to your `ios/Podfile`:

```ruby
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
cd ios && pod install
```

#### 2. Configure App Transport Security

Add to `ios/Runner/Info.plist` to allow the local content server:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true />
</dict>
```

### macOS

#### 1. Configure Podfile

Similar to iOS, add the Readium pods to `macos/Podfile`:

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!

  pod 'PromiseKit', '~> 8.1'
  # ... same Readium pods as iOS

  flutter_install_all_macos_pods File.dirname(File.realpath(__FILE__))
end
```

#### 2. Entitlements

If your app is sandboxed, ensure network access is enabled in `macos/Runner/DebugProfile.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

### Web

#### 1. Copy JavaScript File

Run this command from your project root:

```bash
dart run flureadium:copy_js_file web/
```

This copies the Readium web reader JavaScript to your web directory.

#### 2. Add Script Tags

In `web/index.html`, add to the `<head>` section:

```html
<!-- Flutter initialization -->
<script src="flutter.js" defer></script>

<!-- Flureadium reader -->
<script src="readiumReader.js" defer></script>
```

If you placed the JS file in a subdirectory, update the path accordingly.

## Verify Installation

Create a simple test to verify the setup:

```dart
import 'package:flureadium/flureadium.dart';

void main() async {
  final flureadium = Flureadium();

  // Try loading a publication
  try {
    final pub = await flureadium.loadPublication('file:///path/to/book.epub');
    print('Loaded: ${pub.metadata.title}');
  } on ReadiumException catch (e) {
    print('Error: ${e.message}');
  }
}
```

## Troubleshooting

### Android: "MainActivity cannot be cast to FragmentActivity"

Ensure your `MainActivity` extends `FlutterFragmentActivity`, not `FlutterActivity`.

### iOS: Pod Install Fails

Try:
```bash
cd ios
pod deintegrate
pod install --repo-update
```

### Web: Reader Not Loading

Ensure `readiumReader.js` is in your web directory and the script tag path is correct.

## Next Steps

- [Quick Start](quick-start.md) - Create your first reader
- [Concepts](concepts.md) - Learn core concepts
- [EPUB Reading Guide](../guides/epub-reading.md) - Detailed reading tutorial
