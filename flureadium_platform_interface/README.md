# Flureadium Platform Interface

A common platform interface for the [flureadium](https://pub.dev/packages/flureadium) plugin.

This interface allows platform-specific implementations of the Flureadium plugin, as well as the plugin itself, to ensure they are implementing the same interface.

## Usage

To implement a new platform-specific implementation of `flureadium`, extend [`FlureadiumPlatform`](lib/flureadium_platform_interface.dart) with an implementation that performs the platform-specific behavior.

This package is endorsed and used by the `flureadium` package. It should not be used directly by app developers.

## Current platform contract

Platform implementations are expected to provide publication lifecycle, visual navigation, playback, preference, decoration, and resource helper APIs. Recent resource helpers include `renderFirstPage()` for PDF cover generation and `extractPageThumbnail()` for downscaled JPEG thumbnails from image resources in the currently open publication.

`extractPageThumbnail()` should return `null` when a platform cannot resolve or decode the resource. Platforms that do not support thumbnail extraction may keep the default `UnimplementedError` until they add support.

## Note on breaking changes

Strongly prefer non-breaking changes (such as adding a method to the interface) over breaking changes for this package.

See https://flutter.dev/go/platform-interface-breaking-changes for a discussion on why a less-clean interface is preferable to a breaking change.

## Development

Developed and tested with **Flutter 3.44.7 (Dart 3.12.2)**. The package `pubspec.yaml` constraints (`sdk: >=3.8.0 <4.0.0`, `flutter: >=3.3.0`) remain the source of truth for supported versions. Contributors may pin the toolchain locally with [fvm](https://fvm.app) (`fvm use 3.44.7`); the fvm files are gitignored and not required.

## License

LGPL v3 -- see [LICENSE](LICENSE) for details.
