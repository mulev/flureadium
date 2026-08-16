# Troubleshooting

Common issues and solutions when using Flureadium.

## Build Errors

### Android: "MainActivity cannot be cast to FragmentActivity"

**Error:**
```
java.lang.ClassCastException: com.example.app.MainActivity cannot be cast to androidx.fragment.app.FragmentActivity
```

**Solution:**
Change your `MainActivity` to extend `FlutterFragmentActivity`:

```kotlin
// android/app/src/main/kotlin/.../MainActivity.kt
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {
}
```

### Android: Could not find com.github.marain87 dependencies

**Error:**
```
Could not find com.github.marain87:AndroidPdfViewer:3.2.8
Could not find com.github.marain87:PdfiumAndroid:1.9.8
```

**Cause:**
JitPack repository is not configured. The Readium Pdfium adapter depends on libraries hosted on JitPack.

**Solution:**
Add JitPack to your `android/build.gradle`:
```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' }
    }
}
```

### Android: Minimum SDK Version

**Error:**
```
Manifest merger failed : uses-sdk:minSdkVersion 21 cannot be smaller than version 24
```

**Solution:**
In `android/app/build.gradle`:
```groovy
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

### iOS: Pod Install Failed

**Error:**
```
[!] Unable to find a specification for `ReadiumShared`
```

**Solution:**
1. Update pod repo:
   ```bash
   cd ios
   pod repo update
   ```

2. Clear cache and reinstall:
   ```bash
   pod deintegrate
   pod cache clean --all
   pod install
   ```

3. Ensure Podfile has correct podspecs (see [Installation](getting-started/installation.md))

### iOS: "No such module 'ReadiumShared'"

**Solution:**
Run pod install with repo update:
```bash
cd ios
pod install --repo-update
```

### iOS: Reader crash while turning pages or closing the reader

**Symptoms:**
- Crash in `EpubLocatorReporter.report`, resolving fragments through `EpubPageBridge.locatorFragments`
- More likely while a page-change callback is in flight and the reader is closed immediately after

**Cause:**
Older versions force-unwrapped the JavaScript locator-fragments result. Readium returns `()` when the JavaScript side yields `null`, and a detached page-change task could also race with `dispose`.

**Solution:**
Upgrade to a version containing the fix, or backport both changes:
1. Replace the force-unwrap in the fragment parsing with safe dictionary parsing and `try? Locator(...)` — `parseLocatorFragmentsResult` in `EpubPageBridge.swift`.
2. Guard asynchronous page-change work with a disposal flag and a weak `self` capture before evaluating JavaScript or sending Flutter events. `EpubLocatorReporter` checks the flag on both sides of the WebView hop, and `ReadiumReaderView.resolveLocatorFragments` checks it before the call.

### Web: JavaScript File Not Found

**Error:**
```
Failed to load readiumReader.js
```

**Solution:**
1. Copy the JS file:
   ```bash
   dart run flureadium:copy_js_file web/
   ```

2. Ensure script tag in `index.html`:
   ```html
   <script src="readiumReader.js" defer></script>
   ```

## Runtime Errors

### Publication Won't Open

**Error:**
```
OpeningReadiumException: formatNotSupported
```

**Possible Causes:**
- File is not a valid EPUB
- File path is incorrect
- File is corrupted

**Solution:**
1. Verify file exists:
   ```dart
   final file = File(path);
   print('Exists: ${file.existsSync()}');
   ```

2. Check file extension and format
3. Try with a known-good EPUB file

### "PublicationNotSetReadiumException"

**Error:**
```
PublicationNotSetReadiumException: Cannot navigate without publication
```

**Cause:**
Trying to navigate before publication is opened.

**Solution:**
Ensure publication is opened before navigation:
```dart
final pub = await flureadium.openPublication(path);
// Now you can navigate
await flureadium.goRight();
```

### Blank Reader Screen

**Possible Causes:**
1. Publication not loaded
2. ReaderWidget not receiving publication
3. Native view not initialized

**Solutions:**
1. Add loading indicator:
   ```dart
   if (_publication == null) {
     return CircularProgressIndicator();
   }
   return ReadiumReaderWidget(publication: _publication!);
   ```

2. Check for errors:
   ```dart
   try {
     final pub = await flureadium.openPublication(path);
   } on ReadiumException catch (e) {
     print('Error: ${e.message}');
   }
   ```

### TTS Not Working

**Possible Causes:**
1. TTS not enabled
2. No voices available
3. Platform-specific issue

**Solutions:**
1. Enable TTS first:
   ```dart
   await flureadium.ttsEnable(TTSPreferences(speed: 1.0));
   await flureadium.play(null);
   ```

2. Check voices. These two calls answer different questions, and comparing them tells you which cause you have. The device's own voices, independent of any TTS session:
   ```dart
   final systemVoices = await flureadium.ttsGetSystemVoices();
   print('Device voices: ${systemVoices.length}');
   ```

   And what the TTS session reports — an empty list on Android and iOS when TTS is not enabled:
   ```dart
   final voices = await flureadium.ttsGetAvailableVoices();
   print('Session voices: ${voices.length}');
   ```

   An empty session list beside a populated device list points at cause 1, not cause 2.

3. On Android, ensure TTS engine is installed

### Audio Not Playing

**Possible Causes:**
1. Not an audiobook publication
2. Audio not enabled
3. Volume is zero

**Solutions:**
1. Check publication type:
   ```dart
   if (pub.conformsToReadiumAudiobook) {
     await flureadium.audioEnable();
   }
   ```

2. Check preferences:
   ```dart
   await flureadium.audioEnable(
     prefs: AudioPreferences(volume: 1.0, speed: 1.0),
   );
   ```

### iOS: MissingPluginException on event streams

**Symptom:**
```
MissingPluginException(No implementation found for method listen on channel dev.mulev.flureadium/text-locator)
```
Event streams silently stop delivering updates even after the exception is caught.

**Cause:**
On iOS, the `text-locator`, `reader-status`, and `error` EventChannels are registered lazily
inside `ReadiumReaderView.init()`, which fires from `_onPlatformViewCreated`. Subscribing to
these streams before the platform view is created causes `MissingPluginException`, which
permanently closes `receiveBroadcastStream()`'s internal `StreamController`. All subsequent
events on that channel are silently dropped for the lifetime of the stream.

**Fix:**
Subscribe to streams inside a callback passed as `onReady` to `ReadiumReaderWidget`.
`onReady` fires synchronously from `_onPlatformViewCreated` after all native EventChannel
handlers are registered — no polling, no timers:

```dart
void _subscribeToChannels() {
  _sub?.cancel();
  _sub = _flureadium.onTextLocatorChanged.listen((l) { /* ... */ });
}

