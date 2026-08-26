## 0.17.2

### Bug Fixes

- **A chapter skip moves the reader now, on a book whose nav document anchors typographic lines**: `flattenToc` treats every nav point at every nesting depth as a chapter, which is what makes nested chapters reachable — but a title page that anchors its byline and its imprint line as separate entries puts several of them on one rendered page, and the reader declines to scroll to something already visible. On Gutenberg 25946 six such entries precede the first chapter, so four of the six taps it took to reach it changed nothing at all. `skipToNext` and `skipToPrevious` now walk forward while the next entry is both in the resource on screen and reported visible, and navigate to the first entry that fails either test. The walk stops at the resource boundary, because another resource always re-renders; PDF outlines are left alone, since their entries all share one href; and a failed visibility probe answers `true`, so a broken probe lands on the first entry of the next resource rather than stalling. `_lastNavigatedTocIndex` records the entry actually navigated to.
- **A locator names its chapter now, on a book whose chapters open with a back-to-contents link**: the webview's heading search only looked backwards from the reader's position, so in a chapter whose first element is a link back to the table of contents nothing preceded the position and the search fell through to the enclosing `section` or `body`. It handed back that element's `id` unchecked, and `Element.id` is an empty string when the attribute is absent, so the fragment shipped as `toc=` with nothing after it — a value no TOC entry can match. Every chapter of the reported book was built that way. The search now falls forward to the first following heading that carries an id, but only when no heading precedes the position at all. The section and body fallback requires a real id, and `toc=` is emitted only once a heading has resolved. A host identifying a chapter by that fragment was identifying nothing.
- **`isLocatorVisible` reports a visible range as visible**: it also required an `activeLocation` marker inside the target range, a marker only `setLocation` plants, so every locator the reader was merely showing answered `false`. The TODO above that line had said as much since the file was written. The conjunct is gone, leaving the range check the method's name and its own doc comment promise. A host that read the old answer was reading "is this the active TTS location and on screen", not "is this on screen".

### Documentation

- `docs/api-reference/reader-widget.md`, `flureadium-class.md` and `publication.md` state that a skip passes over entries already on the reader's page, so a tap always moves it.
- `docs/api-reference/locator.md` states the `toc=` contract under `fragments`: the fragment carries a heading id or is absent, never present with an empty value, so a host can read its presence as proof that a heading resolved.
- `docs/05-testing/integration-tests.md` has a "The chrome has to stay reachable" section: the example app's control bar grows with every button added to it, the toggle block is the last `Stack` child so it keeps winning the pointer, and a short-screen overlap reproduces by shrinking the emulator to CI's 682 dp app area.

### Example App

- `assets/pubs/frontmatter_toc.epub` is a new fixture in the reported book's shape: a cover carrying no TOC entry, six front-matter entries anchored inside one rendered page, then three chapters. An **Open Frontmatter** button opens it.
- The EPUB navigation groups moved from `integration_test/epub_test.dart` to `epub_navigation_test.dart`, with their shared wait helper in `integration_test/helpers/expect_eventually.dart`. The new case asserts href *and* progression after every skip, because a TOC index alone cannot show whether the reader moved.
- The `toggle-controls` block is the last child of the example's page `Stack`. The control bar has no height cap, and on a 682 dp screen it had grown tall enough to take the tap aimed at the toggle, so the tap suite could not put the chrome down.

## 0.17.1

### Bug Fixes

- **An Android control-panel layout other than the default survives activity recreation now**: `ControlPanelInfoType` read the Flutter spelling (`chapterTitle`) but wrote the Kotlin constant name (`CHAPTER_TITLE`), because the only function producing the wire spelling sat on the companion where an instance `toString()` call could never reach it. Android saved state writes the value with `?.toString()`, so a saved `chapterTitle` came back unparseable and the reader's `else -> STANDARD` fallback turned it into the default. After a rotation, a low-memory kill or process death, the media notification and lockscreen quietly reverted to publication title plus authors. The wire spelling is now the enum's own `toString()`, which fixes the TTS and audiobook paths together, and the unreachable companion function is gone.

### Documentation

- `docs/platform-specific/android.md` has a "Saved-State Restore" section: one provider whose bundle nests a child bundle per live navigator, nothing re-asks Dart for preferences on restore, and enums crossing the bundle use the spelling the method channel uses. It also names the split between the hand-written codecs, which fall back to a default on a string they cannot read, and the EPUB bundle's kotlinx encoding, which throws.

## 0.17.0

### Breaking changes

- **`ReadiumReaderWidget.loadingWidget` is gone.** It never rendered anything. The widget that drew it was removed in an earlier refactor and the parameter outlived it, so passing a loading widget and passing nothing produced the same blank platform view. There is no replacement parameter: a host that wants to cover the load stacks its own widget over the reader and drops it when `onReaderStatusChanged` reports `ready`. The reader widget's API reference has the recipe. Remove the argument from your call.
- **`rxdart` is no longer a dependency.** The plugin only pulled it in for a debug listener that logged locators and did nothing else, and that listener is gone. Host code that imported `package:rxdart/rxdart.dart` and got it transitively through flureadium now has to declare it: add `rxdart` to your own `pubspec.yaml`. Every `debounceTime` sample in the docs needs it.
- **`ReadiumReaderWidget.onTap` reports a position now, and three gesture parameters are gone.** `onTap` changes from `VoidCallback?` to `void Function(Offset position)?`, so your callback receives the tap point in logical pixels from the top-left of the platform view. `onGoLeft`, `onGoRight` and `onSwipe` are deleted; all three were declared and documented, and nothing ever called them. Edge and swipe paging are configured through `setNavigationConfig()` instead. Update your callback signature and drop the three arguments from your call.

### New Features

- **Content taps come from Readium now, on both platforms.** `onTap` used to be a parameter with nothing behind it. Android registers an `InputListener` on the Readium navigator (`NavigatorTapForwarder`), iOS registers a tap observer on the navigator's `InputObservable` (`ReaderTapObserver`). Both report the point in logical pixels from the top-left of the platform view, and neither consumes the event, so the listeners Readium registered behind them still run. In an EPUB, Readium tests the pointer against interactive elements before any observer sees it: a hyperlink or a footnote is followed and reported as nothing. What reaches `onTap` is a tap nothing else claimed, which is what makes toggling your own chrome on a single tap safe. That filter belongs to the WebView, so PDF and CBZ report every tap, link annotations included. The two platforms differ in one place, and it ships that way on purpose: on iOS a tap on a PDF internal link annotation reports a tap and follows the link, while on Android the same tap is reported and navigates nowhere. `docs/api-reference/reader-widget.md` covers the edge strips the native overlay claims, where `onTap` stays quiet.
- **`enableSwipeNavigation` switches PDF drag paging off on Android.** On Android the flag used to govern one thing only: whether a fling inside an edge strip the overlay had claimed turned a page. The docs promised it governed horizontal flings outright. `PdfNavigator` now hands the pdfium engine provider a listener, so `enableSwipeNavigation: false` reaches the PDF view's own `enableSwipe(false)`. Drag paging stops; taps, pinch-zoom and pan-while-zoomed are unaffected, because AndroidPdfViewer checks that flag in its drag and fling handlers and reports a tap unconditionally. The flag is read when the PDF view is built, so one that arrives while a PDF is on screen applies from the next rebuild (a background/foreground cycle or a reopen) rather than mid-document. EPUB and CBZ page through Readium's internal `R2WebView` and an androidx `ViewPager`; neither exposes a swipe toggle in Readium Kotlin 3.1.2, so there the flag still reaches no further than the edge strips.

### Bug Fixes

- **iOS stops turning pages in a band no host configured**: on a 393 pt iPhone with `enableEdgeTapNavigation` set to `false`, a single tap anywhere in 147.8 pt — 37.6% of the width — still turned a page. Two components claimed edge taps with two different widths, and only one of them read the preference: `EdgeTapInterceptView` absorbed `edgeTapAreaPoints` (44 pt by default) and Readium's `DirectionalNavigationAdapter` claimed `max(80, 0.3 × width)`, or 117.9 pt, ungated. Taps that landed between the two widths fell through the overlay to the adapter, which turned the page. The adapter is now built with an empty pointer policy, so the overlay is the only pointer edge owner on iOS and `enableEdgeTapNavigation` governs every edge tap. The adapter keeps its key observer, so arrow keys and the space bar still page. Android never had a second owner and is unaffected.
- **A tap near the edge of an EPUB reports as a content tap when edge tap is off**: the overlay claimed both edge zones whenever the EPUB was paginated, regardless of the preference, because that was the only way to keep the adapter from seeing those touches. With the adapter's pointers gone, the claim had no purpose left and swallowed the touch instead — `onTap` never fired within 44 pt of either edge. The overlay now intercepts only when it will act, matching what the PDF and image readers already did.
- **Android stops swallowing a tap in the edge strips when only swipe navigation is on**: `EdgeTapInterceptView` claimed a 44 dp strip whenever it held *either* an edge-tap or a swipe callback, and swipe navigation defaults to enabled. So `enableEdgeTapNavigation: false` left the overlay claiming both strips and then dropping the touch on a null edge-tap callback: no page turn, and `onTap` never fired in either strip. The claim predicate reads the edge-tap callbacks alone now, so the tap rule is the same on both platforms. What changes about swiping is narrower than it sounds: a fling reaches the plugin's overlay only inside a strip the edge-tap gate claimed, so with edge taps off the overlay no longer pages on a fling — but a paginated EPUB keeps turning pages on a horizontal drag, because Readium's own `R2WebView` handles that and exposes no toggle. Android CBZ has no overlay at all, so nothing there changed either way.
- **Decorations sent from Dart now reach both platforms**: `applyDecorations` sends `{id, locator, style: {style, tint}}` per decoration, and neither native side read that. Android looked for a `decorationId` key nothing sends and cast `locator` to a `String` when it arrives as a map, so `decorationFromMap` returned null for every decoration and `mapNotNull` dropped it — a highlight never appeared and nothing reported why. iOS force-cast the same list to `[String]`, which no genuine payload satisfies. Both decoders now read the payload Dart actually sends, and a decoration that cannot be decoded raises a `PlatformException` naming the decoration instead of vanishing. The wire format is written down in `docs/api-reference/decorations.md`.
- **Android TTS can no longer restore the language as the literal string "null"**: `FlutterTtsPreferences.fromJSON` read the language with `optString("language", null)`. On a device that returns the four characters `null` when the key holds a JSON null, so a restored preference could ask the synthesizer for a language named "null". The read now asks `isNull` first, which is the one accessor that answers the same way in the JVM test suite and on a device.
- **iOS survives a `setNavigationConfig` call whose argument is not a map**: the decode force-cast `call.arguments`, so a non-dictionary argument trapped the host process. It casts optionally now and yields an all-nil config. No production path sends that shape; a trap on a malformed call is still worth removing.
- **iOS audio playback failures reach the listener on the main actor**: both `handlePlaybackFailure` call sites were invoked from a notification callback off the main actor, which the compiler flagged as an error under the Swift 6 language mode. They now hop through `Task { @MainActor in }`, so the listener is notified one hop later than before.
- **A `setNavigationConfig()` call made before the reader is on screen takes effect now**: it used to do nothing at all, on either layer, and report nothing. Dart stored the config on the platform and forwarded it to a reader that had not registered yet, and nothing ever read the stored value again; on Android the reader forwarded it to a navigator that did not exist yet, so the call ended on a null check. The config is now replayed once when the reader registers, and once more when the navigator is built, so a host can configure navigation right after `openPublication()` instead of waiting for `onReady` and a first locator.

### Example App

