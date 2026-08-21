# Reader Preferences Guide

This guide covers customizing the reader appearance and behavior.

## Visual Appearance

### Font Settings

```dart
EPUBPreferences(
  fontFamily: 'Georgia',  // Font name
  fontSize: 120,          // 120% of normal size
  fontWeight: 400,        // Normal weight
  // ...
)
```

#### Available Font Families

Common system fonts:
- `Georgia` - Serif, good for reading
- `Palatino` - Serif, elegant
- `Helvetica` - Sans-serif, clean
- `Arial` - Sans-serif, widely available
- `Times New Roman` - Serif, traditional

Custom fonts bundled with EPUB are also available.

#### Font Size Scale

The `fontSize` property is a percentage:

| Value | Effect |
|-------|--------|
| 50 | Half size |
| 75 | 75% |
| 100 | Normal |
| 125 | 125% |
| 150 | 150% |
| 200 | Double |

#### Font Weight

| Value | Name |
|-------|------|
| 100 | Thin |
| 300 | Light |
| 400 | Normal |
| 500 | Medium |
| 700 | Bold |
| 900 | Black |

### Color Themes

```dart
// Light theme
EPUBPreferences(
  backgroundColor: Color(0xFFFFFFFF),  // White
  textColor: Color(0xFF000000),        // Black
  // ...
)

// Sepia theme
EPUBPreferences(
  backgroundColor: Color(0xFFF5E6D3),  // Warm beige
  textColor: Color(0xFF5C4033),        // Dark brown
  // ...
)

// Dark theme
EPUBPreferences(
  backgroundColor: Color(0xFF1A1A1A),  // Near black
  textColor: Color(0xFFE0E0E0),        // Light gray
  // ...
)
```

### Layout Settings

```dart
EPUBPreferences(
  verticalScroll: false,  // Paginated (default)
  pageMargins: 0.1,       // 10% margins
  // ...
)
```

#### Scroll vs Pagination

- `verticalScroll: false` - Paginated, page-by-page reading
- `verticalScroll: true` - Continuous vertical scroll

#### Page Margins

Value is a decimal from 0.0 to 1.0:
- `0.05` = 5% margins
- `0.1` = 10% margins
- `0.15` = 15% margins

## Theme Presets

### Creating Theme Classes

```dart
class ReaderTheme {
  final String name;
  final Color backgroundColor;
  final Color textColor;
  final IconData icon;

  const ReaderTheme({
    required this.name,
    required this.backgroundColor,
    required this.textColor,
    required this.icon,
  });

  EPUBPreferences toPreferences({
    required String fontFamily,
    required int fontSize,
  }) {
    return EPUBPreferences(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: 400,
      verticalScroll: false,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
  }

  static const light = ReaderTheme(
    name: 'Light',
    backgroundColor: Color(0xFFFFFFFF),
    textColor: Color(0xFF000000),
    icon: Icons.light_mode,
  );

  static const sepia = ReaderTheme(
    name: 'Sepia',
    backgroundColor: Color(0xFFF5E6D3),
    textColor: Color(0xFF5C4033),
    icon: Icons.auto_stories,
  );

  static const dark = ReaderTheme(
    name: 'Dark',
    backgroundColor: Color(0xFF1A1A1A),
    textColor: Color(0xFFE0E0E0),
    icon: Icons.dark_mode,
  );

  static const List<ReaderTheme> all = [light, sepia, dark];
}
```

## Settings UI

### Complete Settings Panel