// In build():
ReadiumReaderWidget(
  publication: _publication!,
  onReady: _subscribeToChannels,
)
```

Because `_subscribeToChannels` is synchronous (no `Future.delayed` timers), `pumpAndSettle`
settles as soon as the reader is ready in integration tests.

### iOS: Crash on App Close

**Symptom:** App crashes when closing/terminating, with a stack trace through `EventStreamHandler.dispose()` → `FlutterBinaryMessengerRelay sendOnChannel` → `FlutterEngine destroyContext`.

**Cause:** Native stream handlers are trying to send `FlutterEndOfEventStream` during `deinit`, but `deinit` is triggered by the Flutter engine teardown — the channel is already dead.

**Fix:** Ensure all stream handler `.dispose()` calls happen in the platform view's `"dispose"` method call handler (called from Dart while the engine is alive), not in `deinit`. The `deinit` should only nil out references without sending any messages. See [iOS Platform - Stream and View Lifecycle](platform-specific/ios.md#stream-and-view-lifecycle).

### iOS: Crash on Hot Reload with Active Reader (SIGABRT)

**Symptom:** `SIGABRT` with "Fatal access conflict detected" or "Simultaneous accesses to..." when hot-reloading while a reader view is open. The crash trace points to `ReadiumReaderView.deinit` or `PdfReaderView.deinit`.

**Cause:** The old reader view's `deinit` was writing to a module-level global (`currentReaderView`) at the same time the new view's `init` was writing to it. Swift's runtime exclusivity enforcement detects overlapping writes and aborts. This happens because assigning the new view to the global triggers ARC release of the old value, which triggers `deinit` — all within a single write operation.

**Fix (applied):** The globals are now `weak var`, so ARC zeroing doesn't trigger user code in `deinit`. The `deinit` no longer touches global state at all. Explicit cleanup happens in the `"dispose"` method call handler (identity-guarded) and in `closePublication()`. See [iOS Platform - Global Reference Lifecycle](platform-specific/ios.md#global-reference-lifecycle).

### iOS: Crash on ttsSetPreferences with Null voiceIdentifier

**Symptom:**
```
Could not cast value of type 'NSNull' to 'NSString'
```
App crashes when calling `ttsSetPreferences` — for example, tapping the speed button during TTS playback when no voice was explicitly set.

**Cause:**
The `ttsSetPreferences` handler in `FlureadiumPlugin.swift` used a forced cast (`as! Dictionary<String, String>`) on the method channel arguments. When `TTSPreferences` has a null `voiceIdentifier` (the default — system voice), Flutter serializes null as `NSNull`, which cannot be cast to `NSString`.

**Fix (applied):**
Changed the cast to match the safe pattern used by `ttsEnable`: `as? Dictionary<String, Any> ?? [:]`. The downstream `TTSPreferences(fromMap:)` already uses optional casts (`as? String`) for nullable fields, so it handles nulls correctly once the arguments arrive.

### iOS: "No publication open" After Switching Publications

**Error:**
```
PlatformException(InvalidArgument, No publication open)
```

**Cause:**
This happened when `closePublication()` in `FlureadiumPlugin.swift` used a fire-and-forget `Task { @MainActor in }` for cleanup. When `openPublication` called `closePublication()` internally before loading a new publication, the cleanup task ran *after* the new publication was already stored — nullifying `currentPublication`. Any subsequent call (`audioEnable`, `play`, etc.) would fail because the publication reference was gone.

**Fix (applied):**
`closePublication()` is now `async` and uses `await MainActor.run { }` so callers wait for cleanup to complete before proceeding. The `openPublication`, `closePublication`, `dispose`, and `stop` method channel handlers all await cleanup before returning `result(nil)` to Dart.

### iOS: App Freezes on Chapter Change, Seek, or End of Track (Audiobook)

**Symptom:**
The iOS UI goes unresponsive when an audiobook changes chapter, seeks to a locator, or reaches the end of a track and auto-advances. The app does not crash — it hangs, and the main thread is blocked in `__ulock_wait`.

**Cause:**
The audio delegate callbacks read `_audioNavigator?.playbackInfo` synchronously. That read calls `AVPlayer.currentTime()`, which re-enters AVPlayer's lock — but the callback already runs inside `AudioNavigator.go(to:)`, which holds that same lock while mutating the player. The re-entrant read blocks waiting for a lock the same thread owns, so the navigator deadlocks itself on every transition.

**Fix (applied):**
`FlutterAudioNavigator` now caches the `MediaPlaybackInfo` that Readium delivers off-lock to `playbackDidChange`, and the last `Locator` from `locationDidChange`. The two transition callbacks serve their state from those cached values instead of reading back into the live navigator, so nothing re-enters the AVPlayer lock.

### iOS: "TTS Navigator not initialized" From a Voice Query After TTS Stops

**Symptom:**
```
PlatformException(TTSError, TTS Navigator not initialized, null, null)
```
Thrown from `ttsGetAvailableVoices()`, often after the exception has already escaped the call that started it, so the stack points at whatever code was running when it surfaced. Distinct from the stop-then-re-enable case below, where `ttsEnable()` itself fails.

**Cause:**
iOS raised for a voice query with no TTS session installed, while Android returned an empty list and Web queried the browser directly. Any caller whose voice query outlived its session — a user tapping stop while an enable sequence was still resolving, for instance — got a fatal error on iOS only.

**Fix (applied):**
`ttsGetAvailableVoices` now answers an empty list when no `FlutterTTSNavigator` is installed, so a voice query for a session that has gone away is benign on Android, iOS, and Web. `ttsSetVoice` and `ttsSetPreferences` still fail without a session: they mutate one.

### iOS: "TTS Navigator not initialized" After Stop Then Re-enable

**Symptom:**
```
PlatformException(..., TTS Navigator not initialized)
```
Enabling TTS (or opening another audio session) right after stopping playback fails, even though the new navigator was just created. Distinct from the voice-query case above, which carries the same message but comes from `ttsGetAvailableVoices()`.

**Cause:**
`stop` disposes the timebased navigator on a detached main-actor task, so teardown runs after the call returns. If a newer session installs its own navigator before that straggler teardown runs, the late teardown nils it out and leaves the shared slot empty.

**Fix (applied):**
`stop` now captures the navigator to tear down at call time and clears the shared slot only when it still holds that same navigator (`teardownTimebasedNavigator`). A straggler teardown from a prior session can no longer clear a navigator a newer session installed.

### Android: Spurious `JobCancellationException` on Close

**Symptom:**
```
PlatformException(class kotlinx.coroutines.JobCancellationException, ...)
```
Closing a publication while an audiobook `play` (or another suspending call) is still in flight surfaces a platform exception to Dart, even though nothing actually failed.

**Cause:**
The publication method-channel handler caught every exception and forwarded it to Dart via `result.error`. When the publication closes, the coroutine running the in-flight call is cancelled and throws `CancellationException` — normal unwinding, not a failure — which was reported as a spurious error.

**Fix (applied):**
`dispatchGuarded` re-throws `CancellationException` instead of reporting it, so a coroutine torn down mid-call unwinds normally and no phantom `PlatformException` reaches Dart.

### Android: App Killed on Close with "zip file closed" or "Inflater has been closed"

**Symptom:**
```
FATAL EXCEPTION: main
java.lang.IllegalStateException: zip file closed
	at java.util.zip.ZipFile.ensureOpen(ZipFile.java:753)
	at org.readium.r2.shared.util.zip.FileZipContainer$Entry$readFully$2.invokeSuspend(FileZipContainer.kt:97)
