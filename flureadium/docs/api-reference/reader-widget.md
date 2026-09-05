# ReaderWidget

The `ReadiumReaderWidget` displays publication content and handles user interactions. It wraps native Readium navigator views for each platform, including EPUB, PDF, and image-based publications such as CBZ and DIVINA.

**Source:** [reader_widget.dart](../../lib/reader_widget.dart)

## Overview

```dart
ReadiumReaderWidget(
  publication: publication,
  initialLocator: savedPosition,
  onLocatorChanged: (locator) => saveProgress(locator),
)
```

## Constructor

```dart
const ReadiumReaderWidget({
  required Publication publication,
  Locator? initialLocator,
  void Function(Offset position)? onTap,
  Function(String)? onExternalLinkActivated,
  void Function(Locator)? onLocatorChanged,
  VoidCallback? onReady,
  Key? key,
})
```

## Parameters

### publication

**Type:** `Publication` (required)

The publication to display. Obtain from `flureadium.openPublication()`.

```dart
final pub = await flureadium.openPublication('book.epub');
ReadiumReaderWidget(publication: pub, ...)
```

The same widget also renders image-based publications:

```dart
final comic = await flureadium.openPublication('issue.cbz');
ReadiumReaderWidget(publication: comic)
```

Assigning a different `Publication` to a mounted widget rebuilds the native reader view for the new publication. The check is instance identity, not equality — `openPublication` returns a fresh `Publication` for every call, including reopening the same file, and each of those is a real swap because the native side has already released the previous publication's navigator. Passing the same instance again changes nothing.

A swap resets the widget's per-view state: the reading position, the last-skipped chapter, and the reader-ready signal all start over. A `getLocatorFragments` call still in flight resolves to `null`.

### initialLocator

**Type:** `Locator?`

Starting position in the publication. If null, starts from the beginning.

```dart
// Restore saved position
final savedJson = prefs.getString('lastPosition');
final savedLocator = savedJson != null
    ? Locator.fromJsonString(savedJson)
    : null;

ReadiumReaderWidget(
  publication: pub,
  initialLocator: savedLocator,
)
```

### onTap

**Type:** `void Function(Offset position)?`

Called when the user taps the content and Readium handled nothing internally.
The position is in logical pixels, relative to the reader view.

Readium filters the tap before this callback runs. In an EPUB, a tap on a
hyperlink, a footnote, or any other interactive element navigates and does not
fire `onTap` — you get taps on plain content only, so a host can toggle its
chrome on a single tap without swallowing links.

That filter is WebView-specific, and PDF and CBZ have no equivalent. On iOS, a tap
on a PDF link annotation follows the link and reports the tap as well. On Android
the pdfium adapter forwards the point and follows nothing, so the same tap is
reported and navigates nowhere.

One region may not be yours: the left and right edge strips, `edgeTapAreaPoints`
wide, belong to the native edge-tap overlay. A touch the overlay claims never
reaches Readium, so `onTap` does not fire there.

The overlay claims an edge strip only when it has a page turn to run on it —
the reader is paginated and `enableEdgeTapNavigation` is on. Turn edge-tap
navigation off, or put an EPUB into scroll mode, and the overlay claims nothing:
`onTap` fires across the full width.

Two exceptions to read before you rely on it:

- **Android CBZ has no overlay at all.** It is created by the EPUB and PDF
  readers only, and `ImageNavigator.setNavigationConfig` is an empty body. So on
  an Android CBZ nothing claims the edge strips and `enableEdgeTapNavigation` has
  nothing to act on — taps there reach the navigator like any other, which is
  what the tap forwarder reports. That follows from the wiring rather than from a
  device run; the CBZ edge case is on the manual verification list. iOS CBZ does
  have the overlay and follows the rule above.
