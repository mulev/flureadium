import Flutter
import WebKit

/// The scripts injected into the EPUB WebView, in injection order.
enum EpubUserScripts {

  /// Loads the bundled helper assets through `registrar` and builds the scripts.
  static func make(registrar: FlutterPluginRegistrar) -> [WKUserScript] {
    func asset(_ name: String) -> Data {
      let key = registrar.lookupKey(forAsset: name, fromPackage: "flureadium")
      let path = Bundle.main.path(forResource: key, ofType: nil)!
      return FileManager().contents(atPath: path)!
    }
    return make(
      js: [asset("assets/helpers/comics.js"), asset("assets/helpers/epub.js")],
      css: [asset("assets/helpers/comics.css"), asset("assets/helpers/epub.css")]
    )
  }

  /// JavaScript goes in before the document loads; CSS is injected after it, so
  /// the page's own styles are already in the tree when ours lands on top.
  static func make(js: [Data], css: [Data]) -> [WKUserScript] {
    var scripts = js.map {
      WKUserScript(
        source: String(data: $0, encoding: .utf8)!,
        injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
    scripts.append(
      WKUserScript(
        source: platformFlagsSource, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    scripts += css.map {
      WKUserScript(
        source: cssInjectionSource(base64: $0.base64EncodedString()),
        injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }
    scripts.append(
      WKUserScript(
        source: clickSynthesisSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    return scripts
  }

  /// Read by our helper JS to branch on platform.
  static let platformFlagsSource = "const isAndroid=false,isIos=true;"

  /// Appends a `style` element carrying the decoded payload to the document head.
  ///
  /// The stylesheet travels base64-encoded because it goes into a JavaScript
  /// string literal, where its own quotes and newlines would otherwise break out.
  static func cssInjectionSource(base64: String) -> String {
    """
    (function() {
    var parent = document.getElementsByTagName('head').item(0);
    var style = document.createElement('style');
    style.type = 'text/css';
    style.innerHTML = window.atob('\(base64)');
    parent.appendChild(style)})();
    """
  }

  /// Flutter's synthetic touch delivery prevents WKWebView from dispatching a
  /// native click after goLeft/goRight when WKContentView is oversized. This
  /// watches pointerup and synthesises the click if none arrives in 50 ms.
  static let clickSynthesisSource = """
    (function() {
        var pendingClickTimer = null;
        var lastPointerDownPos = null;

        document.addEventListener('pointerdown', function(e) {
            lastPointerDownPos = { x: e.clientX, y: e.clientY };
        }, true);

        document.addEventListener('pointerup', function(e) {
            if (!lastPointerDownPos) return;
            var dx = e.clientX - lastPointerDownPos.x;
            var dy = e.clientY - lastPointerDownPos.y;
            if (Math.sqrt(dx * dx + dy * dy) > 10) return;

            var x = e.clientX;
            var y = e.clientY;
            var target = e.target;

            if (pendingClickTimer) clearTimeout(pendingClickTimer);
            pendingClickTimer = setTimeout(function() {
                pendingClickTimer = null;
                var clickEvent = new MouseEvent('click', {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: x,
                    clientY: y,
                    button: 0
                });
                target.dispatchEvent(clickEvent);
            }, 50);
        }, true);

        document.addEventListener('click', function(e) {
            if (pendingClickTimer) {
                clearTimeout(pendingClickTimer);
                pendingClickTimer = null;
            }
        }, true);
    })();
    """
}