```
or, when the read had already started streaming:
```
FATAL EXCEPTION: main
java.lang.NullPointerException: Inflater has been closed
	at java.util.zip.Inflater.ensureOpen(Inflater.java:416)
	at java.util.zip.InflaterInputStream.read(InflaterInputStream.java:172)
```
The app dies outright, with no Dart error and no exception reaching your code. Closing a publication is what triggers it, and it needs a read still in flight, so it shows up on CBZ and DIVINA where the image navigator reads whole pages. It is timing dependent: the window is around 150 ms wide, and in CI it hit about one run in fifteen.

**Cause:**
`closePublication()` closes the backing `ZipFile`. Removing the navigator fragment cancels readium's page fragment, but cancellation is cooperative, so a read already inside `withContext(Dispatchers.IO)` keeps going and reaches the closed container. Which exception you get depends on how far it had got: `ZipFile.ensureOpen` before the entry stream opens, `Inflater.ensureOpen` once it is streaming. readium 3.1.2 catches `ZipException` and `IOException` in `FileZipContainer.Entry.read()` and neither of these, so the throw escapes the `Try<ByteArray, ReadError>` the method declares. It surfaces in `R2CbzPageFragment`, whose `coroutineContext` is `Dispatchers.Main` with no `Job`: that read is a parentless root coroutine, so no `CoroutineExceptionHandler` anywhere can reach it and the default handler kills the process.

**Fix (applied):**
Resources are wrapped at open time in a guard that reports a read against a closed container as `ReadError.Access`, which is what readium's own `read()` signature promises. The page render fails and the fragment is torn down regardless, so nothing is lost. The guard matches the two exact messages above and nothing else, so a genuine null dereference in a transformer still surfaces, and it re-throws `CancellationException` first, since that subclasses `IllegalStateException`. The race itself is upstream in readium and unchanged.

### Android: App Killed by Any Reader Exception, With Nothing Reaching Dart

**Symptom:**
```
FATAL EXCEPTION: main
java.lang.Exception: Publication is not an EPUB, cannot enable epub navigator
	at dev.mulev.flureadium.ReadiumReader.epubEnable(ReadiumReader.kt:783)
