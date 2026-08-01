# Preferences

Flureadium provides preference classes for customizing the reader experience: EPUB visual preferences, TTS preferences, Audio preferences, PDF preferences, and navigation configuration.

## EPUBPreferences

Controls visual appearance of EPUB content.

**Source:** [reader_epub_preferences.dart](../../../flureadium_platform_interface/lib/src/reader/reader_epub_preferences.dart)

### Constructor

```dart
EPUBPreferences({
  required String fontFamily,
  required int fontSize,
  required double? fontWeight,
  required bool? verticalScroll,
  required Color? backgroundColor,
  required Color? textColor,
  double? pageMargins,
})
```

### Properties

#### fontFamily

**Type:** `String` (required)

The font family name. Use system fonts or fonts bundled with the EPUB.

```dart
fontFamily: 'Georgia'
fontFamily: 'Helvetica'
fontFamily: 'OpenDyslexic'
```

#### fontSize

**Type:** `int` (required)

Font size as a percentage. 100 = normal size (1em).

```dart
fontSize: 80   // 0.8em (smaller)
fontSize: 100  // 1.0em (normal)
fontSize: 120  // 1.2em (larger)
fontSize: 150  // 1.5em (much larger)
```

#### fontWeight

**Type:** `double?`

Font weight value. Common values:

```dart
fontWeight: 300  // Light
fontWeight: 400  // Normal
fontWeight: 500  // Medium
fontWeight: 700  // Bold
```

#### verticalScroll

**Type:** `bool?`

Whether to use vertical scrolling instead of pagination.

```dart
verticalScroll: false  // Paginated (default)
verticalScroll: true   // Continuous scroll
```

#### backgroundColor

**Type:** `Color?`

Page background color.

```dart
backgroundColor: Color(0xFFFFFFFF)  // White
backgroundColor: Color(0xFFF5E6D3)  // Sepia
backgroundColor: Color(0xFF1A1A1A)  // Dark
```

#### textColor

**Type:** `Color?`

Text color.

```dart
textColor: Color(0xFF000000)  // Black
textColor: Color(0xFF5C4033)  // Brown (sepia)
textColor: Color(0xFFE0E0E0)  // Light gray (dark mode)
```

#### pageMargins

**Type:** `double?`

Page margins as a decimal (0.0 to 1.0).

```dart
pageMargins: 0.05  // 5% margins
pageMargins: 0.1   // 10% margins
pageMargins: 0.15  // 15% margins
```

### Methods

#### toJson

Converts to JSON for platform communication.

```dart
Map<String, dynamic> toJson()
```

### Example Usage

```dart
// Light mode
final lightPrefs = EPUBPreferences(
  fontFamily: 'Georgia',
  fontSize: 100,
  fontWeight: 400,
  verticalScroll: false,
  backgroundColor: Color(0xFFFFFFFF),
  textColor: Color(0xFF000000),
  pageMargins: 0.1,
);

// Sepia mode
final sepiaPrefs = EPUBPreferences(
  fontFamily: 'Palatino',
  fontSize: 110,
  fontWeight: 400,
  verticalScroll: false,
  backgroundColor: Color(0xFFF5E6D3),
  textColor: Color(0xFF5C4033),
  pageMargins: 0.1,
);

// Dark mode
final darkPrefs = EPUBPreferences(
  fontFamily: 'Helvetica',
  fontSize: 100,
  fontWeight: 400,
  verticalScroll: false,
  backgroundColor: Color(0xFF1A1A1A),
  textColor: Color(0xFFE0E0E0),
  pageMargins: 0.1,
);

// Apply
await flureadium.setEPUBPreferences(lightPrefs);
```

## TTSPreferences

Controls text-to-speech behavior.

**Source:** [reader_tts_preferences.dart](../../../flureadium_platform_interface/lib/src/reader/reader_tts_preferences.dart)

### Constructor

```dart
TTSPreferences({
  double? speed,
  double? pitch,
  String? voiceIdentifier,
  String? languageOverride,
  ControlPanelInfoType? controlPanelInfoType,
})
```

### Properties

#### speed

**Type:** `double?`

Speech rate multiplier. Typical range: 0.5 to 2.0.

```dart
speed: 0.5   // Half speed
speed: 1.0   // Normal
speed: 1.25  // 25% faster
speed: 1.5   // 50% faster
speed: 2.0   // Double speed
```

#### pitch

**Type:** `double?`

Voice pitch multiplier. Typical range: 0.5 to 2.0.

```dart
pitch: 0.8  // Lower pitch
pitch: 1.0  // Normal
pitch: 1.2  // Higher pitch
```

#### voiceIdentifier

**Type:** `String?`