- The example's Android build now pins Kotlin 2.2.20, matching the plugin module (`android/build.gradle`, `ext.kotlin_version`). It sat on 2.1.20, and every build warned that Flutter support for that version was about to be dropped.
- The Gradle wrapper moves from 8.13 to 8.14.5, in two steps. 8.14 is the minimum Flutter asks for and was the second half of the Kotlin warning pair; both warnings are gone. 8.14.5 came later, because 8.14.0 skips an exception's own message whenever the Problems API has a problem attached, so a failing task printed `What went wrong:` with nothing under it. That is how `:app:validateSigningDebug` failed on CI, reporting no cause at all. Fixed upstream in 8.14.1. AGP stays at 8.13.2; its declared minimum is Gradle 8.13, so either version satisfies it.
- `example/android/gradle.properties` sets `org.gradle.logging.stacktrace=all`. Flutter runs Gradle with `-q`, and a task that fails with an empty cause then prints the `What went wrong:` heading and nothing else. The exception chain always prints now, so the next failure of that shape carries its own message.
- The `native`, `network` and `web` integration-test tags are declared in `example/dart_test.yaml`. Device runs used to print a warning naming all 26 tagged tests because the tags were used but never declared. Nothing about which tests run changed: declaring a tag does not select or deselect anything, so the `--exclude-tags "native || network"` selection Android CI uses behaves exactly as before.

### Documentation

- `docs/api-reference/decorations.md` documents the method-channel wire format for `applyDecorations`, with the key table and the failure contract. Its "Rejected Decorations" section used to say decorations were dropped instead of drawn, which stopped being true once both decoders started reporting failures, and its `tint` example showed `rgba(255, 255, 0, 1.0)`, which no layer produces — `ReaderDecorationStyle.toJson()` emits `#RRGGBB` or `#AARRGGBB`.
- `docs/platform-specific/android.md` describes how Android decodes a decoration payload, including that an unreadable one now fails the whole call, and that an unrecognised style name still falls back to a highlight.
- `docs/platform-specific/ios.md` and `docs/architecture/overview.md` record the main-actor hop the audio navigator's failure callbacks take.
- `docs/05-testing/native-unit-tests.md` warns that the Kotlin compile tasks cache like the test task, so an up-to-date build prints no warnings at all, and explains how to see them. `docs/05-testing/all-tests.md` says which tests may stay skipped.
- The `onTap` edge-strip rule is written down once for both platforms in `docs/api-reference/reader-widget.md` and in the parameter's own dartdoc. They used to say the strips are absorbed whether or not edge-tap navigation is enabled, then said it differently for each platform; the iOS and Android fixes above made both versions false. `docs/platform-specific/android.md` describes the overlay's claim as gated on edge-tap navigation alone. `docs/guides/preferences.md` records that `edgeTapAreaPoints` is the only edge width left on iOS, that both platforms read the same three navigation keys, and how far `enableSwipeNavigation` reaches for each format.
- `docs/guides/epub-reading.md` drops two recipes that put a gesture layer over the reader: "Tap Zones", which stacked two `GestureDetector`s to page it, and the `onHorizontalDragEnd` swipe handler. It shows the single `onTap` callback and the `setNavigationConfig()` flags instead. It and `docs/getting-started/quick-start.md` now say that a tap on a link never reaches `onTap`.
- `docs/platform-specific/android.md`'s `setNavigationConfig` sample called the config `NavigationConfig`. The class is `ReaderNavigationConfig`, so the snippet did not compile.
- `docs/api-reference/reader-widget.md` says that one open can report the same page twice. On Android the first locator comes from Readium's initial position for the resource and carries no `position` or `totalProgression`; a second follows within roughly 200 ms with both fields filled in. `href` and `progression` are the same in both, so neither is a page turn. Read `onLocatorChanged` as "here is the current position" rather than "the reader moved", and compare `href` and `progression` if you need to know it went somewhere.
- `docs/getting-started/installation.md` records that CI runs the same Flutter version contributors do: 3.44.7, pinned on every `subosito/flutter-action` step rather than tracked from the stable channel.
- `docs/05-testing/native-unit-tests.md` raises the Java floor it documents from 17 to 21, and says why: the Android build compiles to `JvmTarget.JVM_18` and javac emits no target above its own release, so 17 cannot build it, while JDK 18 is the one release carrying JDK-8287073 with no fix available.
- `docs/guides/audiobook-playback.md`'s auto-save snippet calls `debounceTime` and now says where that comes from. `rxdart` stopped being a flureadium dependency in this release, and the two other pages with debounce samples already carried the note; a host copying this one got an undefined method.

### Testing

- The decoration decoders have unit coverage on both platforms: every guard branch on iOS, including a locator sent as a JSON string, which is the shape iOS used to require; and nine Robolectric cases on Android, two of which are positive controls, one specifically pinning that a nested locator's `progression` survives the `JSONObject(Map)` conversion.
- `example/integration_test/decoration_contract_test.dart` asserts the contract from Dart on a device: an accepted decoration, a malformed one that must surface a `PlatformException` naming it, and that the example's Highlight button leaves the reader where it was. The case it replaces tapped Highlight and then checked the reader widget still existed, which could not fail.
- Two tests stopped being skipped. The platform-interface locator-stream test was disabled as flaky and was deterministically dead: its mock pushed a Dart object where the getter decodes a JSON string. The three wakelock tests asserted only that methods exist; they are now four cases that drive the mixin's 30-minute timer through a recording platform double, and each one was checked by mutating the mixin.
- Seven Kotlin main-source warnings, fourteen coroutine opt-in warnings and five first-party Swift warnings are gone. The two that remain are tracked with the files they need decomposed first.
- Two assertions that could not fail are corrected. `reader_widget_test.dart` handed `Future.then` an `onError: (Object e) => outcome = e`, an arrow returning the assignment's value where the handler has to return the future's own type, so neither error case recorded anything; both are blocks now. `localized_string_test.dart` asserted `json.containsKey(null)` was false against a `Map<String, String>`, which cannot hold a null key — it checks the whole key set instead, which is what "the null language became `und`, and nothing else appeared with it" actually means.
- `example/integration_test/edge_strip_tap_test.dart` stops reading a locator count as a page turn. One Android open reports the same page twice, for the reason above, so the count rose while the reader stood still. The no-turn assertion compares `href` and `progression` now, through a single predicate shared with the turn detector so the two cannot disagree about what counts as movement.
- `scripts/run_native_unit_tests.sh` needs JDK 21 rather than 17, matching what the Android build can actually be compiled with.

### Dependencies

- Requires `flureadium_platform_interface` ^0.10.2, raised from ^0.10.0. No new interface API is used; the old constraint was simply wrong about what this plugin needs. It let pub resolve against `0.10.0`, which predates that package's fix for reading-order hrefs gaining a leading slash — and `docs/api-reference/publication.md` promises a publication href is comparable with a locator href, which is only true from `0.10.1` on. The floor now names a version where the documentation holds.

### Continuous integration

- Flutter is pinned to 3.44.7 on all 14 `subosito/flutter-action` steps, across the six workflow files. They tracked `channel: stable` with no version, which meant a Flutter release could turn every required check red on a branch nobody had touched — and one did. Dart 3.13 reserves `final` on normal parameters for primary constructors, so the format check rejected 107 declarations, and `flutter drive -d chrome` hangs on 3.47.1. Moving the toolchain is a reviewed commit that edits those 14 lines now, not a surprise on the next run.
- The format job resolves packages before it checks anything. `dart format` reads a file's language version from the surrounding package config and falls back to the SDK's newest when there is none, so with no `pub get` it read language-3.8 sources as 3.13 — the other half of the `final` parameter failure.
- The three Android jobs build on JDK 21 instead of 18. `java-version: '18'` resolves to 18.0.2 and nothing newer, because JDK 18 ended there, and that release carries JDK-8287073 unfixed: on a cgroup v2 host `CgroupSubsystemFactory` looks up the memory controller by name and dereferences the result, and kernels from 6.12 on stopped listing a memory row in `/proc/cgroups`. The runner image crossed that line between the last green build and this branch, so every Android job died at `:app:validateSigningDebug` — the task that creates the debug keystore, which loads AGP's `JvmWideVariable`, whose static initializer asks for the `OperatingSystemMXBean`. OpenJDK fixed it in 19 and backported to 17.0.5 and 11.0.17, never to 18.x, and 17 cannot compile `JvmTarget.JVM_18`. That leaves 21.
- `.github/scripts/workflow_jdk_pin_test.sh` keeps the pin from drifting back. It checks every `java-version` against the 21 floor, that a workflow using `setup-java` pins a version at all, and that the floor still clears the `JvmTarget` the Gradle build asks for — so raising the bytecode target without raising the pin fails here instead of on a runner. It runs beside the other workflow checks in the widget-test job.

## 0.16.6

### Bug Fixes

- **Android engine teardown can no longer cancel the publication close it starts**: `ReadiumReader.detach()` launched `closePublication()` on `mainScope` and then, as its last three statements, cancelled `jobs` and `mainScope`'s children. Teardown was published as a child of the scope the same function cancels. Nothing broke from it, and the reason is narrow: `detach()` nulls the epub, image and pdf navigators before the launch, and those three are the ones whose `release()` suspends on a plain `withContext(Dispatchers.Main)`. What was left were the three time-based navigators — `ttsNavigator`, `audiobookNavigator` and `syncAudiobookNavigator`, the last of which extends `AudiobookNavigator` without overriding `release()`, so two bodies between them — and both switch with `withContext(Dispatchers.Main.immediate)`, which does not dispatch when it is already on the main thread. On the platform thread the close therefore ran inline and finished before the cancel below it was reached. That held only while every `release()` left on the path kept not suspending, and only while the three closes kept running first. The cancel now runs before any teardown statement: the launch is issued after it, and `cancelChildren()` cancels the children the scope has while leaving its `SupervisorJob` active, so the work started afterwards still runs.

### Documentation

- `docs/platform-specific/android.md` stated that the launched `closePublication()` "suspends inside each navigator's `release()`, and the `cancelChildren()` at the end of `detach()` cancels it there". It did not, and that sentence is what the bug was originally filed on. The teardown-ownership section now gives the order `detach()` uses, and says which navigators had to be closed first for the old order to survive.

### Testing

- `ReadiumReaderDetachOrderingTest` pins both halves of the order. One case checks that the launched close survives `detach()` and runs to completion. The other checks that the cancel block has already finished when the first teardown statement runs, read from inside a stubbed `EpubNavigator.dispose()`. The second case exists because the first one passes with the cancel sitting between `pdfClose()` and the launch, which is neither the old order nor the new one.
- `ReadiumReader.mainScope` is a `var` now. It resolves `Dispatchers.Main.immediate` once, when the object initialises, and the singleton outlives every test class in a JVM run, so whichever class touches it first fixes that dispatcher for the whole run and `Dispatchers.setMain` cannot reach it afterwards. The first version of the ordering test went red on its own and green in the full suite against the broken order. It swaps the whole scope by reflection instead, and a `val` compiles to a static final field that reflection cannot write.
- The comment above the three synchronous-close cases in `ReadiumReaderTeardownOwnershipTest` repeated the same claim the docs made.
- The `jobs` list had no coverage anywhere in the suite, so the cancel-and-clear half of `detach()` was unpinned. Both new cases were checked by mutation: reverting the statement each defends is what turns it red.

### Continuous integration

- The example's lockfile stayed on 0.16.4 through the 0.16.5 bump. Every suite the runner drives through the example resolves with `--enforce-lockfile`, so the example unit tests and the entire integration run failed on "Unable to satisfy `pubspec.yaml` using `pubspec.lock`" before a single test executed. It moves with `pubspec.yaml` now, alongside the three install snippets that were added to that list one release ago.

## 0.16.5

### Bug Fixes