```
The app dies. No error event, no `error` reader status, nothing thrown into
Dart. In an integration run everything after it reports `did not complete`,
which makes the first failure look like a suite-wide collapse.

**Cause:**
Every reader scope was `CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)`
with no `CoroutineExceptionHandler`. A supervisor's direct children are root
coroutines, so a failure had nowhere to go: `handleCoroutineException` found no
handler in the context and fell through to the thread's uncaught handler, which
on Android is `RuntimeInit.KillApplicationHandler` and calls
`Process.killProcess`. `SupervisorJob` keeps a failing child from cancelling its
siblings; it does not handle the exception.

**Fix (applied):**
`readerCoroutineExceptionHandler` is installed on all three reader scopes — the
widget, the `ReadiumReader` singleton, and `BaseNavigator`. It logs the
throwable, sets reader status to `error`, and sends an error event with code
`ReaderFailure`, the exception message, and the stack trace as `data`. A widget
only reports while it still owns the reader registration, so a stale platform
view's failure cannot describe the session that replaced it. Cancellation is
never handed to a handler, so `dispose()` and `detach()` stay silent.

Two adjacent holes closed with it: the reader method channel answers a failed
call with `result.error` instead of leaving the Dart future pending, and the
error channel holds errors sent before Dart subscribes, so a failure reported
during platform-view creation still reaches the first subscriber.

## Platform-Specific Issues

### iOS: Localhost Connection Failed

**Error:**
```
The resource could not be loaded because the App Transport Security policy requires the use of a secure connection.
```

**Solution:**
Add to `ios/Runner/Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### Android: WebView Issues