Platform-specific voice identifier. Get available voices with `ttsGetSystemVoices()`, which works before TTS is enabled — you need the identifier in hand to build the `TTSPreferences` you pass to `ttsEnable()`.

```dart
voiceIdentifier: 'com.apple.voice.compact.en-US.Samantha'  // iOS
voiceIdentifier: 'en-US-Standard-A'                         // Android
```

#### languageOverride

**Type:** `String?`

Override the publication's language for voice selection.

```dart
languageOverride: 'en-US'
languageOverride: 'en-GB'
languageOverride: 'fr-FR'
```

#### controlPanelInfoType

**Type:** `ControlPanelInfoType?`

What information to show in system media controls.

### Example Usage

```dart
// Enable TTS with preferences
await flureadium.ttsEnable(TTSPreferences(
  speed: 1.2,
  pitch: 1.0,
));

// Get available voices
final voices = await flureadium.ttsGetAvailableVoices();
for (final voice in voices) {
  print('${voice.name} (${voice.language}): ${voice.identifier}');
}

// Set a specific voice
final englishVoice = voices.firstWhere(
  (v) => v.language.startsWith('en'),
);
await flureadium.ttsSetVoice(englishVoice.identifier, 'en');

// Update preferences during playback
await flureadium.ttsSetPreferences(TTSPreferences(
  speed: 1.5,  // Speed up
));
```

## AudioPreferences

Controls audiobook playback behavior.

**Source:** [reader_audio_preferences.dart](../../../flureadium_platform_interface/lib/src/reader/reader_audio_preferences.dart)

### Constructor

```dart
AudioPreferences({
  double? volume,
  double? speed,
  double? pitch,
  double? seekInterval,
  bool? allowExternalSeeking,
  ControlPanelInfoType? controlPanelInfoType,
})
```

### Properties

#### volume

**Type:** `double?`

Playback volume (0.0 to 1.0).

```dart
volume: 0.5  // 50%
volume: 1.0  // 100%
```

#### speed

**Type:** `double?`

Playback speed multiplier.

```dart
speed: 0.75  // 75% speed
speed: 1.0   // Normal
speed: 1.5   // 1.5x speed
speed: 2.0   // 2x speed
```

#### pitch

**Type:** `double?`

Audio pitch multiplier.

```dart
pitch: 1.0  // Normal
```

#### seekInterval

**Type:** `double?`

Skip interval in seconds for next/previous controls.

```dart
seekInterval: 10   // Skip 10 seconds
seekInterval: 30   // Skip 30 seconds
seekInterval: 60   // Skip 1 minute
```

#### allowExternalSeeking

**Type:** `bool?`

Whether to allow seeking from system controls (lockscreen, etc.).

```dart
allowExternalSeeking: true  // Allow
allowExternalSeeking: false // Disable
```

#### controlPanelInfoType

**Type:** `ControlPanelInfoType?`

What information to show in system media controls.

### Example Usage

```dart
// Enable audiobook with preferences
await flureadium.audioEnable(
  prefs: AudioPreferences(
    volume: 1.0,
    speed: 1.0,
    seekInterval: 30,
    allowExternalSeeking: true,
  ),
  fromLocator: savedPosition,
);

// Update preferences during playback
await flureadium.audioSetPreferences(AudioPreferences(
  speed: 1.5,  // Speed up
));

// Seek forward
await flureadium.audioSeekBy(Duration(seconds: 30));
```

## PDFPreferences

> **Note:** PDF support is available on Android and iOS:
> - **Android:** Native navigator via Pdfium adapter
> - **iOS:** Native navigator via PDFKit
> - **Flutter widget layer:** `setPDFPreferences()` method available
> - **Status:** Manual testing in progress

Controls PDF reader behavior.

**Source:** [reader_pdf_preferences.dart](../../../flureadium_platform_interface/lib/src/reader/reader_pdf_preferences.dart)

### Constructor

```dart
PDFPreferences({
  PDFFit? fit,
  PDFScrollMode? scrollMode,
  PDFPageLayout? pageLayout,
  bool? offsetFirstPage,
})
```

### Properties

#### fit

**Type:** `PDFFit?`

How the PDF page fits within the viewport.

```dart
fit: PDFFit.width    // Fit page width to viewport width
fit: PDFFit.contain  // Fit entire page in viewport
```

#### scrollMode

**Type:** `PDFScrollMode?`

Scroll direction for PDF navigation.

```dart
scrollMode: PDFScrollMode.horizontal  // Swipe left/right between pages
scrollMode: PDFScrollMode.vertical    // Scroll up/down through pages
```

#### pageLayout

**Type:** `PDFPageLayout?`