- **An Android reader failure no longer kills the app**: any exception in a reader coroutine took the process down with a `FATAL EXCEPTION` and no signal to Dart — no error event, no `error` status, nothing thrown into your code. The observed one was mounting the reader over a publication that had been closed, which throws `Publication not opened cannot enable epub`. Each reader scope was a `SupervisorJob` scope with no `CoroutineExceptionHandler`, and a supervisor's direct children are root coroutines, so the failure went straight to Android's `KillApplicationHandler`. The widget scope, the `ReadiumReader` singleton scope and every navigator scope now carry a handler that reports the failure as reader status `error` plus an error event with `code: "ReaderFailure"`, the exception message and the native stack trace. A widget only reports while it still owns the reader registration, so a stale platform view cannot flip the reader that replaced it to `error`, and cancellation reports nothing, so `dispose()` and `detach()` stay silent.
- **A failed reader method call answers Dart**: `onMethodCall` dispatched every branch on a coroutine with no catch, and several branches parse their payload with unguarded casts. A malformed call threw, nothing was replied, and the Dart future never completed. It now replies `result.error` with the exception class, message and stack trace — the same shape the publication channel returns — and rethrows `CancellationException` so a call torn down by `dispose()` does not surface as a phantom `PlatformException`.
- **An error reported before Dart subscribes still arrives**: the reader widget reports a failed enable from `init`, which runs inside the platform-view `create` call, so the error left native before Flutter replied to Dart and before a host could subscribe from `onReady`. `ErrorEventChannel` sent it into a null sink and dropped it. It now holds pending errors and replays them in order to the first subscriber, keeping the first eight because the earliest failure explains the ones after it, and clears them on dispose so a finished session cannot surface on a later subscription.
- **A rejected publication leaves no is-ready channel behind**: `epubEnable`, `imageEnable` and `pdfEnable` disposed and recreated `EpubIsReadyEventChannel` before checking whether the publication could host the navigator, so a rejected publication left a live channel registered for a reader that never came up. Invisible while the process died; now the guard runs first.
- **An event-channel failure no longer kills the app either**: the sweep above covered the reader scopes and stopped there. Every event channel sends through one shared scope in `EventChannelWrapper`, and that scope had no handler, so a send that threw reached the same kill handler by the same route. It logs now instead of reporting: a report is itself sent on the reader-status and error channels, so a channel that reported its own failure would send again, fail again, and never stop — and because the send is dispatched rather than nested, that loop spins forever rather than overflowing the stack. The process survives and the throwable is in logcat.
- **A failed rewind or forward from the car or the notification is reported**: both transport commands ran their work with `async` in a scope created on the spot, and nobody ever read the `Deferred`. A failure was neither reported nor logged — it sat in a `Deferred` until it was collected. They share one scope with the reader failure handler now and use `launch`. The session is still answered immediately; these commands are fire-and-forget by design.
- **The media facade and the two reader fragments report their failures**: `PluginMediaServiceFacade` and the EPUB and PDF fragment scopes were built without a handler, so a throw in any of them still took the process down. A dead scope on `PluginMediaService.Session` — created with the session, cancelled on close, never launched into — was removed rather than given one.
- **iOS answers Dart when `audioEnable` throws**: the call runs its work in a detached `Task` whose `Task<Void, Error>` is discarded, so a throw would be stored there and dropped, leaving the Dart future uncompleted with no error event. Neither `try` in that body can throw today — `FlutterAudioPreferences.init(fromMap:)` is declared `throws` but reads every value with a default, and both conforming navigators declare `initNavigator()` as `async -> Void` — but the protocol declares it `async throws`, so the call site has to answer for it. A throw now answers with a `ReaderFailure` `FlutterError` and reports on `onErrorEvent`; `CancellationError` stays silent, matching Android's torn-down-call rule.

### Documentation

- `docs/troubleshooting.md` gains the reader-failure entry: the fatal exception, why a supervisor child reaches the kill handler, and what the fix reports instead.
- `docs/guides/error-handling.md` documents what a native reader failure delivers on `onErrorEvent`, that the same failure sets reader status `error`, that an error reported during platform-view creation is held for the first subscriber, and the limitation that a failed enable leaves the widget mounted with no navigator and will not recover on its own.
- `docs/api-reference/streams-events.md` said Android never emits the `error` status and never emits error events automatically. Both were false after this release; the status table and the Android paragraph now describe what is emitted and how errors are held for a late subscriber.
- `docs/platform-specific/android.md` said `ReaderStatusEventChannel` is the only channel that buffers. It now covers all three shapes — latest status, first eight errors, no locators — and its `Coroutine Failure Reporting` section states the rule the code now enforces: every scope reports, or carries a written reason why it does not.
- `docs/guides/error-handling.md` and `docs/api-reference/streams-events.md` introduced `ReaderFailure` as an Android code. iOS sends it too, from a failed `audioEnable`, and both now say so; `docs/platform-specific/ios.md` describes the call's answer-or-report contract.
- `docs/05-testing/integration-tests.md` documents the `Reader failure` integration group and the two example-app buttons it needs to force a failure no asset produces on its own.
- The three install snippets (`docs/getting-started/installation.md`, `README.md`, `flureadium/README.md`) read `^0.16.3`; the 0.16.4 release commit bumped `pubspec.yaml` without them. They move to `^0.16.5` with `pubspec.yaml` in one commit this time, so the two cannot drift again.

### Testing

- Four new Android JVM classes: `ErrorEventChannelTest` (pending delivery, ordering, the cap, drain-not-replay, dispose), `ReaderCoroutineFailureTest` (what the handler reports and when it stays silent), `ReadiumReaderWidgetEnableFailureTest` (a failed enable reports instead of reaching the default uncaught handler, and a stale widget stays quiet), and `ReadiumReaderScopeHandlerTest` plus `ReadiumReaderEnableGuardTest` (both remaining scopes carry a reporting handler; a rejected publication leaves no channel).
- `ReadiumReaderWidgetAudioChannelTest` gained the method-channel failure cases, including one that cancels a call mid-flight and checks nothing is answered or reported.
- Three test classes carried their own copy of the same Robolectric harness. They share `ReaderTestHarness.kt` now, alongside the `ReadiumReaderFields.kt` reflection helper.
- Three more Android JVM classes: `CoroutineScopeHandlerConventionTest` scans every scope construction under `src/main/kotlin` and fails the build unless it carries a handler or a `// no-handler:` reason, which is what stops the next bare scope; `EventChannelFailureTest` covers a failed send surviving, staying silent and not being retried; `PluginLibrarySessionCallbackFailureTest` covers both transport directions.
- `ReadiumReaderScopeHandlerTest` gained the facade and the two fragment scopes. The convention test reads source text, so it cannot tell a working handler from a stub; these cases pull the installed handler out of each scope and invoke it.
- Every new case was checked by mutation: the production line it defends was reverted, and only that case went red. That is how the forward-command gap was found — `commandScope.async` still passes the convention test, because the scope does carry a handler and `async` simply never routes to it.
- `FlureadiumPluginAudioEnableTests` is the first Swift coverage of the audio call answering exactly once. Adding it surfaced `FlureadiumPluginCarRefreshTests`, which had been sitting in `RunnerTests/` unregistered in `project.pbxproj` since the CarPlay refresh feature landed, so it had never compiled and never run. Both run now, and both pass.
- `example/integration_test/error_handling_test.dart` gained an untagged `Reader failure` group: it closes the publication natively, remounts the reader over it, waits for `reader-status: error`, and reopens the book so the files after it still have a working reader. Making the assertion at all is the proof — the failure used to take the process down and every later test reported "did not complete".

## 0.16.4

### Bug Fixes

- **Assigning a new publication to a mounted reader rebuilds the native view**: opening a second book into a reader that was already on screen left the platform view bound to the publication the plugin had just closed. The reader kept showing the old book, and every navigation call reached a navigator native had already released, so it did nothing and reported nothing. Flutter only recreates a platform view when the element is replaced, and nothing forced that: `_PlatformViewLinkState.didUpdateWidget` recreates the view only when `viewType` changes, which is a constant here, and creation parameters are never re-sent to a live view. The view is now keyed by a generation counter that `didUpdateWidget` bumps whenever the widget receives a publication that is not the same instance as the previous one. The check is instance identity rather than equality, because `Publication` compares by full manifest value, so reopening the same file produces an object that is equal to the one native has already released. A swap now tears down the old channel, registration, reading position and remembered chapter before the replacement view is built, and `onReady` fires again for the new view. A `getLocatorFragments` call that was waiting when the swap happened used to wait forever on a completer nothing would ever complete; it returns `null` instead.
- **A replaced reader view stops reporting**: the outgoing view's method-call handler used to stay installed for the length of the native dispose round-trip, because `ReadiumReaderChannel.dispose()` only drops the handler after that call returns. A page change delivered in that window ran against whatever the widget held at the time, so after a swap it could write the previous book's position into the new reader and fire `onLocatorChanged` with it — which a host would store as the position of the book now on screen. The handler is detached before the round-trip starts. A skip that was waiting on native navigation when the swap happened no longer writes its chapter index back either.
- **iOS mounts a reader with no navigator for an audio-only publication**: an audiobook built the full EPUB stack — a `WKWebView` pagination host, an HTTP server route, a preload pass — for content that has nothing to render. Nothing crashed, which is why it went unnoticed, but readiness never arrived: an audio publication has no page to report, and the EPUB view only reports `ready` after a first `locationDidChange`. A host waiting on that waited forever. `readerViewKind(for:)` now checks `conformsTo(.audiobook)` after the PDF and image checks and routes to a new `AudioReaderView`, which builds no navigator and reports `ready` from `init`. This is what Android's `ReadiumReaderWidget` has done since it could host an audiobook. Media-overlay EPUBs are unaffected: they declare the audiobook profile over an HTML reading order, and the check is ordered so they stay on the EPUB navigator.
- **A closing reader view no longer ends the host's event streams on iOS**: `reader-status` and `text-locator` were owned per reader view. Flutter builds a replacement platform view before disposing the one it replaces, so the outgoing view's `dispose` end-streamed a channel the incoming view already owned — and because `MethodChannelFlureadium` memoizes the Dart stream, every status and locator after that was lost for the rest of the session. Both channels now belong to `FlureadiumPlugin`, which is where the `error` channel already lived. A view still reports its own `closed`; it just stops closing the channel underneath it. Affects EPUB and image readers, not only audio.
- **iOS delivers a reader status sent before Dart can subscribe**: a reader view reports `loading` from `init`, which runs while the platform view is still being created — before Flutter replies to Dart, so before a host can subscribe from `ReadiumReaderWidget.onReady`. That status went into a nil sink and was dropped, and for an audio publication so did the `ready` that follows it. `ReaderStatusEventStream` holds the most recent status while nobody is listening and delivers it once when the first subscriber attaches. Only the latest is held, and a status already delivered is never replayed. Matches `ReaderStatusEventChannel` on Android.
- **The Android reader-status channel drops its buffered status when disposed**: the held status outlived disposal, so a stale value could reach a later subscriber. Harmless in practice because `ReadiumReader.attach` replaces the whole instance, but it was a trap for anyone reusing one.

### Refactoring

- Chapter-skip navigation moved out of `reader_widget.dart` into `TocSkipNavigationMixin`. `skipToNext` and `skipToPrevious` were 148 lines of near-identical code inside a widget whose job is hosting the platform view, and they differed in three places: the decision function, the last-match flag, and the log label. The shared table-of-contents index lookup they both carried is now `resolveCurrentTocIndex` in `toc_matcher.dart`, alongside `tocHrefWithFragment`. `reader_widget.dart` went from 385 to 264 code lines.
- Removed `wasDestroyed` from the reader widget. It was assigned during disposal and never read.

### Testing

