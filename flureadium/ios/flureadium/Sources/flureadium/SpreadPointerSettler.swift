import WebKit

/// Cancels the pointer ids a spread's document still holds.
///
/// Each spread announces itself at document start through
/// `EpubUserScripts.spreadReadyMessageName`, which is the only route to *every*
/// spread: `EPUBNavigatorViewController.evaluateJavaScript` reaches the current
/// one, and the stranded pointer is not always there. References are weak
/// because `PaginationView` creates and discards spread views as the reader
/// moves.
///
/// Main-actor isolated: the registry is mutated from the script-message
/// callback and read from the navigation call sites, and both are main-thread
/// paths today. Stating it keeps an off-main caller a compile error rather than
/// a hash-table race.
@MainActor
final class SpreadPointerSettler: NSObject, WKScriptMessageHandler {

  private let spreads = NSHashTable<WKWebView>.weakObjects()

  /// Subscribes to the document-start post that announces each spread.
  func register(on userContentController: WKUserContentController) {
    userContentController.add(self, name: EpubUserScripts.spreadReadyMessageName)
  }

  /// Dispatches `pointercancel` for every pointer id the known documents still
  /// hold. Returns the number of spreads reached.
  @discardableResult
  func settle() -> Int {
    let live = spreads.allObjects
    for spread in live {
      spread.evaluateJavaScript(
        "window.\(EpubUserScripts.settleFunctionName)?.()", completionHandler: nil)
    }
    return live.count
  }

  /// How many spreads the registry still holds.
  ///
  /// Reading this dispatches nothing, and leaves nothing alive. `settle()`
  /// cannot answer the same question: it evaluates JavaScript on every live
  /// spread, and WebKit retains a web view for the duration of that call.
  ///
  /// The pool matters as much as the absent dispatch. `allObjects` hands back
  /// an autoreleased array that strongly references its contents, so a caller
  /// polling this in a loop would pile those arrays into whatever pool encloses
  /// it, and a spread one poll saw alive could not die until that pool drained.
  /// Draining here keeps the reading free of the effect it measures.
  var trackedSpreadCount: Int { autoreleasepool { spreads.allObjects.count } }

  /// Adds one spread to the registry.
  ///
  /// Separate from the message handler because `WKScriptMessage` has no public
  /// initialiser: without this, the only way to put a spread in the registry is
  /// to load a document in a real web view, which is a WebKit dependency the
  /// fan-out behaviour does not otherwise have.
  func register(spread: WKWebView) {
    // Every frame of every spread posts, so the same web view arrives more than
    // once; the hash table keys on identity and keeps one entry.
    spreads.add(spread)
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard let webView = message.webView else { return }
    register(spread: webView)
  }
}
