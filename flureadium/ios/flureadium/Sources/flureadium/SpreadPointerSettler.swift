import WebKit

/// Cancels the pointer ids a spread's document still holds.
///
/// Each spread announces itself at document start through
/// `EpubUserScripts.spreadReadyMessageName`, which is the only route to *every*
/// spread: `EPUBNavigatorViewController.evaluateJavaScript` reaches the current
/// one, and the stranded pointer is not always there. References are weak
/// because `PaginationView` creates and discards spread views as the reader
/// moves.
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

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    // Every frame of every spread posts, so the same web view arrives more than
    // once; the hash table keys on identity and keeps one entry.
    guard let webView = message.webView else { return }
    spreads.add(webView)
  }
}