- Widget tests for the swap: a different publication replaces the view element, the same instance does not, a swap clears the registered reader widget, and an in-flight `getLocatorFragments` resolves to `null`.
- Nine behaviour tests for `TocSkipNavigationMixin`, covering empty tables of contents, missing locators, boundaries at both ends, a null channel, and the remembered index that carries a skip when the reported locator has not caught up yet.
- Integration test in `example/integration_test/cbz_test.dart` opens a CBZ into a live EPUB reader and waits for the reader to report the first page. Before the fix that poll timed out.
- 30 new XCTest cases on iOS (425 total): the reader-status replay buffer, the audio host's channel contract and both its initialisers, reader-view routing with its precedence rules, and plugin ownership of the shared streams.
- Android gained tests for the audio host's method-channel answers, which had none — the answers were correct by accident, through null guards on a navigator that is never built, rather than by design. Reader-kind routing is now also checked against real Readium manifests instead of a stubbed `conformsTo`, which is what pins the media-overlay case.
- The text-locator stream had no coverage anywhere. `example/integration_test/text_locator_test.dart` asserts a page turn reaches Dart, that the stream follows a publication swap, and that a swap to audio leaves no locator behind.

### Continuous integration

- Android CI selects integration tests by tag (`--exclude-tags "native || network"`) instead of importing a hand-picked list of files into a separate aggregator. A file left out of that list ran nowhere and said nothing about it, which is how the audiobook suite went unrun on Android for months. The `@Tags` annotations that looked like they handled this never took effect: a library-level annotation is ignored once an aggregator imports the file rather than running it. Tags are applied per test now, and the two audio-only host tests that need no player moved to their own untagged file so they run on the emulator.

## 0.16.3

### Bug Fixes

- **Android reader survives its platform view being replaced**: opening a second book into a reader the host app keys per publication left the new reader on its loading widget for good. No page turns, no locator updates, no error. Flutter builds the replacement platform view before it disposes the one it replaces, so native sees create-new then dispose-old, and the stale widget's `dispose()` still ran `pdfClose()`, `imageClose()` or `epubClose()` — each of which opened with an unconditional `currentReaderWidget = null`. Every native-to-Dart reader callback routes through that field, so clearing it cut the live widget off: `onPageChanged`, `onPageLoaded`, `onExternalLinkActivated` and `onVisualReaderIsReady` all no-opped on `?.`. Dart flips its ready flag inside the `onPageChanged` handler, which is why the loading widget never went away. 0.16.2 gave the audio branch an identity guard for the same hazard; that guard now covers the whole shared teardown. `dispose()` emits `"closed"`, clears the registration and closes the navigator only while `ReadiumReader.currentReaderWidget === this`, and the three close functions no longer touch the registration — they release the navigator and the is-ready channel their matching `*Enable` created, which is what their names promise. A stale widget still releases its own method-call handler, coroutine scope and view group.
- **Android engine teardown releases the reader itself**: `detach()` disposed four of the five event channels and left `isReadyEventChannel` alive, and it never released the visual navigators. Both omissions were masked by the widget dispose that used to follow, which ran a close function unconditionally. That dispose is identity-guarded now, and `detach()` clears the widget registration before it arrives, so nothing would have been released: the navigator, its fragment and the closed publication stayed reachable from the process-scoped `ReadiumReader` for the life of the process, and the next engine's `epubEnable` would have attached to the dead navigator instead of building a fresh one. `closePublication()` cannot cover it either — it suspends inside each navigator's `release()`, and the `cancelChildren()` at the end of `detach()` cancels it there. `detach()` now calls `epubClose()`, `imageClose()` and `pdfClose()` up front, on the synchronous path.
- **iOS Swift package declares the Flutter framework**: `ios/flureadium/Package.swift` listed only the Readium toolkit and PromiseKit, so `flutter build` warned that the plugin "has a Package.swift for ios but is missing a dependency on FlutterFramework". Flutter 3.44 made that dependency part of the plugin template and builds only kept working because the tool injects it at build time, which it describes as a stopgap for plugins that have not adopted it yet. The manifest now declares `FlutterFramework` as a package and as a target product, matching what `flutter create --template=plugin` emits. CocoaPods builds are unaffected.

### Documentation

- `docs/platform-specific/android.md` gains a `Teardown ownership` section under `Platform View`: why native sees create-before-dispose, what the identity guard covers, which teardown is publication-scoped rather than widget-scoped, and why `detach()` has to release the navigators itself. Its platform-view factory snippet showed a `ReadiumReaderView` class that does not exist, and now matches `ReadiumReaderViewFactory.kt`.
- `docs/api-reference/streams-events.md` said the Android `closed` status comes from `ReadiumReaderWidget.dispose()`. It comes from the widget that still owns the registration; a stale platform view stays quiet.
- `docs/platform-specific/ios.md` said the plugin keeps two module-level reader-view globals. There are three, and `ImageReaderView.swift` handles its own the same way the EPUB and PDF views do. The cross-reference to Android's identity guard pointed at a line number the guard has since moved off.

### Testing

- Android JVM (Robolectric): `epubClose()`, `imageClose()` and `pdfClose()` release their navigator and leave the widget registration alone; a stale widget's `dispose()` keeps a newer widget's registration, navigator and is-ready channel across EPUB, image and PDF hosts; the widget that still owns the registration performs the full teardown and emits `"closed"`; `detach()` disposes the is-ready channel and every visual navigator.
- Those tests mount a reader of any kind on the JVM by pre-seeding the navigator field, which short-circuits the navigator construction inside each `*Enable`. No device or emulator is involved.
- Seven test classes each carried a byte-identical private copy of the reflection helper that reaches `ReadiumReader`'s private fields. They share one `ReadiumReaderFields.kt` now.
- Two integration assertions waited on a state change with a fixed sleep instead of a poll, and the shorter of the two started failing on Android: `tts off hides sentence nav buttons` gave the button three seconds to disappear, but it only clears once `stop()` resolves, and that call races the `play()` still in flight from enabling TTS a moment earlier. Both now poll, the way the rest of the file already waits. iOS gets the time back — it stops sleeping through eight seconds it never needed. The fixed pumps that assert something *stays* true are left alone; polling would let those pass early and prove nothing.

## 0.16.2

### Bug Fixes

- **Android reader widget hosts an audiobook instead of killing the app**: mounting `ReadiumReaderWidget` over an audiobook took the process down with `FATAL EXCEPTION: Publication is not an EPUB, cannot enable epub navigator`. `PublicationReaderKind` had three members (`EPUB`, `PDF`, `IMAGE`) and used `EPUB` as its catch-all, so an audiobook was classified as an EPUB, the widget had no audio-only host to dispatch to, and `epubEnable`'s own conformance guard then rejected the publication the classifier had handed it. The throw happened in a coroutine with no supervisor, so it killed the process rather than surfacing on the error channel. There is now an `AUDIO` kind, matched by `conformsTo(Publication.Profile.AUDIOBOOK)` and checked after PDF and image so the existing precedence and the media-overlay EPUB path are untouched, and the widget mounts an audiobook with no visual navigator at all. A host app can open an audiobook as the reader's first publication, which previously required booting an EPUB and swapping.
- **Android reader status reaches a subscriber that arrives late**: `ReadiumReaderWidget.init` runs inside the platform-view `create` call, so the statuses it sends leave native before Flutter replies to Dart and before a host app can subscribe from `ReadiumReaderWidget.onReady`. `ReaderStatusEventChannel.sendEvent` wrote to an `eventSink` that only exists once Dart has subscribed, so those statuses went nowhere. EPUB, PDF, and image hosts were unaffected in practice, because their `"ready"` arrives later from `onVisualReaderIsReady()`; an audio host has no later source, so a host app that hides its spinner on `ready` would have waited forever. The channel now holds the most recent status while nobody is listening and delivers it when the first subscriber arrives. Only the latest is held, since status is a state rather than a log, and a status already delivered is never replayed to a later subscriber.
- **Android reader kind is fixed for the widget's lifetime**: the widget derived its kind from `ReadiumReader.currentPublication` on every access, so opening a publication of another kind under a live platform view could flip the kind, send `dispose()` down the wrong teardown path, and leak the navigator and the is-ready channel the widget had actually enabled. The kind is now captured when the platform view is created. An audio host's `dispose()` also clears `ReadiumReader.currentReaderWidget` only while it is still the registered widget, so a stale teardown cannot wipe a newer widget's registration.

### Documentation

- **Android reader kinds written down**: `docs/platform-specific/android.md` gains a `Reader Kind` section covering the PDF, image, audio, and EPUB precedence and what each kind mounts, and states the reader-status lifecycle including the statuses held for a late first subscriber. `docs/api-reference/streams-events.md` records the same subscription timing next to `onReaderStatusChanged` and no longer claims Android's `ready` comes only from `onVisualReaderIsReady()`.
- **Audiobook integration-test boot corrected**: `docs/05-testing/integration-tests.md` said an audiobook has to ride on a host EPUB. It now describes the direct boot, scopes the audio-only host to Android (iOS resolves an audiobook to its EPUB reader view and builds a navigator that renders nothing), and says why the audiobook group keeps `openAfterColdBoot` and which runs actually exercise the cold boot.

### Testing

- Android JVM (Robolectric): an audio-only publication mounts the widget with no EPUB navigator machinery, reports `loading` then `ready`, clears its own registration on dispose, and leaves a newer widget's registration alone.
- Android JVM: `PublicationReaderKind` classifies an audiobook as `AUDIO`, and PDF, DIVINA, bitmap, and media-overlay EPUB publications keep their previous kinds.
- Android JVM: `ReaderStatusEventChannel` delivers a status sent before the first subscriber, keeps only the latest while unsubscribed, delivers directly while subscribed, and does not replay to a second subscriber.
- The audiobook integration group boots `assets/pubs/38533.audiobook` directly rather than booting `moby_dick.epub` and opening the audiobook over it, which drops an EPUB load and navigator mount from every run and exercises the fix end to end. Its end-of-book test reuses the publication the group already loaded instead of extracting and parsing the manifest a second time.
- The audiobook and CBZ suites share one `extractAsset` helper instead of a private copy each, and it now gives every call its own temp directory: the old name was the current millisecond, so two extractions inside one millisecond returned the same path and the second write truncated the file the first caller had opened. `example/test/extract_asset_test.dart` covers both guarantees.

## 0.16.1

### Bug Fixes

- **Android application reference survives a UI-less engine**: `ReadiumReader.application` threw `IllegalStateException` in an engine with no Activity, because only `attach(activity, ...)` ever seeded it. An Android Auto car engine browsing the library therefore lost EPUB read-aloud. The reference is now seeded from the plugin binding's application context at engine attach, and `detach()` no longer clears it: it is process-scoped and outlives every engine, so a host running a UI engine and a car engine side by side keeps resolving it. The Activity-scoped event channels are unchanged and still require `attach()`.
- **iOS TTS voice query no longer throws without a session**: `ttsGetAvailableVoices()` returned a `TTSError` on iOS when no TTS session was installed, while Android returned an empty list and Web queried the browser directly. A voice query that raced a TTS teardown therefore crashed on iOS only. iOS now returns an empty list, matching Android. On iOS, `ttsSetVoice()` and `ttsSetPreferences()` still fail without a session, since they mutate one.
- **Android crash when a publication closes during a read**: closing a publication while the image navigator was still loading a page killed the app. Closing the publication closes the backing `ZipFile`, but cancellation is cooperative, so a read already inside `withContext(Dispatchers.IO)` runs on and reaches the closed container. `java.util.zip` reports that in two ways depending on how far the read had got: `ZipFile.ensureOpen` throws `IllegalStateException("zip file closed")` before the entry stream opens, and once the read is streaming `Inflater.ensureOpen` throws `NullPointerException("Inflater has been closed")`. readium 3.1.2 catches only `ZipException` and `IOException` there, so neither is expressed through the `Try<ByteArray, ReadError>` its `read()` declares, and they land in a readium fragment whose coroutine context carries no `Job`: no parent, no handler, and Android takes the process down. Reads against a closed container now report `ReadError.Access`, which is what readium's own signature promises. The guard goes on at the container boundary, so it covers CBZ, DIVINA, EPUB and PDF. It matches those two exact messages and nothing else, so a genuine null dereference in one of our transformers still surfaces, and it re-throws `CancellationException` ahead of the check, since `CancellationException` subclasses `IllegalStateException` and swallowing it would break the cancellation contract the method channel relies on. The race is upstream and still there; this stops it killing the host app.
- **Android publication hrefs no longer carry a leading slash the `Locator` stream does not**: a packaged manifest names itself with a relative `self` link, and resolving reading-order hrefs against it produced `/01_track.mp3` while the locator stream kept emitting `01_track.mp3`. Comparing a reading-order href against a live locator therefore failed on Android and worked on iOS, because readium-kotlin keeps a packaged manifest's `self` link and readium-swift strips it. Fixed in `flureadium_platform_interface` 0.10.1; `docs/api-reference/publication.md` already promised the behaviour that now holds.