```dart
class ReaderSettingsPanel extends StatefulWidget {
  final ReaderSettings settings;
  final Function(ReaderSettings) onChanged;

  const ReaderSettingsPanel({
    required this.settings,
    required this.onChanged,
    super.key,
  });

  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  late ReaderSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(ReaderSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Theme selection
          _buildThemeSelector(),

          SizedBox(height: 24),

          // Font size
          _buildFontSizeControl(),

          SizedBox(height: 24),

          // Font family
          _buildFontFamilySelector(),

          SizedBox(height: 24),

          // Layout toggle
          _buildLayoutToggle(),
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ReaderTheme.all.map((theme) {
            final isSelected = _settings.theme == theme;
            return GestureDetector(
              onTap: () => _update(_settings.copyWith(theme: theme)),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: theme.backgroundColor,
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.grey,
                    width: isSelected ? 3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Aa',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFontSizeControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Font Size', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.text_decrease),
              onPressed: _settings.fontSize > 50
                  ? () => _update(_settings.copyWith(
                        fontSize: _settings.fontSize - 10,
                      ))
                  : null,
            ),
            Expanded(
              child: Slider(
                min: 50,
                max: 200,
                divisions: 15,
                value: _settings.fontSize.toDouble(),
                label: '${_settings.fontSize}%',
                onChanged: (value) => _update(
                  _settings.copyWith(fontSize: value.round()),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.text_increase),
              onPressed: _settings.fontSize < 200
                  ? () => _update(_settings.copyWith(
                        fontSize: _settings.fontSize + 10,
                      ))
                  : null,
            ),
          ],
        ),
        Center(
          child: Text('${_settings.fontSize}%'),
        ),
      ],
    );
  }

  Widget _buildFontFamilySelector() {
    const fonts = ['Georgia', 'Palatino', 'Helvetica', 'Arial'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Font', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: fonts.map((font) {
            final isSelected = _settings.fontFamily == font;
            return ChoiceChip(
              label: Text(font, style: TextStyle(fontFamily: font)),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  _update(_settings.copyWith(fontFamily: font));
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLayoutToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Scroll Mode', style: Theme.of(context).textTheme.titleMedium),
        Switch(
          value: _settings.verticalScroll,
          onChanged: (value) => _update(
            _settings.copyWith(verticalScroll: value),
          ),
        ),
      ],
    );
  }
}

class ReaderSettings {
  final ReaderTheme theme;
  final String fontFamily;
  final int fontSize;
  final bool verticalScroll;

  const ReaderSettings({
    this.theme = ReaderTheme.light,
    this.fontFamily = 'Georgia',
    this.fontSize = 100,
    this.verticalScroll = false,
  });

  ReaderSettings copyWith({
    ReaderTheme? theme,
    String? fontFamily,
    int? fontSize,
    bool? verticalScroll,
  }) {
    return ReaderSettings(
      theme: theme ?? this.theme,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      verticalScroll: verticalScroll ?? this.verticalScroll,
    );
  }

  EPUBPreferences toEPUBPreferences() {
    return theme.toPreferences(
      fontFamily: fontFamily,
      fontSize: fontSize,
    ).copyWith(verticalScroll: verticalScroll);
  }
}
```

## Applying Preferences

### Set Default Preferences

```dart
// Before opening publication
flureadium.setDefaultPreferences(EPUBPreferences(
  fontFamily: 'Georgia',
  fontSize: 100,
  fontWeight: 400,
  verticalScroll: false,
  backgroundColor: Color(0xFFFFFFFF),
  textColor: Color(0xFF000000),
));
```

### Update During Reading

```dart
// Apply new preferences immediately
await flureadium.setEPUBPreferences(EPUBPreferences(
  fontFamily: 'Helvetica',
  fontSize: 120,
  fontWeight: 400,
  verticalScroll: true,
  backgroundColor: Color(0xFF1A1A1A),
  textColor: Color(0xFFE0E0E0),
));
```

## Persisting Preferences

### Save to SharedPreferences

```dart
class PreferencesStorage {
  static const _key = 'reader_preferences';

  Future<void> save(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'theme': settings.theme.name,
      'fontFamily': settings.fontFamily,
      'fontSize': settings.fontSize,
      'verticalScroll': settings.verticalScroll,
    }));
  }

  Future<ReaderSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return const ReaderSettings();

    final data = jsonDecode(json);
    return ReaderSettings(
      theme: ReaderTheme.all.firstWhere(
        (t) => t.name == data['theme'],
        orElse: () => ReaderTheme.light,
      ),
      fontFamily: data['fontFamily'] ?? 'Georgia',
      fontSize: data['fontSize'] ?? 100,
      verticalScroll: data['verticalScroll'] ?? false,
    );
  }
}
```

### Load on App Start

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReaderSettings>(
      future: PreferencesStorage().load(),
      builder: (context, snapshot) {
        final settings = snapshot.data ?? const ReaderSettings();

        // Set default preferences
        Flureadium().setDefaultPreferences(settings.toEPUBPreferences());

        return MaterialApp(
          // ...
        );
      },
    );
  }
}
```

## Per-Book Preferences

Some users prefer different settings per book:

```dart
class BookPreferences {
  final Map<String, ReaderSettings> _perBook = {};
  final ReaderSettings _default;

  BookPreferences(this._default);

  ReaderSettings getForBook(String bookId) {
    return _perBook[bookId] ?? _default;
  }