Page layout mode for PDF display.

```dart
pageLayout: PDFPageLayout.single     // Display one page at a time
pageLayout: PDFPageLayout.double     // Display two pages side-by-side (spreads)
pageLayout: PDFPageLayout.automatic  // Automatically choose based on viewport
```

#### offsetFirstPage

**Type:** `bool?`

Whether to offset the first page in double-page spreads (useful for cover pages).

```dart
offsetFirstPage: true   // First page displayed alone, then pairs
offsetFirstPage: false  // All pages displayed in pairs
```

### Methods

#### toJson

Converts to JSON for platform communication.

```dart
Map<String, dynamic> toJson()
```

#### fromJsonMap

Creates preferences from a JSON map.

```dart
factory PDFPreferences.fromJsonMap(Map<String, dynamic> map)
```

#### copyWith

Creates a copy with specified values overridden.

```dart
PDFPreferences copyWith({
  PDFFit? fit,
  PDFScrollMode? scrollMode,
  PDFPageLayout? pageLayout,
  bool? offsetFirstPage,
})
```

### Example Usage

```dart
// Default reading mode
final defaultPrefs = PDFPreferences(
  fit: PDFFit.width,
  scrollMode: PDFScrollMode.horizontal,
  pageLayout: PDFPageLayout.single,
);

// Document viewing mode (vertical scroll, fit whole page)
final documentPrefs = PDFPreferences(
  fit: PDFFit.contain,
  scrollMode: PDFScrollMode.vertical,
  pageLayout: PDFPageLayout.single,
);

// Book spread mode (two pages side-by-side)
final spreadPrefs = PDFPreferences(
  fit: PDFFit.contain,
  scrollMode: PDFScrollMode.horizontal,
  pageLayout: PDFPageLayout.double,
  offsetFirstPage: true,  // Cover page alone
);

// Modify existing preferences
final updated = defaultPrefs.copyWith(
  scrollMode: PDFScrollMode.vertical,
);
```

## ReaderNavigationConfig

Controls navigation UX behavior in the reader. These settings are app-developer concerns — they define how the reader responds to user gestures — and are separate from Readium reading preferences.

**Source:** [reader_navigation_config.dart](../../../flureadium_platform_interface/lib/src/reader/reader_navigation_config.dart)

### Constructor

```dart
ReaderNavigationConfig({
  bool? enableEdgeTapNavigation,
  bool? enableSwipeNavigation,
  double? edgeTapAreaPoints,
  bool? disableDoubleTapZoom,
  bool? disableTextSelection,
  bool? disableDragGestures,
  bool? disableDoubleTapTextSelection,
})
```

### Properties

#### enableEdgeTapNavigation

**Type:** `bool?`

Whether tapping the left/right edges of the screen navigates pages. Defaults to `true` when null on the native side.

```dart
enableEdgeTapNavigation: true   // Edge taps navigate pages (default)
enableEdgeTapNavigation: false  // Edge taps disabled
```

#### enableSwipeNavigation

**Type:** `bool?`

Whether swiping left/right navigates pages. Defaults to `true` when null on the native side.

```dart
enableSwipeNavigation: true   // Swipe navigates pages (default)
enableSwipeNavigation: false  // Swipe navigation disabled
```

#### edgeTapAreaPoints

**Type:** `double?`

Edge tap zone width in absolute points (44–120). Controls how wide the left/right tap zones are for page navigation. Values are clamped to the 44–120 range on the native side.

```dart
edgeTapAreaPoints: 44   // Default (iOS HIG minimum tap target)
edgeTapAreaPoints: 60   // Wider tap zones
edgeTapAreaPoints: 80   // Even wider tap zones
edgeTapAreaPoints: 120  // Maximum tap zones
```

#### disableDoubleTapZoom (iOS only)

**Type:** `bool?`

Whether to disable the built-in double-tap-to-zoom gesture. When true, double-tap won't zoom the PDF content.

```dart
disableDoubleTapZoom: false  // Zoom enabled (default)
disableDoubleTapZoom: true   // Zoom disabled
```

#### disableTextSelection (iOS only)

**Type:** `bool?`

Whether to disable text selection gestures. When true, long-press won't select text in the PDF.

```dart
disableTextSelection: false  // Text selection enabled (default)
disableTextSelection: true   // Text selection disabled
```

#### disableDragGestures (iOS only)

**Type:** `bool?`

Whether to disable drag gestures. When true, drag gestures won't trigger text selection or drag-and-drop.

```dart
disableDragGestures: false  // Drag gestures enabled (default)
disableDragGestures: true   // Drag gestures disabled
```

#### disableDoubleTapTextSelection (iOS only)