### Documentation

- **Voice query contract stated where the API is defined**: the platform interface, the public facade, and the API reference now say the same thing about when a voice query throws. The TTS guide, the `TTSPreferences` reference, and the iOS troubleshooting page source voice identifiers with `ttsGetSystemVoices()`, which works before `ttsEnable()`. `docs/platform-specific/macos.md` is deliberately left alone: the macOS plugin implements only `getPlatformVersion`, so every call that page documents raises `MissingPluginException` regardless of which one it names.
- **iOS async test conventions written down**: `docs/05-testing/ios-unit-tests.md` now says why a wait scheduled on the main queue under a fixed timeout is a bet rather than a contract, and that a negative assertion needs a positive control or it can only fail by timeout. Waiting on a callback that fires directly is unaffected.
- **Audiobook position timing written down**: the audiobook guide now says that `play()` returning does not mean a position exists yet, and that on Android the native locator survives `stop()` and reopen, so early states for a new book can still carry the previous one's position. The auto-save example screens the locator against the reading order, with a note on why that filters rather than proves which book a locator came from.

### Testing

- iOS XCTest: `ttsGetAvailableVoices` with no TTS navigator returns an empty list rather than an error.
- Dart: the method-channel decode path surfaces an empty native voice response as an empty list.
- Android JVM (Robolectric): the Application reference is exposed after an engine attach with no Activity, survives Activity detach, throws before any attach, and cannot be unset by a later attach whose context has no Application.
- Audiobook integration tests now compare track identity by href rather than by the whole label, and wait for a real href before treating it as a baseline. Three chapter-navigation tests had been reading the label before playback reported a track: one failed intermittently, and the other two could satisfy their "the track changed" check with the first href that arrived rather than with an actual change.
- Android JVM (Robolectric): the closed-container guard reports both the closed-`ZipFile` and closed-`Inflater` reads as `ReadError.Access`, lets `CancellationException` through untouched, leaves every other runtime failure loud including an unrelated `NullPointerException`, and delegates `close()` and `sourceUrl`. One test builds the guard the way the open path builds it, with `TransformingResource` in between, since the composed expression is what has to hold rather than the guard on its own.
- iOS XCTest: the word-range suppression test now proves both halves — a word range arriving inside a suppressed utterance never reaches the listener, and once suppression clears word ranges do reach it. The second half is new and is what gives the first one meaning: the old assertion held on a pipeline that had stopped emitting entirely, so it could only fail by timeout. It also no longer waits on a main-queue block under a fixed cap: the block needed 200 ms and the wait was capped at 1 s, and on a local run the block did not fire inside the cap, so the test failed after 2.128 s. It had run in about 0.21 s on the four runs before that. The sibling dispose test carries the same pattern with a 150 ms block and ran for 1.125 s on the run that passed, which is how little margin there was; its wait is now a `Task.sleep` too.
- Android integration: `reads outliving closePublication fail soft, not fatal` closes a CBZ publication with sixteen unawaited page reads in flight, three times over. Sampling could not confirm this fix — the race appears in about one run in fifteen, and five green runs logged the guard zero times across 105 closes, so the suite was passing without ever entering the guarded path. Running this test on two branches differing only by the line that installs the guard settles it: unguarded fails three of three, guarded passes three of three with the guard firing twice per run. It also found the closed-`Inflater` variant, which the first version of the fix let through.
- The Android integration job now records `logcat` and a per-test event stream and uploads both on every run, pass or fail. It had been dying part way through roughly one run in fifteen since June with nothing kept from the run, so none of the first three occurrences could be read; the fourth was diagnosable in minutes. Keeping the artifacts from green runs is what makes the guard's log line visible, and a green run that discards it cannot tell you whether the fixed path was ever entered. The capture lives in `.github/scripts/android_integration_tests.sh` rather than inline in the workflow, because `reactivecircus/android-emulator-runner` splits its `script:` input on newlines and runs each line in a separate `sh -c`. `android_integration_tests_test.sh` fails if the workflow turns that input back into a shell block. A `workflow_dispatch` input runs the Android job on its own, for sampling a flaky Android failure without paying for macOS runners.
- The iOS integration job bounds suite loading at ten minutes and retries once when the load itself times out, which is a lost Dart VM service URL rather than a test failure. `test_core` enforced a 12 minute default here until 0.6.16 dropped it, and the job could otherwise sit until GitHub's six hour cap. The bound sits in `example/dart_test.yaml` under `on_os: mac-os`, since only a macOS host runs an iOS simulator. `.github/scripts/ios_suite_load_timed_out.sh` decides whether a timeout landed on the load or inside a test, and its test suite replays real event streams for the four failure modes that have to be told apart. Every workflow job now carries a `timeout-minutes`.

## 0.16.0

### New Features

- **Live car library refresh**: `Flureadium().refreshCarContent()` tells a connected CarPlay or Android Auto surface that the browsable library changed, so it re-queries and repaints without a reconnect. On iOS the CarPlay scene re-fetches each retained tab's children and updates its list templates in place; on Android the media service re-notifies each subscribed browse parent, taking the child count from the same browse query so the empty-state status row and dropped `siri` markers stay consistent. See `docs/architecture/car-bridge-decision.md`.
- **Android Auto browse before playback**: `PluginMediaService` now holds one persistent, browse-capable `MediaLibrarySession` built with an idle placeholder player, so Android Auto browses the host library from a cold, UI-less process before anything plays; starting a book swaps the real player into the same session instead of rebuilding it. See `docs/platform-specific/android.md`.

### Testing

- iOS XCTest: the CarPlay refresh path (notification to renderer refresh to template update).
- Android JVM (Robolectric): the browse-capable session and player swap, the idle placeholder, and the subscription-tracked refresh (per-controller notify, status-row and `siri` count, released-session safety).

### Dependencies

- Requires `flureadium_platform_interface` ^0.10.0 for `refreshCarContent()`.

## 0.15.0

### New Features

- **Car content provider (CarPlay + Android Auto)**: A host app now drives the whole in-car browse experience through one registered object, rather than the car surfaces deriving content from the single open publication. `Flureadium().registerCarContentProvider(provider, strings:)` takes a `CarContentProvider` the host implements (`rootTabs`, `children`, `search`, `play`, `nowPlayingChapters`, `addBookmark`, `cycleSpeed`), and the CarPlay scene and the Android Auto media service answer browse/search/play from it over an app-scoped car engine, so the head unit shows the host's whole library rather than just the open book. Content crosses as plain `CarBrowseNode`/`CarTab` values with host-supplied, already-localized `CarContentStrings`; the plugin holds no host data and makes no library policy. See `docs/api-reference/car-content.md`.
- **CarPlay tab templates + Siri search**: The iOS renderer builds the provider's root tabs as CarPlay list templates and populates them asynchronously on cold connect, so a status-only root shows first and the screen is never blank. A `siri`-kind node on the Search tab installs CarPlay's system Siri assistant cell (iOS 15+, with an `INPlayMediaIntent` hand-off), and on iOS 27+ keyboard-capable vehicles the Search tab also offers a typed `CPSearchTemplate`. See `docs/platform-specific/ios.md`.
- **Android Auto library browse + search**: The Android media service serves the provider's tabs and rows as a media3 browse tree with first-class search, container/playable/now-playing states, artwork, and a progress-bar completion extra. `siri` marker nodes are dropped, since Android voice input is Google Assistant rather than a browse row. See `docs/platform-specific/android.md`.
- **Now Playing actions**: CarPlay installs bookmark (audiobook items), playback-rate (`cycleSpeed`), and chapters buttons on the Now Playing template; Android Auto adds a bookmark custom command next to its rewind and forward buttons and has no playback-speed control, so `cycleSpeed` is iOS-only. The bookmark action routes back to the provider.

### Testing

- Dart: platform-interface transport routing and provider-contract tests; the `flureadium` barrel re-exports the car types.
- iOS XCTest: tab and list rendering, the async cold-connect update, the Siri assistant cell, and the iOS 27 typed-search delegate (renderer, bridge, factory, and template suites).
- Android JVM (Robolectric): the browse-tree mapping (including the `siri` drop), the method-channel content source with cold-start retry, and the library-session callback browse/search/bookmark paths.

### Documentation

- New `docs/api-reference/car-content.md` (the host contract), CarPlay and Android Auto sections in `docs/platform-specific/{ios,android}.md`, and the car-bridge ADR `docs/architecture/car-bridge-decision.md` linked from the architecture overview.

### Dependencies

- Requires `flureadium_platform_interface` ^0.9.0 for the car content provider types.

## 0.14.1

### Bug Fixes

- **Android Auto discovery**: `PluginMediaService` now advertises the legacy `android.media.browse.MediaBrowserService` intent-filter action. Android Auto connects as a platform `MediaBrowser` client and finds media apps by scanning for that action, so without it the app never appeared in the Android Auto app list — even though the media3 `MediaLibraryService` and the `com.google.android.gms.car.application` descriptor were already in place. Also removed a non-standard `android.media.session.MediaSessionService` action that was a `browse`/`session` typo. No API or runtime behaviour change: media3's `MediaLibraryService` already bridges to the legacy browser interface, so this only fixes the manifest advertisement.
- **Now Playing title race (iOS)**: the lock-screen/CarPlay title could briefly revert from "Book - Chapter" to just "Book" when the cover image finished loading. `NowPlayingInfoUpdater` loads the cover on a background task and wrote the artwork into the shared `NowPlayingInfo.Media` value type off the main thread, so it could overwrite a chapter-title update made on the main thread. Cover updates are now delivered on the main thread, serializing them with the title and chapter writes.

### Testing

- Added `PluginMediaServiceManifestTest` (Android JVM): asserts the shipped source manifest advertises `android.media.browse.MediaBrowserService` and no longer declares the non-standard `android.media.session.MediaSessionService`.

## 0.14.0

### Bug Fixes

- **iOS/macOS Swift Package Manager compile**: several Swift sources used Foundation types (`TimeInterval`, `JSONSerialization`, `Data`, `NSCoder`, and similar) without importing Foundation, relying on it arriving transitively through CocoaPods. Under Flutter 3.44+ (SwiftPM on by default) SwiftPM compiles each module with strict per-file imports, so those files no longer built: `Cannot find type 'TimeInterval' in scope`. Each such source now imports Foundation explicitly. No API or behaviour change; CocoaPods builds were unaffected.

### Testing

- Validated on Flutter 3.44.7 / Dart 3.12.2: the Dart and widget unit tests, the Android Robolectric JVM unit tests, and the example integration suite (`launch`, `epub`, `epub_tts`, `audiobook`, `cbz`, `divina`, `error_handling`, `webpub`) all pass on Android and iOS.

## 0.13.3