**Symptoms:**
- Content not rendering properly
- JavaScript errors

**Solutions:**
1. Enable hardware acceleration in AndroidManifest.xml:
   ```xml
   <application android:hardwareAccelerated="true">
   ```

2. Check minimum SDK version is 24+

### Web: CORS Errors

**Error:**
```
Access to fetch at 'file://' from origin 'http://localhost' has been blocked by CORS
```

**Cause:**
Loading local files from web.

**Solution:**
Serve files from a web server or use asset bundling.

## Performance Issues

### Slow Page Turns

**Possible Causes:**
1. Large images in EPUB
2. Complex CSS
3. Many decorations

**Solutions:**
1. Use paginated mode instead of scroll:
   ```dart
   EPUBPreferences(verticalScroll: false)
   ```

2. Limit number of decorations
3. Consider EPUB optimization

### High Memory Usage

**Possible Causes:**
1. Large publication
2. Many resources loaded
3. Memory leak

**Solutions:**
1. Close publication when done:
   ```dart
   await flureadium.closePublication();
   ```

2. Dispose of subscriptions:
   ```dart
   @override
   void dispose() {
     _subscription?.cancel();
     super.dispose();
   }
   ```

### Stream Subscription Leaks

**Symptoms:**
- Memory growing over time
- Multiple callbacks firing

**Solution:**
Always cancel subscriptions:
```dart
class _MyState extends State<MyWidget> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = flureadium.onTextLocatorChanged.listen((loc) {
      // handle
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
```

## Debugging Tips

### Enable Logging

```dart
flureadium.onErrorEvent.listen((error) {
  debugPrint('Flureadium Error: ${error.message}');
  debugPrint('Code: ${error.code}');
  debugPrint('Data: ${error.data}');
});
```

### Check Publication Info

```dart
final pub = await flureadium.openPublication(path);
debugPrint('Title: ${pub.metadata.title}');
debugPrint('Identifier: ${pub.identifier}');
debugPrint('Reading order: ${pub.readingOrder.length} items');
debugPrint('TOC: ${pub.tableOfContents.length} items');
debugPrint('Is audiobook: ${pub.conformsToReadiumAudiobook}');
debugPrint('Has overlays: ${pub.containsMediaOverlays}');
```

### Verify Locator

```dart
flureadium.onTextLocatorChanged.listen((locator) {
  debugPrint('Href: ${locator.href}');
  debugPrint('Type: ${locator.type}');
  debugPrint('Progress: ${locator.locations?.totalProgression}');
  debugPrint('JSON: ${locator.json}');
});
```

## Getting Help

If you can't resolve an issue:

1. Check the [example app](../example/) for working code
2. Review the [error handling guide](guides/error-handling.md)
3. Search existing [GitHub issues](https://github.com/mulev/flureadium/issues)
4. Open a new issue with:
   - Flutter version (`flutter --version`)
   - Platform (iOS, Android, Web, macOS)
   - Error messages and stack traces
   - Minimal reproduction code

## See Also

- [Installation](getting-started/installation.md) - Setup guide
- [Error Handling](guides/error-handling.md) - Exception types
- [Platform-Specific Docs](platform-specific/) - Platform details