**Type:** `bool?`

Whether to disable double-tap word selection in PDF text. When true, double-tapping on PDF text won't select a word or show the Copy/Look Up/Translate menu. Long-press text selection remains fully functional.

```dart
disableDoubleTapTextSelection: false  // Double-tap selection enabled (default)
disableDoubleTapTextSelection: true   // Double-tap selection disabled
```

### Example Usage

```dart
// EPUB: enable edge-tap navigation
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(enableEdgeTapNavigation: true),
);

// PDF: read-only mode (disable all interactive gestures)
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(
    enableEdgeTapNavigation: true,
    disableDoubleTapZoom: true,
    disableTextSelection: false,
    disableDragGestures: true,
    disableDoubleTapTextSelection: true,
  ),
);

// Wider edge tap zones
await flureadium.setNavigationConfig(
  ReaderNavigationConfig(
    enableEdgeTapNavigation: true,
    edgeTapAreaPoints: 80,
  ),
);
```

## PDFFit

Enum for page fit modes.

```dart
enum PDFFit {
  width,    // Fit page width to viewport width
  contain,  // Fit entire page in viewport
}
```

## PDFScrollMode

Enum for scroll direction.

```dart
enum PDFScrollMode {
  horizontal,  // Scroll horizontally between pages
  vertical,    // Scroll vertically through pages
}
```

## PDFPageLayout

Enum for page layout modes.

```dart
enum PDFPageLayout {
  single,     // Display one page at a time
  double,     // Display two pages side-by-side (spreads)
  automatic,  // Automatically choose based on viewport
}
```

## ControlPanelInfoType

Enum for system media control display options.

**Source:** [reader_audio_preferences.dart](../../../flureadium_platform_interface/lib/src/reader/reader_audio_preferences.dart)

### Values

```dart
enum ControlPanelInfoType {
  standard,           // Default display
  standardWCh,        // Standard with chapter
  chapterTitleAuthor, // Chapter, Title, Author
  chapterTitle,       // Chapter and Title
  titleChapter,       // Title and Chapter
}
```

## Common Patterns

### Theme Presets

```dart
class ReaderTheme {
  final String name;
  final EPUBPreferences preferences;

  const ReaderTheme(this.name, this.preferences);

  static final light = ReaderTheme('Light', EPUBPreferences(
    fontFamily: 'Georgia',
    fontSize: 100,
    fontWeight: 400,
    verticalScroll: false,
    backgroundColor: Color(0xFFFFFFFF),
    textColor: Color(0xFF000000),
  ));

  static final sepia = ReaderTheme('Sepia', EPUBPreferences(
    fontFamily: 'Georgia',
    fontSize: 100,
    fontWeight: 400,
    verticalScroll: false,
    backgroundColor: Color(0xFFF5E6D3),
    textColor: Color(0xFF5C4033),
  ));

  static final dark = ReaderTheme('Dark', EPUBPreferences(
    fontFamily: 'Georgia',
    fontSize: 100,
    fontWeight: 400,
    verticalScroll: false,
    backgroundColor: Color(0xFF1A1A1A),
    textColor: Color(0xFFE0E0E0),
  ));
}
```

### Persisting Preferences

```dart
class PreferencesManager {
  Future<void> saveEPUBPreferences(EPUBPreferences prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('fontFamily', prefs.fontFamily);
    await sp.setInt('fontSize', prefs.fontSize);
    // ... save other properties
  }

  Future<EPUBPreferences> loadEPUBPreferences() async {
    final sp = await SharedPreferences.getInstance();
    return EPUBPreferences(
      fontFamily: sp.getString('fontFamily') ?? 'Georgia',
      fontSize: sp.getInt('fontSize') ?? 100,
      fontWeight: 400,
      verticalScroll: sp.getBool('verticalScroll') ?? false,
      backgroundColor: Color(sp.getInt('backgroundColor') ?? 0xFFFFFFFF),
      textColor: Color(sp.getInt('textColor') ?? 0xFF000000),
    );
  }
}
```

### Font Size Slider

```dart
Widget buildFontSizeSlider(int currentSize, Function(int) onChanged) {
  return Slider(
    min: 50,
    max: 200,
    divisions: 15,
    value: currentSize.toDouble(),
    onChanged: (value) => onChanged(value.round()),
    label: '${currentSize}%',
  );
}
```

## See Also

- [Preferences Guide](../guides/preferences.md) - Detailed customization guide
- [Flureadium Class](flureadium-class.md) - API for applying preferences
- [Text-to-Speech Guide](../guides/text-to-speech.md) - TTS configuration
- [Audiobook Guide](../guides/audiobook-playback.md) - Audio configuration