### Bug Fixes

- **Android concurrent publication open**: `ReadiumReader.openPublication` now serializes concurrent opens behind a single mutex. Opening a publication mutates singleton reader state (the current publication, its URL, and the active navigators), so two opens racing — a reader screen opening one book while background categorization opens another — could double-load a publication or double-release navigators. Every open now runs under the lock, and a second open of the same publication waits for the first and reuses its result through the fast path. `loadPublicationFromUrl` (used by categorization) loads without mutating navigator state and stays outside the lock.

### Testing

- Android JVM test `ReadiumReaderOpenConcurrencyTest`: `openPublication` serializes behind the mutex even on the same-publication fast path.
- Integration test: a streamed audiobook (a remote WAV served over a local range-seekable server) opens and plays. This guards the audio navigator build, which must run on the main thread because media3 pins the ExoPlayer to its single application thread; building it on a background dispatcher throws "Player is accessed on the wrong thread". The build's thread affinity cannot be unit-tested in the JVM — Robolectric cannot construct a real ExoPlayer — so the on-device integration test is the regression gate.

### Documentation

- Android platform notes: `openPublication` concurrency serialization and the audio-navigator main-thread build contract (`docs/platform-specific/android.md`).

## 0.13.2

### Bug Fixes

- **Android audiobook chapter-jump freeze**: Jumping to a chapter from the table of contents or resuming from a bookmark no longer freezes playback. `play(locator)` used to rebuild the media session every call, so a jump made while audio was playing created a second `MediaLibrarySession` with the same default (empty) id; media3 rejects duplicate session ids, and the error handler tore down the only player, leaving playback stuck at the new chapter's `0:00`. `play(locator)` now reuses the open session for the same navigator and seeks, releasing the old session only when switching navigators (audiobook to TTS). The transport buttons (`next()`/`previous()`) and the initial `play(null)` are unchanged.

## 0.13.1

### Bug Fixes

- **iOS/macOS Swift Package Manager resolution**: The SwiftPM library product in `ios/flureadium/Package.swift` was named `flutter-readium`, which does not match the plugin name. Under Flutter 3.44+ (SwiftPM on by default) an app build failed to resolve the plugin: `product 'flureadium' ... not found in package 'flureadium'`. The product is now named `flureadium`, matching the plugin, so SwiftPM integration resolves. No API or behaviour change; CocoaPods builds were unaffected.

## 0.13.0

### New Features

- **Android Auto**: Audiobooks now show up as a browsable media app on Android Auto head units. `PluginMediaService` runs as a media3 `MediaLibraryService` and serves a one-level browse tree: a root whose children are the open publication's chapters (its `readingOrder`). Picking a chapter on the head unit seeks the same audiobook navigator the in-app controls use, and play/pause/skip plus now-playing metadata reuse the existing media session. Needs no host manifest changes — the plugin declares the `com.google.android.gms.car.application` meta-data and ships the `automotive_app_desc.xml` descriptor, which manifest merging pulls into the host app (the example app adds nothing), and there are no Dart API changes. See `docs/platform-specific/android.md`.
- **CarPlay (iOS)**: Audiobooks expose a chapter list and transport controls on CarPlay. `CarPlayChapterList` builds one row per `readingOrder` entry (titles fall back to a localized "Chapter N"); selecting a row routes through `CarPlayPlaybackBridge` to the active audio navigator. Now-playing metadata and transport reuse the existing `NowPlayingInfoUpdater`. Host apps add a CarPlay scene to their scene manifest and the `com.apple.developer.carplay-audio` entitlement, which needs a per-app Apple grant, so plan for that lead time. See `docs/platform-specific/ios.md`.
- **Audiobook end-of-book state**: Reaching the natural end of the last track now emits a single `TimebasedState.ended` on both platforms, so hosts can show a completion screen. It fires only at a real end of book; closing or disposing the reader mid-playback no longer produces a phantom `ended` (iOS previously emitted one from `dispose()`).
- **Audiobook error events**: Streamed audio failures now reach `Flureadium.onErrorEvent` as a `ReadiumError` with code `TimebasedError`, instead of the player stalling silently at 0:00. Android forwards every timebased failure, load-time and mid-stream. iOS catches load-time track failures deterministically: during opening an `onCreatePublication` transform (`AudioResourceLoadFailureReporter` + `LoadFailureObservingResource`) wraps each audio track resource and reports a failed read, one error per track. Post-load decode/status failures and healthy-URL stalls stay best-effort on iOS (a KVO-only signal on Readium's private `AVPlayer`), and benign cancelled reads are filtered out. See `docs/guides/error-handling.md`.

### Bug Fixes

- **Audiobook previous/next chapter (Android & iOS)**: `Flureadium.previous()` / `next()` now move one track along the reading order on both platforms, instead of performing a 30-second seek that made the chapter buttons identical to skip-back / skip-forward. Bounded at the first and last track. TTS still maps these to previous/next sentence, and `audioSeekBy` (skip) behaviour is unchanged.
- **iOS audiobook transition freeze**: Changing chapter, seeking to a locator, or auto-advancing at end of track no longer freezes the UI. The audio delegate callbacks used to read `_audioNavigator.playbackInfo` synchronously, which re-entered the `AVPlayer` lock that `AudioNavigator.go(to:)` already held on the same thread — a self-deadlock. They now serve state from the playback info and locator Readium delivers off-lock, so a transition never reads back into the live player.
- **iOS error channel ownership**: The `error` `EventChannel` is now owned once by `FlureadiumPlugin` instead of being re-registered by each reader view. Closing a reader view no longer end-streams the Dart subscription, the audio path (which has no reader view) can send on the same channel, and `FlureadiumError` is serialized to a codec-safe map — sending the object itself crashed the Flutter standard codec. The PDF reader keeps its separate `pdf-error` channel.
- **iOS navigator teardown race**: `stop` now disposes the navigator captured at call time and clears the shared slot only if it still holds that navigator. A straggler teardown from a previous session no longer nils a navigator a newer session installed, which had surfaced as a spurious "TTS Navigator not initialized".
- **Android method-channel cancellation**: A coroutine cancelled mid-call — for example a `play` still suspended when the publication closes — unwinds normally instead of surfacing to Dart as a spurious `PlatformException(JobCancellationException)`. `CancellationException` is re-thrown rather than reported.

### Testing

- Android JVM tests for the Android Auto path: `AudiobookBrowseTree`, `PluginLibrarySessionCallback` (browse tree and chapter-pick seek-to-index), `PluginMediaService` library session, `PluginSimpleBasePlayer` (next/previous seek remap), and `TrackNavigation`; plus `AudiobookNavigatorEnded`, `ReadiumReaderTimebasedError`, and `PublicationChannelCancellation`.
- iOS XCTests for the CarPlay and error paths: `CarPlayChapterList`, `CarPlayPlaybackBridge`, `FlureadiumPluginChapterNav`, `FlureadiumPluginErrorChannel`, `FlutterAudioNavigator`, `AudioResourceLoadFailureReporter`, and `LoadFailureObservingResource`.
- Integration coverage: audiobook end-of-book `ended`, chapter and previous-chapter navigation (the same navigator path a head unit drives), unreachable and partial streamed-audio error surfacing, and an untitled-chapter audiobook. Adds the `untitled_chapter.audiobook` fixture and an `audio_stream_fixtures` harness for mid-stream failure.
- Example integration harness: `pumpUntil` bounded polling and an `ensureAppShowing` shared-boot helper so each test group boots once and reuses the app; TTS readiness is polled instead of waited out on a fixed timer.
- Test runners: `run_native_unit_tests.sh` gains `--rerun` for a clean Android rebuild, and `run_integration_tests.sh` pins the default Android TTS engine before the EPUB TTS leg so a cold emulator does not report an empty voice list.

### Documentation

- Android Auto setup and the browse-tree implementation, including Desktop Head Unit testing (`docs/platform-specific/android.md`).
- CarPlay setup — entitlement, scene manifest, simulator testing — and the chapter-list implementation (`docs/platform-specific/ios.md`).
- Audiobook end-of-book, transition safety, playback-error handling, and in-car sections (`docs/guides/audiobook-playback.md`).
- The `onErrorEvent` stream and the audiobook streaming-failure platform matrix, with the iOS post-load limitation (`docs/guides/error-handling.md`).
- Error channel single-ownership platform notes (`docs/api-reference/streams-events.md`).
- Troubleshooting entries for the iOS transition freeze, the "TTS Navigator not initialized" teardown race, and the Android cancellation `PlatformException` (`docs/troubleshooting.md`).
- Testing conventions: `pumpUntil`, `ensureAppShowing` shared boot, the `--rerun` runner flag, and the Android TTS prerequisite (`docs/05-testing/`).

## 0.12.1

### Bug Fixes

- **readingOrder href format**: `pub.readingOrder` hrefs now match what the `Locator` stream emits — bare paths as the native Readium parser produced them, with no synthetic leading slash (`001.jpg`, not `/001.jpg`). This fixes silent failures in code that compares a `Locator.href` against `readingOrder[i].href`, or round-trips an href through a native API, where the leading slash made the two never match. Comes from `flureadium_platform_interface` 0.7.1.

### Testing

- Add a CBZ integration regression that asserts `pub.readingOrder.first.href` equals the live `Locator.href` for the same resource.

### Documentation

- Note in the publication API reference that `readingOrder` hrefs share the `Locator` stream's format.

## 0.12.0

### New Features

- Add `flattenToc(List<Link> toc) → List<Link>`. Collects every TOC entry — including `link.children` at any depth — into a flat list in reading order. Exported from the `flureadium` barrel. Use it when you need a flat chapter sequence for a progress indicator or jump-to-chapter picker.

### Bug Fixes

- **Chapter skip / hierarchical EPUB3 TOC**: Fix `skipToNext` and `skipToPrevious` on `ReadiumReaderWidget` skipping over entire nested chapter groups. For books where `toc.xhtml` stores chapters as children of a parent entry (`link.children`), both methods previously searched only the top-level list — nested chapters were invisible, skip buttons disappeared, and "next chapter" jumped straight to the next top-level entry. Both now use the flattened TOC.
- **Chapter skip / non-TOC spine items**: Fix `skipToNext` and `skipToPrevious` giving up when the current page has no TOC entry (a cover, interstitial page, or back matter). Both now scan the reading order to find the nearest TOC entry before or after.

### Testing

- Unit tests for `flattenToc`: empty input, flat list, one level of nesting, multiple levels.
- Between-entries unit tests for `decideSkipToNext` and `decideSkipToPrevious`: a spine item between two TOC entries resolves to the adjacent chapter in each direction.
- `ReadiumReaderWidget` unit tests confirming `skipToNext` from a nested chapter reaches the next sibling, not the next top-level entry.
- `hierarchical_toc.epub` — a synthetic EPUB3 fixture with a two-level TOC (Part I → [Ch1, Ch2, Ch3]; Part II → Section 1 → [Ch4, Ch5]) and three non-TOC spine items.
- Navigation smoke tests parameterized to run against both `moby_dick.epub` and `hierarchical_toc.epub`.

### Documentation

- Document `flattenToc` in the publication API reference and the EPUB reading guide.
- Update `skipToNext` / `skipToPrevious` in the ReaderWidget reference with hierarchical TOC behavior.

## 0.11.0

### New Features

- Add `Flureadium.extractPageThumbnail(href, maxHeight, quality)` for downscaled JPEG thumbnails from image resources in the currently open publication.
- Add native thumbnail extraction on Android and iOS. Android uses `BitmapFactory` downsampling and JPEG compression; iOS uses ImageIO thumbnail decoding and JPEG compression.
- Add the `extractPageThumbnail` web override, returning `null` until a web decoder is wired up.

### Bug Fixes

- **iOS / CBZ and PDF navigation**: Route `goToLocator` to image-based readers and PDF readers, not just EPUB and time-based navigators.
- **iOS / early CBZ navigation**: Wait for the image navigator to become ready before programmatic `goToLocator`, returning `false` instead of hanging indefinitely when readiness never arrives.
- **Android / CBZ and PDF navigation**: Dispatch `goToLocator` to image and PDF navigators and return the native navigation result to Dart.
- **Android / thumbnail href lookup**: Resolve thumbnail hrefs through Readium legacy-href URL normalization so manifest hrefs with leading slashes or encoded characters resolve consistently.
- **Android / TTS service startup**: Enter the foreground immediately with a startup media notification so background playback startup is not killed before the real media notification is ready.

### Testing

- Add Dart facade tests and platform-interface method-channel tests for `extractPageThumbnail`.
- Add Android JVM tests for `PageThumbnailExtractor` and foreground-service startup behavior.
- Add iOS XCTest coverage for `PageThumbnailExtractor` and image-reader `goToLocator` readiness/routing.
- Extend CBZ integration coverage for `goToLocator`, successful thumbnail extraction, missing hrefs, and closed-publication behavior.

### Documentation

- Document `extractPageThumbnail` in the Flureadium API reference, concepts, platform docs, READMEs, and example README.
- Update README and docs format matrices for CBZ/DIVINA support and remove stale "not implemented" claims.
- Document Android and iOS thumbnail implementation details and the web `null` behavior.

### Dependencies

- Requires `flureadium_platform_interface` ^0.7.0.

## 0.10.0

### New Features

- **CBZ and DIVINA support**: `ReadiumReaderWidget` renders image-based publications on Android and iOS. Format detection is automatic — same widget, same API, no Dart-side changes.
- **Android**: `ImageNavigator` wraps Readium Kotlin's `ImageNavigatorFragment` with lifecycle management, state persistence, and locator tracking.
- **iOS**: `ImageReaderView` wraps Readium Swift's `CBZNavigatorViewController` with edge-tap and swipe navigation, same UX as the PDF reader.

### Bug Fixes

- **iOS CBZ navigation crash**: Fix `PlatformException(InvalidArgument, Failed to parse locator)` when navigating CBZ files with special characters in filenames. The Locator href encode/decode boundary in `flureadium_platform_interface` now normalizes hrefs correctly for native platform transport.
- **iOS CBZ page navigation performance**: Cache images from Readium's local server to eliminate redundant ZIP extraction and HTTP round-trips on every page turn. Adds `ImageCacheURLProtocol`, a URLProtocol subclass that intercepts localhost GET requests and serves cached images from NSCache. Cache is session-scoped and cleared when the reader closes.

### Performance

- **CBZ/DIVINA page turn speed**: Forward the `animated` parameter from `ReadiumReaderWidget.goLeft()`/`goRight()` through the method channel so callers can disable page turn animation. Previously the parameter was accepted but silently dropped, and the channel always animated.
- **iOS CBZ edge-tap instant page turns**: Edge-tap and swipe handlers in `ImageReaderView` now use `animated: false`, eliminating the ~300ms `UIPageViewController` transition on every tap.
- **Same-publication cache (iOS + Android)**: `openPublication` returns the already-loaded publication when called with the same URL, skipping redundant ZIP parsing and manifest construction. Eliminates ~3.9s re-open latency when resuming a CBZ/DIVINA book.

### Testing

- Android JVM tests for image navigator state, cleanup, routing detection, and saved-state persistence.
- iOS XCTest coverage for navigation state, edge-tap config, and publication routing.
- CBZ and DIVINA integration tests with bundled test fixtures, registered in `all_tests.dart` and `all_tests_android_ci.dart`.
- iOS XCTest coverage for `ImageCacheURLProtocol`: canInit filtering, cache hit/miss, enable/disable lifecycle, clearCache.
- Dart unit tests for `animated` parameter forwarding in `goLeft`/`goRight`.
- Android Robolectric tests for same-publication cache: cache hit, cache miss (different URL), cache miss (no current publication).
- DIVINA cache integration test.

### Example App

- "Open CBZ" and "Open DIVINA" buttons with bundled fixtures.
- Configurable startup asset (`initialAsset` parameter) for integration test injection.

### Documentation

- Reader widget, Android, iOS, concepts, and integration test docs updated for image-based publications.
- README format matrix now lists CBZ and DIVINA.
- Document href encoding behavior in the Locator API reference.

## 0.9.4

### Bug Fixes

- **Reader external-link callbacks**: Forward `ReadiumReaderWidget.onExternalLinkActivated` into `ReadiumReaderChannel` so Dart hosts actually receive external-link activations reported by the native reader.
- **Analyzer/test export mismatch**: Expose the widget-test channel-construction helper consistently across the conditional `reader_widget_*` exports so `dart analyze` and `flutter test` resolve the same public surface.

### Testing

- Add Dart regressions for the native `onExternalLinkActivated` method-call path and the widget/channel construction seam.
- Verify `dart analyze`, `flureadium/flutter test`, `flureadium_platform_interface/flutter test`, and the example EPUB integration smoke test pass.

### Documentation

- Document `onExternalLinkActivated` as a delivered integration callback and clarify that host apps can hand external links off to the OS browser for restricted-content flows.

## 0.9.3

### Bug Fixes

- **iOS / EPUB reader locator crash**: Replace the force-unwrapped `getLocatorFragments()` parse path with safe optional handling so `null` JavaScript results no longer crash the reader.
- **iOS / reader disposal race**: Guard async page-change callbacks with a disposal flag and `MainActor` state reads so page-change work does not outlive a torn-down reader view.

### Testing

- Add iOS regression coverage for locator-fragment result parsing in `ReadiumExtensionsTests`.
- Verify Flutter tests, native iOS `RunnerTests`, and example integration tests pass for the fix.

### Documentation

- Add a troubleshooting entry covering the locator-fragment crash symptoms, cause, and remediation.

## 0.9.2

### Bug Fixes

- **Android / sync audiobook saved-state crash**: `SyncAudiobookNavigator.storeState()` put `FlutterMediaOverlay` objects into the Bundle via `putSerializable`, but those objects contain non-serializable Readium types (`Url`, `MediaType`). Android's activity state save hit `BadParcelableException` → `NotSerializableException` during synchronized audiobook playback. The data was never actually read back — `restoreState()` re-derives overlays from the publication — so the fix drops the dead `putSerializable` call and removes `Serializable` from both model classes.

## 0.9.1

### Bug Fixes

- **Android / TTS and audiobook background playback**: Start `PluginMediaService` with `startForegroundService()` instead of `startService()` so Android 15 does not kill playback shortly after the app goes to the background.
- **Android / media session cleanup**: Close the media session if `TTSNavigator.play()` or `AudiobookNavigator.play()` fails while opening the session, preventing a dangling foreground-service start from timing out.
- **Android / saved-state background crash**: Persist `FlutterDecorationPreferences` as primitive `Bundle` data instead of Java serialization so pressing Home does not crash activity state saving with `BadParcelableException` on devices where Readium decoration styles are not serializable.

### Testing

- Add Android JVM regression tests for foreground-service startup and `openSession()` failure cleanup in TTS and audiobook navigators.
- Add Android JVM regression tests for `FlutterDecorationPreferences` bundle round-tripping and `ReadiumReader.storeState()` parcel-safe saved-state persistence.

### Documentation

- Document the Android foreground-service permissions required for background TTS and audiobook playback.
- Update the Android troubleshooting note to cover both the foreground-service startup fix and the saved-state crash fix for playback stopping when the app is backgrounded.

## 0.9.0

### New Features

- **iOS / EPUB**: Add `Copy` to the long-press text selection menu. EPUB selection actions now use `EditingAction.copy`, `EditingAction.lookup`, and `EditingAction.translate`, replacing the old placeholder custom action.

### Testing

- Add iOS XCTest coverage for EPUB editing actions in `EpubEditingActionsTests`.
- Add an EPUB integration smoke test that long-presses the reader surface and verifies the reader remains mounted.

### Documentation

- Document text-selection copy behavior on iOS and Android, including the existing PDF behavior and the Android PDF limitation.

## 0.8.3

### Bug Fixes

- **Android**: Fix NullPointerException crash when opening PDF files. Inside `PdfNavigator.initNavigator()`, a Kotlin scope resolution bug caused `engineProvider` to resolve to the uninitialized `PdfReaderViewModel` property instead of the outer `PdfNavigator` property.

## 0.8.2

### Bug Fixes

- **iOS**: Fix SIGABRT crash on hot reload with an active EPUB or PDF reader. The crash was a Swift runtime exclusivity violation — `deinit` wrote to a global variable that was already mid-write during ARC deallocation triggered by the new view's `init`. Global reader view references are now `weak var` (matching Android's `WeakReference` pattern), and `deinit` no longer touches them.
- **iOS**: Make PdfReaderView dispose handler comprehensive — stream disposal and channel cleanup were previously only in `deinit`, meaning they never ran when the Dart `dispose` call arrived while the engine was still alive.

