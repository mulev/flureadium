import Flutter
import WebKit

/// The scripts injected into the EPUB WebView.
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
    scripts.append(
      WKUserScript(
        source: pointerSettleSource, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    return scripts
  }

  /// Read by our helper JS to branch on platform.
  static let platformFlagsSource = "const isAndroid=false,isIos=true;"

  /// The settle entry point `pointerSettleSource` installs on `window`.
  static let settleFunctionName = "__flureadiumSettlePointers"

  /// The handler each document posts to once, so native learns its web view.
  static let spreadReadyMessageName = "flureadiumSpreadReady"

  /// Tracks the pointer ids this document holds, and cancels them on demand.
  ///
  /// Readium disables interaction on the shared pagination view for the length
  /// of a page transition. A touch still in flight then dies without WebKit
  /// dispatching `pointerup`, so the page never terminates that pointer id and
  /// Readium's tap recognisers keep it active forever — swallowing every later
  /// tap, including Readium's own `didTapAt`. `SpreadPointerSettler` calls the
  /// settle function after each navigation; each part of the dispatch clears one
  /// filter Readium applies before any observer sees the event:
  ///
  ///     document.body      its ancestor walk finds no interactive element
  ///     cancelable: false  preventDefault() is a no-op, defaultPrevented stays false
  ///     clientX/Y: -1      matches no activable decoration rect
  ///     bubbles: true      reaches Readium's document-level pointercancel listener
  ///
  /// The location is irrelevant to the outcome: a cancel is keyed on pointer id.
  ///
  /// A settle cannot tell a stranded id from a finger that is genuinely still
  /// down, and nothing in the page can: a strand differs from a live press only
  /// in what WebKit will do next. Readium restores interaction before the
  /// navigation call returns, so a press that begins between that moment and the
  /// settle is cancelled with the strand and loses its tap. An age cutoff was
  /// considered and rejected — a non-animated `go` strands a pointer younger
  /// than a held finger, so no threshold separates them. The trade is one
  /// dropped tap in a window a few hundred milliseconds wide, against a reader
  /// whose taps never work again.
  static let pointerSettleSource = """
    (function() {
        var live = {};

        document.addEventListener('pointerdown', function(e) {
            live[e.pointerId] = e.pointerType;
        }, true);

        ['pointerup', 'pointercancel'].forEach(function(name) {
            document.addEventListener(name, function(e) { delete live[e.pointerId]; }, true);
        });

        window.\(settleFunctionName) = function() {
            var target = document.body || document.documentElement;
            if (target) {
                Object.keys(live).forEach(function(id) {
                    target.dispatchEvent(new PointerEvent('pointercancel', {
                        pointerId: Number(id),
                        pointerType: live[id] || 'touch',
                        bubbles: true,
                        cancelable: false,
                        clientX: -1,
                        clientY: -1
                    }));
                });
                live = {};
            }
            // A fixed-layout spread holds the resource in an iframe, and the
            // settle is driven per web view rather than per frame, so the parent
            // hands the call down. Same origin under Readium's server. A
            // cross-origin child throws here and keeps its own live ids. Two
            // routes would close that and neither is taken: a `message`
            // listener in the child, settled by `postMessage` from this loop,
            // would accept a settle from any origin; and evaluating natively in
            // the `WKFrameInfo` the ready post already carries needs
            // `evaluateJavaScript(_:in:contentWorld:)` behind an iOS 14 gate,
            // for a case no EPUB in hand produces.
            for (var i = 0; i < window.frames.length; i++) {
                try { window.frames[i].\(settleFunctionName)?.(); } catch (e) {}
            }
        };

        try {
            window.webkit.messageHandlers.\(spreadReadyMessageName).postMessage(null);
        } catch (e) {}
    })();
    """

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
