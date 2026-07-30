# Car content

The car API defines how a native car integration asks a host app for its
library. It is the data contract between the two sides: the host describes its
books as plain rows, and the native layer requests and plays them.

The native CarPlay and Android Auto renderers that draw these rows on a head
unit are built in later phases. This page documents the contract they consume,
which a host can implement and test today.

flureadium never reaches into the host's data or decides policy. Everything the
head unit needs arrives through one object the host registers, and all
user-facing text is passed in already localized. That keeps the plugin free of
any app-specific or localization concerns.

## Registering a provider

Call `registerCarContentProvider` once during app start, before a car connects:

```dart
Flureadium().registerCarContentProvider(
  myProvider,
  strings: CarContentStrings(
    emptyRootTitle: 'Nothing to play yet',
    emptyRootSubtitle: 'Books you add will appear here.',
    voiceUnavailable: 'This voice is not installed.',
    offline: 'This book needs a connection.',
  ),
);
```

Call `unregisterCarContentProvider()` to remove it (for example in tests, or
when tearing down). The channel handler stays installed either way, so a car
process that launches cold and calls in before registration gets an empty
result rather than an error.

## Refreshing a live car surface

The car transport is otherwise one-directional: native asks, the host answers.
`refreshCarContent()` is the one outbound signal, telling a connected head unit
to re-ask for its browse tree after the library changes:

```dart
Flureadium().refreshCarContent();
```

Call it on every browsable-set mutation: a book added, deleted, categorized,
completed, or renamed. It is fire-and-forget and a no-op when no car surface is
connected, so it is safe to call unconditionally; coalesce bursts on the host
side so a bulk import collapses to one refresh. On iOS it repaints the retained
root-tab list templates in place, leaving pushed detail lists to re-fetch on the
next navigation. On Android, the equivalent step is notifying the subscribed
browse parents, and it ships in a later phase.

## `CarContentProvider`

The contract the host implements. Every method is async because the car can ask
before any UI is alive, so answers usually come from the host's own storage.

| Method | Returns |
|--------|---------|
| `rootTabs()` | The top-level tabs, for example Continue, Library, Search. |
| `children(nodeId)` | The rows nested under a tab or container. |
| `search(query)` | The rows matching a query across the library. |
| `play(nodeId)` | Starts playback; the host decides audiobook versus read-aloud. |
| `nowPlayingChapters()` | The chapters of whatever is playing now. |
| `addBookmark()` | Records a bookmark at the current playback position; the host chooses where. |
| `cycleSpeed()` | Advances playback speed to the host's next preset and persists it. |

On the Now Playing screen the renderers surface these as buttons where the
platform supports them. iOS installs a bookmark button (audiobook items only), a
playback-rate button (`cycleSpeed`), and a chapters button that pushes
`nowPlayingChapters()`. Android Auto adds a bookmark custom command
(`addBookmark`) next to its rewind and forward buttons; it has no playback-rate
button, so `cycleSpeed` is not surfaced there. Whether the active item is an
audiobook is host playback state. The host passes that flag when it installs the
buttons; the plugin never tracks it.

## `CarBrowseNode`

One row on the head unit. It is a plain serializable value with no reader or
host types, so it survives the trip to native code unchanged.

| Field | Meaning |
|-------|---------|
| `id` | Opaque host id, for example `book:42`. Required, non-empty. |
| `title` | Primary text. Required, non-empty. |
| `subtitle` | Secondary text, such as an author or time left. Optional. |
| `artworkPath` | Cover path or url the host resolves. Optional. |
| `kind` | A `CarNodeKind`: `tab`, `container`, `audiobook`, `ttsBook`, `chapter`, or `siri`. |
| `isPlayable` | Whether selecting the row starts playback instead of opening a child list. |
| `progress` | Playback progress from 0 to 1, or null. Values outside that range are rejected. |
| `isNowPlaying` | Whether this row is the current item. |

The `siri` kind marks the Search tab's voice-assistant entry rather than a normal row. Renderers surface it per platform: iOS installs the system Siri assistant cell, while Android Auto drops it, since its voice input is Google Assistant rather than a browse row. See the [iOS](../platform-specific/ios.md) and [Android](../platform-specific/android.md) platform docs.

## `CarTab`

A root tab: an `id`, a `title`, and an optional `iconName` hint that renderers
map to a native system image where one exists. A blank id or title is rejected.

## `CarContentStrings`

The already-localized status text the renderers show as-is: `emptyRootTitle`,
`emptyRootSubtitle`, `voiceUnavailable`, and `offline`. Each field is required
and must be non-empty, so a blank label never reaches the head unit.

## What the host owns

flureadium carries the data across to the car layer. The host decides everything else:
which books appear, how they sort, what counts as playable, whether a title
streams or plays offline, and all of the copy. A book is playable in the car
only if the host marks its node `isPlayable`.