## 0.8.1

### Bug Fixes

- **Android**: Convert `error.cause` to `String?` in `publicationError()` before passing it to `MethodChannel.Result.error()`. The Readium `Error` object was not codec-safe, causing `StandardMessageCodec` to throw `IllegalArgumentException: Unsupported value` and silently swallowing EPUB subject metadata.

## 0.8.0

### New Features

- **TTS availability check**: Add `ttsCanSpeak()` — checks whether the device TTS engine supports the current publication's language before enabling. Returns `false` when TTS is unavailable, letting you show an appropriate message instead of a silent failure.
- **TTS voice installer**: Add `ttsRequestInstallVoice()` — opens the platform voice-data installer when the required language pack is missing. Android launches the system TTS settings; on iOS and web this is a no-op.
- **TTS error reporting**: Add `TtsErrorType` to `ReadiumTimebasedState` — surfaces structured error types (`languageMissingData`, `languageNotSupported`, `synthesisError`, `networkError`) so the app can react to specific failure modes.
- **System voices**: Add `ttsGetSystemVoices()` — returns all system-level TTS voices regardless of publication language. Unlike `ttsGetAvailableVoices()` (which filters to the current publication), this gives the full list for voice-picker UI.
- **TTS position restore**: Add optional `fromLocator` parameter to `ttsEnable()` — allows resuming TTS playback from a saved position after disabling and re-enabling.
- **Android**: Add awaitable `release()` to all navigators — proper resource cleanup that can be awaited before switching publications.
- **Web**: Add TTS engine using the Web Speech API with full JS interop bridge to Dart.

### Bug Fixes

- **Android**: Suppress backward scroll when calling TTS `play()` from a specific position — the navigator no longer jumps back to the start of the chapter before reading.
- **iOS**: Suppress backward scroll on TTS play from a specific position, matching the Android fix.
- **Android**: Honor `initialLocator` in `TTSNavigator.initNavigator()` — TTS now starts from the saved locator instead of the beginning of the chapter.
- **iOS**: Use optional cast in `ttsSetPreferences` to handle null `voiceIdentifier` without crashing.
- **iOS**: Make `closePublication` awaitable to prevent async race when switching publications.
- **Android**: Dispatch navigator `close()` to the main thread in `release()`, preventing `CalledFromWrongThreadException`.
- **Android**: Dispatch fragment `commitNow` on the main thread in `release()`.
- **Android**: Guard stale "closed" event from a disposed platform view.
- **Android**: Release navigators in `openPublication()` before switching to prevent resource leaks.
- **Android**: Use `release()` in `ReadiumReader` for proper resource cleanup.
- Guard `setState` with `mounted` check and cancel leaked subscription after dispose.
- Use `_initialLocator` in TTS `play()` so resume starts from the saved position.
- Pass saved TTS locator on re-enable.

### Example App

