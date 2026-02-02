# Flutter Readium Fork: Gesture State Fix

## Problem

After using overlay navigation buttons (`goLeft()`/`goRight()`), links in book content stop working.

## Root Cause

Bug in flutter_readium's native iOS code at `ReadiumReaderView.swift` lines 367-388.

When `goLeft()` or `goRight()` is called programmatically:
1. The native `EPUBNavigatorViewController.goLeft()` is called via platform channel
2. The WebView reloads content for the new page
3. **But gesture recognizers are NOT reset** after navigation completes
4. The `DirectionalNavigationAdapter`'s gesture recognizers remain in a stale state
5. Link tap handlers don't properly re-register with the new page content

## Evidence

- Pointer down/up events ARE received by Flutter's Listener
- Platform view IS receiving touches (`_enableWakelock` logs prove this)
- But links don't activate because native gesture state is stale

## Fix

### File to Modify

`flutter_readium/ios/flutter_readium/Sources/flutter_readium/ReadiumReaderView.swift`

### Changes

#### goLeft handler (lines 367-377)

**Before:**
```swift
case "goLeft":
  let animated = call.arguments as! Bool
  let readiumViewController = self.readiumViewController

  Task.detached(priority: .high) {
    let success = await readiumViewController.goLeft(options: NavigatorGoOptions(animated: animated))
    await MainActor.run() {
      result(success)
    }
  }
  break
```

**After:**
```swift
case "goLeft":
  let animated = call.arguments as! Bool
  let readiumViewController = self.readiumViewController

  Task.detached(priority: .high) {
    let success = await readiumViewController.goLeft(options: NavigatorGoOptions(animated: animated))
    // Reset gesture recognizer state after navigation
    await MainActor.run() {
      readiumViewController.view.isUserInteractionEnabled = false
      readiumViewController.view.isUserInteractionEnabled = true
      result(success)
    }
  }
  break
```

#### goRight handler (lines 378-388)

Apply the same fix - add gesture reset before `result(success)`:
```swift
readiumViewController.view.isUserInteractionEnabled = false
readiumViewController.view.isUserInteractionEnabled = true
```

## Steps to Apply

1. **Fork the repository**
   - Go to: https://github.com/Notalib/flutter_readium
   - Click "Fork" to create your own copy

2. **Clone your fork**
   ```bash
   git clone https://github.com/YOUR_USERNAME/flutter_readium.git
   cd flutter_readium
   ```

3. **Create a branch**
   ```bash
   git checkout -b gesture-fix
   ```

4. **Edit the Swift file**
   - Open: `flutter_readium/ios/flutter_readium/Sources/flutter_readium/ReadiumReaderView.swift`
   - Apply the changes above to lines 367-388

5. **Commit and push**
   ```bash
   git add .
   git commit -m "Fix gesture state after programmatic navigation

   After goLeft/goRight, reset gesture recognizers by toggling
   isUserInteractionEnabled. This fixes links not working after
   using navigation buttons.
   "
   git push -u origin gesture-fix
   ```

6. **Update Epist pubspec.yaml**
   ```yaml
   flutter_readium:
     git:
       url: https://github.com/YOUR_USERNAME/flutter_readium
       path: flutter_readium
       ref: gesture-fix
   ```

7. **Test**
   ```bash
   flutter pub get
   flutter run
   ```
   - Open a book with TOC links
   - Double-tap to show overlay
   - Use < or > navigation buttons
   - Double-tap to hide overlay
   - Tap a link in the book content
   - Verify the link works

## Original Source

- Repository: https://github.com/Notalib/flutter_readium
- File: `flutter_readium/ios/flutter_readium/Sources/flutter_readium/ReadiumReaderView.swift`
- Lines: 367-388 (goLeft/goRight handlers)

## Related

- DirectionalNavigationAdapter setup: lines 145-147
- middleTapHandler override: lines 174-176