  void setForBook(String bookId, ReaderSettings settings) {
    _perBook[bookId] = settings;
  }

  void clearForBook(String bookId) {
    _perBook.remove(bookId);
  }
}
```

## System Theme Integration

Follow system dark mode:

```dart
class SystemAwareSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final systemTheme = brightness == Brightness.dark
        ? ReaderTheme.dark
        : ReaderTheme.light;

    return ReaderScreen(
      initialTheme: systemTheme,
    );
  }
}
```

## PDF Preferences

PDF documents have different preference options than EPUBs, focused on page layout and navigation rather than typography.

### Basic PDF Settings

```dart
PDFPreferences(
  fit: PDFFit.width,           // How page fits in viewport
  scrollMode: PDFScrollMode.horizontal,  // Swipe direction
  pageLayout: PDFPageLayout.single,      // Single or double pages
  offsetFirstPage: true,       // Cover page alone in spreads
)
```

### Fit Modes

- `PDFFit.width` - Fit page width to screen width (best for reading)
- `PDFFit.contain` - Fit entire page on screen (best for overview)

### Scroll Modes

- `PDFScrollMode.horizontal` - Swipe left/right between pages
- `PDFScrollMode.vertical` - Scroll up/down continuously

### Page Layouts

- `PDFPageLayout.single` - One page at a time
- `PDFPageLayout.double` - Two pages side-by-side (book spreads)
- `PDFPageLayout.automatic` - Choose based on screen size

### Applying PDF Preferences

```dart
// Set default PDF preferences before opening
flureadium.setDefaultPdfPreferences(PDFPreferences(
  fit: PDFFit.width,
  scrollMode: PDFScrollMode.horizontal,
  pageLayout: PDFPageLayout.single,
));

// Update during reading
await flureadium.setPDFPreferences(PDFPreferences(
  fit: PDFFit.contain,
  scrollMode: PDFScrollMode.vertical,
));
```

### iOS-Specific Gesture Controls

On iOS, PDF gesture behavior can be customized via `ReaderNavigationConfig`:

```dart
// Read-only mode: disable all interactive gestures
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(
    disableDoubleTapZoom: true,
    disableTextSelection: true,
    disableDragGestures: true,
    disableDoubleTapTextSelection: true,
  ),
);
```

These are useful for creating a simplified reading experience or when your app handles gestures differently.

### Navigation Configuration

Navigation behavior (edge taps, swipe, edge tap area) is configured separately from Readium reading preferences using `setNavigationConfig()`. Both edge tap and swipe navigation default to enabled. iOS and Android read the same three keys — see [Edge Tap and Swipe Navigation](../platform-specific/android.md#edge-tap-and-swipe-navigation) for the Android overlay.

```dart
// Disable edge taps but keep swipe navigation
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(
    enableEdgeTapNavigation: false,
    enableSwipeNavigation: true,
  ),
);

// Wider edge tap zones for accessibility
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(
    enableEdgeTapNavigation: true,
    edgeTapAreaPoints: 80,  // 80pt per side (default: 44pt)
  ),
);

// Disable all gesture-based navigation
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(
    enableEdgeTapNavigation: false,
    enableSwipeNavigation: false,
  ),
);
```

`edgeTapAreaPoints` uses absolute points (44–120, clamped automatically), ensuring consistent tap zones across all devices including iPad split-screen. Android reads the same number as dp. It is the only edge width there is: as of 0.17.0 the iOS build gives Readium's `DirectionalNavigationAdapter` an empty pointer policy, so the overlay is the single owner of edge pointers and `enableEdgeTapNavigation` governs every iOS edge tap. Before that, a second component claimed a wider zone of its own and ignored the preference.

In EPUB scroll mode, both gestures are automatically disabled regardless of configuration.

One platform difference worth knowing if your app reads taps: the iOS overlay leaves the edges alone as soon as `enableEdgeTapNavigation` is off, so `ReadiumReaderWidget.onTap` fires across the full width again. The Android overlay keeps claiming the edges while *either* edge tap or swipe navigation is on, so turning edge taps off alone does not bring `onTap` back to the strips.

## See Also

- [EPUBPreferences Reference](../api-reference/preferences.md#epubpreferences)
- [PDFPreferences Reference](../api-reference/preferences.md#pdfpreferences)
- [Flureadium Class](../api-reference/flureadium-class.md) - API for applying preferences
- [EPUB Reading Guide](epub-reading.md) - Visual reading customization