- **Swipes are gated differently per platform, and neither platform can switch
  EPUB swiping off.** On Android a fling only pages through the overlay if the
  edge-tap gate already claimed that strip, so `enableSwipeNavigation` never
  holds a strip open — and Readium's own `R2WebView` still pages a paginated
  EPUB on a horizontal drag, whatever either flag says. On iOS the plugin's swipe
  recognizers sit on the full-size container and test direction only, so with
  `enableSwipeNavigation` on a swipe anywhere pages regardless of
  `enableEdgeTapNavigation`; with it off their callbacks are cleared, but
  Readium's `PaginationView` keeps paging on a drag.

See
[Edge Tap and Swipe Navigation](../platform-specific/ios.md#edge-tap-and-swipe-navigation)
for iOS and
[Edge Tap and Swipe Navigation](../platform-specific/android.md#edge-tap-and-swipe-navigation)
for Android.

Everywhere else on the page, what a region means is a host decision — the plugin
reports where the tap landed and nothing more.

```dart
ReadiumReaderWidget(
  publication: pub,
  onTap: (position) {
    setState(() => _showControls = !_showControls);
  },
)
```

### onExternalLinkActivated

**Type:** `Function(String)?`

Called when the native reader reports that the user activated an external link
(a URL outside the publication). The callback is delivered to the host app, so
the host decides whether to block, confirm, or launch the URL.

```dart
ReadiumReaderWidget(
  publication: pub,
  onExternalLinkActivated: (url) async {
    // Host app controls external-link policy.
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    }
  },
)
```

Use this seam to keep reader-originated links consistent with the rest of your
app's external URL policy. For example, apps that must avoid in-app browser
surfaces during restricted-content flows can always hand the URL off to the OS
browser instead.

### onLocatorChanged

**Type:** `void Function(Locator)?`

Called when the reading position changes. Use for saving progress.

```dart
ReadiumReaderWidget(
  publication: pub,
  onLocatorChanged: (locator) {
    final progress = locator.locations?.totalProgression ?? 0;
    print('Progress: ${(progress * 100).toStringAsFixed(1)}%');

    // Save to storage
    prefs.setString('lastPosition', locator.json);
  },
)
```

One open can deliver several locators for the same page. On Android the first
one comes from Readium's initial position for the resource and carries no
`position` or `totalProgression` — the example above reads `0` for progress on
that delivery — and a second locator follows within roughly 200 ms with both
fields filled in. Neither is a page turn: `href` and `progression` are the same
in both.

So treat this callback as "here is the current position", not "the reader
moved". Compare `href` and `progression` if you need to know whether the reader
actually went somewhere; counting callbacks will tell you it moved when it did
not.

### onReady

**Type:** `VoidCallback?`

Called once per platform view, when the native view has been created and all EventChannel handlers are registered — on first mount, and again after each publication swap. This is the correct place to subscribe to `Flureadium.onReaderStatusChanged`, `Flureadium.onTextLocatorChanged`, and `Flureadium.onErrorEvent`.

On iOS these channels are registered lazily inside `ReadiumReaderView.init()`, which runs just before `onReady` fires. Subscribing before `onReady` causes `MissingPluginException`, which permanently closes the stream's internal `StreamController` and silently drops all subsequent events. On Android and web the channels are always ready, but using `onReady` for consistency is recommended.

```dart
class _ReaderPageState extends State<ReaderPage> {
  final _flureadium = Flureadium();
  StreamSubscription<Locator>? _locatorSub;

  void _subscribeToChannels() {
    _locatorSub?.cancel();
    _locatorSub = _flureadium.onTextLocatorChanged.listen(
      (l) => setState(() => _locator = l),
    );
  }

  @override
  void dispose() {
    _locatorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReadiumReaderWidget(
      publication: _publication!,
      onReady: _subscribeToChannels,
    );
  }
}
```

## Covering the load

The reader shows no content between mount and the moment Readium reports it. There is no plugin-side parameter for that window — cover it yourself by stacking a widget over the reader and dropping it when the reader reports `ready`:

```dart
class _ReaderPageState extends State<ReaderPage> {
  final _flureadium = Flureadium();
  StreamSubscription<ReadiumReaderStatus>? _statusSub;
  var _ready = false;

  void _subscribe() {
    _statusSub = _flureadium.onReaderStatusChanged.listen((status) {
      if (mounted) setState(() => _ready = status.isReady);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          ReadiumReaderWidget(
            publication: widget.publication,
            onReady: _subscribe,
          ),
          if (!_ready)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.white,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      );
}
```

Two things about this recipe are load-bearing.

**The reader stays in the tree.** Returning the cover *instead of* `ReadiumReaderWidget` never finishes loading: the platform view is what triggers creation, creation is what fires `onReady`, and `onReady` is where you subscribe. Swap the widget out and the status you are waiting for is never sent. Put the cover over the reader, not in place of it.

**Subscribing from `onReady` is early enough.** On Android and iOS the reader reports `loading` while the platform view is still being created, before Flutter can reply to Dart, so the first status is sent before any host can be listening. Both platforms hold the latest status and hand it to the first subscriber, so `ready` reaches a host that subscribes from `onReady` even when it was sent before the subscription existed. Web keeps no such buffer, since its status stream is a plain broadcast stream, but web fires `onReady` from the first frame while the JavaScript reader is still loading. The subscription is in place well before `ready` either way.

**One exception: PDF on iOS.** `PdfReaderView` publishes its statuses to its own `pdf-reader-status` channel (the `readerStatusStreamHandler` it creates in `PdfReaderView.init`), and nothing on the Dart side subscribes to it — `onReaderStatusChanged` listens on `dev.mulev.flureadium/reader-status` only. An iOS PDF therefore reports no status at all, so a cover gated on `ready` never comes down. Drop it on the first locator there, or on a timeout.

Whether the cover blocks input is your call. Wrap it in `IgnorePointer` to let touches through to the reader underneath, or leave it out to swallow them until the reader is up.

One note for your own widget tests: an indeterminate `CircularProgressIndicator` schedules frames for as long as it is mounted, so `pumpAndSettle` never returns while the cover is up. Pump in bounded steps until the condition you care about holds — the reader reporting `ready`, a finder matching — instead.

See [onReaderStatusChanged](streams-events.md#onreaderstatuschanged) for the full status set.

## Interface Methods

The widget implements `ReadiumReaderWidgetInterface`, providing these methods:

### go

Navigate to a specific locator.

```dart
Future<void> go(
  Locator locator, {
  required bool isAudioBookWithText,
  bool animated = false,
})
```

### goLeft

Navigate to the previous page.

```dart
Future<void> goLeft({bool animated = true})
```

### goRight

Navigate to the next page.

```dart
Future<void> goRight({bool animated = true})
```

### skipToNext

Skip to the next chapter.

```dart
Future<void> skipToNext({bool animated = true})
```

Moves to the next TOC entry. For EPUB3 books with a nested `toc.xhtml`, this is the next chapter at any depth — not the next top-level sibling. If the current page has no TOC entry, scans the reading order to find the nearest TOC entry ahead.

Entries the reader is already showing are passed over. A nav document that anchors a title, its byline and its imprint line as separate entries puts several of them on one rendered page, and the reader will not scroll to something already on screen — so the skip walks forward until it reaches an entry off the current page, and every tap moves. The walk stays inside the current resource: a target in another resource always re-renders, so it never needs the check. PDF outlines are left alone.

Entries that cannot be reached are passed over too. A nav document can point at a file that is in neither the reading order nor the resources; no locator can be built for such an entry, so a navigation aimed at it does nothing at all. The skip selects only among entries it can reach, and lands on the next one that works. That changes both ends of the contents as well. When every entry after the reader's is unreachable, the reader counts as being at the last chapter, so `skipToNext` steps into the reading order and lands on the next spine document — and stops there, because no contents entry names that document and a further skip finds nothing ahead of it. `skipToPrevious` does the same in reverse at the first entry. A host wiring button enablement off this should note that the first such tap still moves the reader. Entries that resolve are all kept — a part or section heading with chapters nested under it is a document of its own in a well-formed EPUB3, so hierarchical contents are unaffected.

On a reader that has not yet reported a page, the call waits for the first reported position instead of returning silently. A host that subscribes from `onReady` and skips right away gets the skip it asked for, rather than a no-op. If the view is released before it reports anything — a publication swap, for instance — the call returns without navigating.

### skipToPrevious

Skip to the previous chapter.

```dart
Future<void> skipToPrevious({bool animated = true})
```

Moves to the previous TOC entry, with the same hierarchical, between-entries, already-on-screen and unreachable-entry behavior as `skipToNext`. It also waits for the first reported position on a reader that has not reported one yet, and returns without navigating if the view is released first.

### getCurrentLocator

Get the current reading position.

```dart
Future<Locator?> getCurrentLocator()
```

### getLocatorFragments

Get additional locator fragments for a position.

```dart
Future<Locator?> getLocatorFragments(Locator locator)
```

### setEPUBPreferences

Apply EPUB visual preferences.

```dart
Future<void> setEPUBPreferences(EPUBPreferences preferences)
```

### setPDFPreferences

Apply PDF visual preferences.

```dart
Future<void> setPDFPreferences(PDFPreferences preferences)
```

### applyDecorations

Apply decorations to the content.

```dart
Future<void> applyDecorations(String id, List<ReaderDecoration> decorations)
```

## Platform Implementation

The widget uses platform-specific views:

### Android

Uses `PlatformViewLink` with `AndroidViewSurface` for high-performance native view embedding.

### iOS

Uses `UiKitView` for iOS native view integration.

### macOS

Uses Swift native view (similar to iOS).

### Web

Uses `ReadiumWebView` with JavaScript interop.

## Lifecycle Management

The widget automatically manages:

### Wakelock

Keeps the screen on while reading. Uses `WakelockManagerMixin`.

### Orientation

Handles device orientation changes. Uses `OrientationHandlerMixin`.

### Reader Registration

Manages widget registration with the platform. Uses `ReaderLifecycleMixin`.

## Complete Example

```dart
class ReaderScreen extends StatefulWidget {
  final String publicationPath;

  const ReaderScreen({required this.publicationPath, super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _flureadium = Flureadium();
  Publication? _publication;
  Locator? _initialLocator;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _loadPublication();
  }

  Future<void> _loadPublication() async {
    // Load saved position
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('position_${widget.publicationPath}');
    if (savedJson != null) {
      _initialLocator = Locator.fromJsonString(savedJson);
    }

    // Open publication
    final pub = await _flureadium.openPublication(widget.publicationPath);
    setState(() => _publication = pub);
  }

  @override
  void dispose() {
    _flureadium.closePublication();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_publication == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Reader
          ReadiumReaderWidget(
            publication: _publication!,
            initialLocator: _initialLocator,
            onTap: (position) {
              setState(() => _showControls = !_showControls);
            },
            onExternalLinkActivated: (url) {
              launchUrl(Uri.parse(url));
            },
            onLocatorChanged: (locator) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                'position_${widget.publicationPath}',
                locator.json,
              );
            },
          ),

          // Overlay controls
          if (_showControls)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AppBar(
                title: Text(_publication!.metadata.title ?? 'Reader'),
                backgroundColor: Colors.black54,
              ),
            ),

          if (_showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                      onPressed: () => _flureadium.skipToPrevious(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      onPressed: () => _flureadium.goLeft(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white),
                      onPressed: () => _flureadium.goRight(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      onPressed: () => _flureadium.skipToNext(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

## See Also

- [Flureadium Class](flureadium-class.md) - Main API
- [Publication](publication.md) - Publication model
- [Locator](locator.md) - Position tracking
- [Preferences](preferences.md) - Visual customization
