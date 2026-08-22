import ReadiumShared

private let TAG = "EpubPageBridge"

/// The `window.epubPage` JavaScript API, injected into the EPUB WebView by
/// `EpubUserScripts`.
///
/// `evaluate` comes from the reader view, so tests can assert the JavaScript
/// without a WebView. A failed evaluation is never fatal: the call logs and
/// returns nil, or hands the caller Readium's own `Result` to deal with.
@MainActor
struct EpubPageBridge {
  let evaluate: @MainActor (String) async -> Result<Any, Error>

  /// The raw reply from the fragment resolver. The method channel returns this
  /// value to Dart unchanged, so it cannot go through the parsing variant.
  func locatorFragmentsResult(locatorJson: String, isScrollMode: Bool) async -> Result<Any, Error> {
    await evaluate("window.epubPage.getLocatorFragments(\(locatorJson), \(isScrollMode));")
  }

  /// Resolves DOM fragments for `locatorJson`, which the Dart side needs to
  /// persist a position that survives a re-layout.
  func locatorFragments(locatorJson: String, isScrollMode: Bool) async -> Locator? {
    switch await locatorFragmentsResult(locatorJson: locatorJson, isScrollMode: isScrollMode) {
    case let .success(value):
      guard let locator = parseLocatorFragmentsResult(value) else {
        print(TAG, "locatorFragments: failed to parse locator from JS result")
        return nil
      }
      return locator
    case let .failure(error):
      print(TAG, "locatorFragments failed! \(error)")
      return nil
    }
  }

  func scroll(toLocations json: String, isScrollMode: Bool, toStart: Bool) async {
    print(TAG, "scroll: Go to locations \(json), toStart: \(toStart)")
    _ = await evaluate("window.epubPage.scrollToLocations(\(json),\(isScrollMode),\(toStart));")
  }

  func setLocation(locatorJson: String, isAudioBookWithText: Bool) async -> Result<Any, Error> {
    await evaluate("window.epubPage.setLocation(\(locatorJson), \(isAudioBookWithText));")
  }

  func isLocatorVisible(locatorJson: String) async -> Result<Any, Error> {
    await evaluate("window.epubPage.isLocatorVisible(\(locatorJson));")
  }

  /// Wrapped in existence checks: the host can ask before the helper script ran.
  func isReaderReady() async -> Result<Any, Error> {
    await evaluate("""
          (function() {
              if (typeof window.epubPage !== 'undefined' && typeof window.epubPage.isReaderReady === 'function') {
                  return window.epubPage.isReaderReady();
              } else {
                  return false;
              }
          })();
      """)
  }
}

/// Reads a locator out of a `window.epubPage` reply. Readium hands back `()`
/// when the JavaScript side yields null, so the dictionary cast comes first.
func parseLocatorFragmentsResult(_ result: Any?) -> Locator? {
  guard let json = result as? Dictionary<String, Any?> else {
    return nil
  }

  return try? Locator(json: json, warnings: readiumBugLogger)
}
