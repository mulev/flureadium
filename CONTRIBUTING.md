# Contributing to Flureadium

Thank you for your interest in contributing!

## Development Setup

1. Clone the repository:
```bash
git clone https://github.com/mulev/flureadium.git
cd flureadium
```

2. Install dependencies:
```bash
cd flureadium_platform_interface && flutter pub get
cd ../flureadium && flutter pub get
cd example && flutter pub get
```

3. Run tests:
```bash
flutter test
```

## Project Structure

```
flureadium/
├── flureadium/                      # Main plugin package
│   ├── lib/                         # Dart source code
│   ├── android/                     # Android platform code
│   ├── ios/                         # iOS platform code
│   ├── macos/                       # macOS platform code
│   ├── web/                         # Web platform code (TypeScript)
│   └── example/                     # Example app
├── flureadium_platform_interface/   # Platform interface package
│   └── lib/                         # Shared models and interfaces
└── project/                         # Project documentation
```

## Code Style

- Run `dart format` before committing
- Follow existing code patterns
- Add documentation for public APIs
- Write tests for new features

## Making Changes

### For Dart/Flutter code:
1. Make your changes in the appropriate package
2. Add or update tests as needed
3. Run `flutter analyze` to check for issues
4. Run `flutter test` to ensure tests pass

### For Web (TypeScript) code:
1. Make changes in `flureadium/web/`
2. Run `npm run build` to compile TypeScript
3. Test in the example app with `flutter run -d chrome`

### Releasing a new version

The plugin's version is written in four files and they must move together. Only
the first is what pub.dev resolves; the other three are metadata that shows up in
CocoaPods output and Gradle artifacts, and each had drifted to a placeholder
before anyone noticed.

1. `flureadium/pubspec.yaml` — `version:`, plus a `flureadium/CHANGELOG.md` entry
2. `flureadium/ios/flureadium.podspec` — `s.version`
3. `flureadium/macos/flureadium.podspec` — `s.version`
4. `flureadium/android/build.gradle` — `version`

`flureadium_platform_interface` and `flureadium_lints` version independently;
bump them only when their own contents change.

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes with tests
3. Ensure CI passes
4. Request review

## Reporting Issues

Please include:
- Flutter version (`flutter --version`)
- Platform (Android/iOS/macOS/Web)
- Minimal reproduction code
- Expected vs actual behavior
- Any error messages or stack traces

## Testing

Run tests for each package:
```bash
# Platform interface tests
cd flureadium_platform_interface
flutter test

# Plugin tests
cd flureadium
flutter test
```

## Documentation

When adding new public APIs:
1. Add dartdoc comments to all public members
2. Include usage examples in doc comments
3. Update README if needed
4. Consider adding to the example app

## Questions?

Feel free to open an issue for questions or discussions about potential contributions.