- Full TTS control UI: can-speak gating, voice cycling, system voice picker, sentence navigation, install-voice prompt on missing language data.
- Save and restore TTS position across enable/disable cycles.
- Detect navigation when re-enabling TTS to prevent backward scroll.
- Catch `PlatformException` in audio toggle.
- Use unique temp paths in asset extraction to prevent SIGBUS.
- Fix race condition in `_toggleTts` that discarded the playing state.

### Developer Tools

- Harden integration test runner with signal traps, test reporter, and cleanup.
- Capture native logcat during Android integration tests.
- Clean up orphaned Chrome processes and use `web-server` device.
- Stream test output in real-time when `--verbose` is set.

### Testing

- Add Web TTS integration tests (`epub_tts_web_test.dart`).
- Add Jest test suite for the Web Speech API TTS engine.
- Replace fixed sleeps with adaptive polling and bounded pump loops in integration tests.
- Add tearDown blocks to integration tests for cleanup between tests.
- Replace stale `getPlatformVersion` template test with real `ttsCanSpeak` test.
- Add Android unit tests: `ReadiumReaderCleanupTest`, `ReadiumReaderTtsTest`, `AudiobookNavigatorReleaseTest`, `TTSNavigatorReleaseTest`, `TTSNavigatorTest`.
- Add iOS unit tests: `FlutterTTSNavigatorTests`.

### Documentation

- Document `ttsCanSpeak`, `ttsErrorType`, `ttsGetSystemVoices`, and `ttsRequestInstallVoice` in API reference.
- Document TTS position resume with `fromLocator` in the text-to-speech guide.
- Document `release()` vs `dispose()` navigator pattern.
- Document audio error handling and test isolation tearDown pattern.
- Add iOS Swift unit test documentation.
- Add troubleshooting entries for `ttsSetPreferences` iOS crash and iOS publication cleanup.

### Dependencies

- Requires `flureadium_platform_interface` ^0.6.0.

---

## 0.7.2

### Bug fixes

- **iOS / Edge tap interception (iOS 26+)**: iOS 26 changed how Flutter routes touches on
  platform views. With `enableEdgeTapNavigation = false`, no tap callbacks were set on
  `EdgeTapInterceptView`, so edge-zone touches fell through to WKWebView. Readium's
  `DirectionalNavigationAdapter` picked them up and turned the page anyway.

  Root cause: `hitTest` was gated on `onLeftEdgeTap != nil`, not on whether interception
  was wanted.

  Fix: `EdgeTapInterceptView` now has an `interceptEdgeTaps: Bool` property. `hitTest`
  checks the flag, not callbacks. `ReadiumReaderView` sets it `true` in paginated mode
  (regardless of `enableEdgeTapNavigation`) and `false` in scroll mode. `PdfReaderView`
  sets it equal to `enableEdgeTapNavigation`. When `true`, edge-zone touches never reach
  `DirectionalNavigationAdapter`; with no callbacks set, the touch does nothing. No Dart
  changes. Behaviour on iOS 13-18 is unchanged.

### Documentation

- `docs/platform-specific/ios.md`: Added the iOS 26 `interceptEdgeTaps` fix and per-mode
  behaviour (paginated always intercepts, scroll never, PDF follows
  `enableEdgeTapNavigation`).

---

## 0.7.1

### Bug Fixes

- **Example app**: Fix `setState() called after dispose()` in `_ReaderPageState` — all async
  methods (`_openEpub`, `_openAudiobook`, `_openWebPub`, `_toggleAudio`, `_nextVoice`) now check
  `mounted` before calling `setState` after an `await`.

### Developer Tools

- Add `scripts/run_integration_tests.sh` — runs integration tests for Android, iOS, and Web
  sequentially from a single command. Scans `flutter devices` once, auto-selects when only one
  device is found per platform, manages ChromeDriver automatically (npx version-matched first,
  system binary fallback), and writes per-platform logs to a gitignored `test_logs/` directory.

### Documentation

- `docs/05-testing/integration-tests.md`: Document the new test runner script; correct CI section
  (CI runs build verification only — integration tests are run locally with the script).
- `docs/platform-specific/web.md`: Mark web publication loading as work in progress with an
  accurate known issues table.

---

## 0.7.0

### New Features

- **Android / Edge tap & swipe navigation**: `setNavigationConfig()` now works on Android, matching iOS behaviour.
  A transparent overlay is placed on top of the Readium navigator (EPUB and PDF) and intercepts touches in
  the configurable left/right edge zones. Center touches always pass through to the reader content.
  - `enableEdgeTapNavigation` — tap the left/right edge to turn pages (default: enabled)
  - `enableSwipeNavigation` — horizontal fling to turn pages (default: enabled)
  - `edgeTapAreaPoints` — edge zone width in dp, clamped to 44–120 (default: 44)
  - In EPUB vertical scroll mode, all overlay gestures are automatically disabled so Readium's
    WebView can handle native scrolling; gestures are re-enabled when scroll mode is turned off.

---

## 0.6.0

### New Features

- **iOS / EPUB scroll mode**: Swipe-back now restores the last scroll position within the previous spine item.
  Previously, swiping back always landed at the start of the item. The position is stored in memory per
  spine item and restored automatically when a backward swipe is detected.
  - Explicit navigation (TOC tap, `skipToPrevious`) is unaffected — it clears the stored position for the
    target item so restoration does not override an intentional jump.
  - History is session-only; it is not persisted across app launches.
  - `onLocatorChanged` fires after restoration, so persistent position saving always reflects the
    final restored position.

---

## 0.5.0

### Breaking Changes

- **EPUBPreferences / PDFPreferences**: Navigation config fields removed. See `flureadium_platform_interface` 0.5.0 changelog for full field list.
  Requires `flureadium_platform_interface` ^0.5.0.

### New Features

- **iOS**: Add `setNavigationConfig` method channel handler in `ReadiumReaderView` and `PdfReaderView`. Navigation UX settings (edge tap, swipe, gesture disabling) are now applied via a dedicated channel call rather than being extracted from the Readium preferences map.
- **iOS**: Remove `developerConfigKeys` filtering workaround from `ReadiumReaderView` and `PdfReaderView`. Readium's `EPUBPreferences.init(fromMap:)` / `PDFPreferences.init(fromMap:)` now receive clean maps with only Readium keys.
- **iOS**: Add `FlutterNavigationConfig` Swift model for deserializing `ReaderNavigationConfig` from the method channel.

## 0.4.0

### Breaking Changes

- **iOS / PDFPreferences**: Rename `disableTextSelectionMenu` to `disableDoubleTapTextSelection`.
  Requires `flureadium_platform_interface` ^0.4.0.

### New Features

- **iOS / PDF**: Fix double-tap word selection in PDF reader. Double-tapping on PDF text no longer
  selects the word or shows the Copy/Look Up/Translate menu. Only the reader overlay controls toggle.
  Long-press text selection with the system menu remains fully functional, matching ePub behavior.
  - Root cause: `UITextNonEditableInteraction.doubleTapInUneditable:` on the lazily-created
    `PDFTextInputView` was intercepting double taps. Previous attempts failed because `PDFTextInputView`
    does not exist at `setupPDFView` time — it is added asynchronously after page rendering.
  - Fix: Deferred traversal (0.1s / 0.5s / 1.0s after `setupPDFView` and each `locationDidChange`)
    finds `PDFTextInputView` and removes `UITextNonEditableInteraction` from it.

## 0.3.4

### Bug Fixes

- **iOS**: Fix `MissingPluginException` on channel `dev.mulev.flureadium/text-locator` (and sibling event channels) when closing a publication.
  - Root cause: `EventStreamHandler.dispose()` was calling `channel.setStreamHandler(nil)` synchronously after sending `FlutterEndOfEventStream`. Flutter's answering "cancel" message arrived after the handler was already gone, producing the exception.
  - Fix: Remove the premature `setStreamHandler(nil)` call. The handler remains registered until the "cancel" round-trip completes; `onCancel` then clears the event sink. The handler is released naturally when the view is deallocated.

## 0.3.3

### New Features

- **iOS**: Add `edgeTapAreaPoints` preference to `EPUBPreferences` and `PDFPreferences` — configures edge tap zone width in absolute points (44–120pt). Replaces the previous percentage-based approach with a fixed-size zone that behaves consistently in split-screen and on all device sizes. Defaults to 44pt (iOS HIG minimum tap target) when null.
  - Requires `flureadium_platform_interface` ^0.3.1.

### Bug Fixes

- **iOS**: Fix spurious `"EPUBPreferences WARN: Cannot map property"` log warnings on every `setPreferences` call and at view init. Developer config keys (`enableEdgeTapNavigation`, `enableSwipeNavigation`, `edgeTapAreaPoints`) are now filtered out before passing the preference map to Readium's `EPUBPreferences.init(fromMap:)` and `PDFPreferences.init(fromMap:)`, which only understand Readium preference keys.
- **iOS**: Fix potential nil crash in `getCurrentLocator` when `currentLocation` returns nil inside the async task.

## 0.3.2

### Bug Fixes

- **iOS**: Fix crash on app close caused by stream handlers sending `FlutterEndOfEventStream` during `deinit`, after the Flutter engine has already torn down its channels.
  - Move all `EventStreamHandler.dispose()` calls from `deinit` to the Dart `"dispose"` method call handler, which runs while the engine is still alive.
  - `deinit` now only nils out references as a safety net without sending any messages.

### Testing

- Add `EventStreamHandlerTests` covering dispose lifecycle, double-dispose safety, send-after-dispose no-op, and listener registration/cancellation.

## 0.3.1

### Bug Fixes

- **Android EPUB**: Fix position restore drift where reopening a book would jump to a different location than the saved position.
  - Root cause: JavaScript `scrollToLocations()` recalculated progression from element bounding rect geometry, overwriting correct StateFlow value.
  - Solution: Skip `scrollToLocations()` during restore when already positioned correctly (within 1% delta), achieving iOS/Android parity.
  - Add grace period validation to suppress late locator emissions after restore settles.
  - Add fragment re-subscription on lifecycle changes to prevent stale listeners.
  - See [Saving Progress Guide](docs/guides/saving-progress.md#testing-restore-behavior) for testing documentation.

### Testing

- Add comprehensive unit tests for Android EPUB restore behavior (`EpubNavigatorRestoreTest.kt`, replaced in 0.17.0 by `EpubScrollRestoreTest.kt`).
- Add manual reopen-loop validation procedure to documentation.
- Improve diagnostic logging for restore flow investigation.

## 0.3.0

- Add `renderFirstPage` API — renders the first page of a PDF as a JPEG image for use as a cover. Uses `PdfRenderer` on Android and `CGPDFDocument` on iOS. No Readium dependency needed.
- Requires `flureadium_platform_interface` ^0.3.0.

## 0.2.0

- Add swipe gesture navigation for EPUB and PDF readers on iOS — swipe left/right to turn pages in edge zones.
- Add `enableEdgeTapNavigation` and `enableSwipeNavigation` preference flags for independently controlling edge tap and swipe page navigation on iOS.
- Requires `flureadium_platform_interface` ^0.2.0.

## 0.1.1

- Fix `.pubignore` excluding `lib/src/web/` which prevented dartdoc generation on pub.dev.

## 0.1.0

- Initial public release of Flureadium.
- Full EPUB 2/3 reading with customizable typography and themes.
- PDF reading support on Android (Pdfium) and iOS (PDFKit).
- Text-to-speech with voice selection, speed, and pitch control.
- Audiobook playback with track navigation and variable speed.
- Media overlay support for synchronized read-along experiences.
- Decoration API for highlights, bookmarks, and annotations.
- ReaderWidget for embedding the reader in Flutter widget trees.
- Position tracking and saving via Locator streams.
- Cross-platform support: Android, iOS, macOS, and Web.
