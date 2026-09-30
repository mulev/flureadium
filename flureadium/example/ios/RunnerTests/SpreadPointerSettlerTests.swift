import WebKit
import XCTest

@testable import flureadium

/// Behaviour tests for `SpreadPointerSettler` against real `WKWebView`s running
/// the real settle script.
///
/// `bridgeSource` stands in for Readium's own bridge. It is injected as a user
/// script into every frame, as Readium injects its own, and reports the fields
/// `EPUBSpreadView.didReceivePointerEvent` reads before any observer sees the
/// event. A payload that fails one of those filters is dropped by Readium, so
/// the dispatch shape is asserted here rather than by matching the script's
/// source text.
@MainActor
final class SpreadPointerSettlerTests: XCTestCase {

    /// The anchor matters: Readium walks ancestors for an interactive element,
    /// so a cancel dispatched on the recorded target would carry the `<a>` and
    /// be dropped.
    private let markup = "<a href='chapter2.xhtml'><span id='word'>tap me</span></a>"

    /// The `preventDefault` listener matters for the same reason — it is a
    /// no-op only while the event stays non-cancelable.
    private let bridgeSource = """
        document.addEventListener('pointercancel', function(e) { e.preventDefault(); }, true);
        document.addEventListener('pointercancel', function(e) {
          var interactive = e.target.closest ? e.target.closest('a') : null;
          window.webkit.messageHandlers.pointerEventReceived.postMessage({
            phase: 'cancel',
            pointerId: e.pointerId,
            pointerType: e.pointerType,
            defaultPrevented: e.defaultPrevented,
            interactiveElement: interactive ? interactive.outerHTML : null,
            clientX: e.clientX
          });
        });
        """

    // MARK: - Tests

    func testSettleCancelsTheLivePointerThroughTheBridge() {
        let settler = SpreadPointerSettler()
        let bridge = PointerEventRecorder()
        let webView = loadSpread(settler: settler, bridge: bridge)

        press(pointerId: 42, in: webView)
        settler.settle()

        let payload = bridge.awaitPayload(self)
        XCTAssertEqual(payload?["phase"] as? String, "cancel", "Readium heals on a cancel phase")
        XCTAssertEqual(payload?["pointerId"] as? Int, 42, "the stranded id is the one that must be cleared")
        XCTAssertEqual(payload?["pointerType"] as? String, "touch", "both observers ignore non-touch pointers")
    }

    /// Without this, deleting the script's `pointerup`/`pointercancel`
    /// listeners would leave every other case green while turning each
    /// navigation into a source of cancels for pointers the page finished
    /// cleanly.
    func testSettleIgnoresAPointerThatAlreadyEnded() {
        let settler = SpreadPointerSettler()
        let bridge = PointerEventRecorder()
        let webView = loadSpread(settler: settler, bridge: bridge)

        press(pointerId: 3, in: webView)
        dispatch("pointerup", pointerId: 3, in: webView)
        XCTAssertEqual(
            settler.settle(), 1,
            "an unregistered spread would make the empty recorder below prove nothing")

        // Ordered after the settle's own evaluation on the same web view.
        evaluate("void 0;", in: webView)
        XCTAssertTrue(
            bridge.payloads.isEmpty, "a pointer the page terminated itself is not stranded")
    }

    func testSettledPayloadClearsReadiumsPreObserverFilters() {
        let settler = SpreadPointerSettler()
        let bridge = PointerEventRecorder()
        let webView = loadSpread(settler: settler, bridge: bridge)

        press(pointerId: 7, in: webView)
        settler.settle()

        let payload = bridge.awaitPayload(self)
        XCTAssertTrue(
            payload?["interactiveElement"] is NSNull,
            "dispatching on document.body keeps the ancestor walk off the enclosing <a>"
        )
        XCTAssertEqual(
            payload?["defaultPrevented"] as? Bool,
            false,
            "a non-cancelable event survives a page that calls preventDefault"
        )
        XCTAssertEqual(
            payload?["clientX"] as? Int,
            -1,
            "negative coordinates match no activable decoration rect, which would swallow the post"
        )
    }

    /// Positive control for the assertion above: the stub bridge does report an
    /// interactive element when the cancel lands where the touch did. Without
    /// this, a bridge that never reported one would make that test vacuous —
    /// and a settle dispatched on the recorded target is the mistake the
    /// investigation made and Readium silently drops.
    func testCancelOnTheTouchTargetWouldCarryTheEnclosingLink() {
        let settler = SpreadPointerSettler()
        let bridge = PointerEventRecorder()
        let webView = loadSpread(settler: settler, bridge: bridge)

        dispatch("pointercancel", pointerId: 9, in: webView)

        XCTAssertTrue(
            (bridge.awaitPayload(self)?["interactiveElement"] as? String)?.contains("<a") == true,
            "Readium's ancestor walk finds the link, so such a payload never reaches an observer"
        )
    }

    func testSettleReachesEveryRegisteredSpread() {
        let settler = SpreadPointerSettler()
        let bridge = PointerEventRecorder(expected: 2)
        let first = loadSpread(settler: settler, bridge: bridge)
        let second = loadSpread(settler: settler, bridge: bridge)

        press(pointerId: 11, in: first)
        press(pointerId: 22, in: second)
        settler.settle()

        bridge.awaitPayload(self)
        XCTAssertEqual(
            Set(bridge.payloads.compactMap { $0["pointerId"] as? Int }),
            [11, 22],
            "the strand can sit in a spread that is not the current one"
        )
    }

    /// A fixed-layout spread holds its resource in an iframe, and the settle is
    /// driven per web view rather than per frame, so the parent document has to
    /// hand the call down. Without that walk the whole fixed-layout path keeps
    /// stranding while the settler reports success.
    func testSettleReachesAPointerInsideASubframe() {
        let settler = SpreadPointerSettler()
        let bridge = PointerEventRecorder()
        let webView = loadSpread(settler: settler, bridge: bridge, withSubframe: true)

        evaluate(
            """
            document.getElementById('spread').contentDocument.getElementById('word').dispatchEvent(
              new PointerEvent('pointerdown', { pointerId: 55, pointerType: 'touch', bubbles: true }));
            """,
            in: webView)
        settler.settle()

        XCTAssertEqual(
            bridge.awaitPayload(self)?["pointerId"] as? Int,
            55,
            "the pointer stranded in the iframe, which is where the touch landed"
        )
    }

    func testReleasedSpreadIsDropped() {
        let settler = SpreadPointerSettler()
        autoreleasepool {
            let webView = loadSpread(settler: settler, bridge: PointerEventRecorder())
            XCTAssertEqual(settler.settle(), 1)
            webView.stopLoading()
        }

        // Polls `trackedSpreadCount`, never `settle()`. Every `settle()` call
        // evaluates JavaScript on each live spread, and WebKit retains a web
        // view until that call answers — so a loop that polls `settle()` keeps
        // the spread alive by asking whether it is gone. On CI, where those
        // evaluations queue, the case burned its whole ceiling doing that on
        // 2026-09-30.
        let deadline = Date(timeIntervalSinceNow: asyncTimeout)
        while settler.trackedSpreadCount != 0, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertEqual(
            settler.trackedSpreadCount, 0,
            "PaginationView discards spreads as the reader moves; the registry must not retain them")
    }

    // MARK: - Harness

    /// Ceiling for a spread's first paint, separate from `asyncTimeout` because
    /// it covers something no other wait in this target does: the first
    /// `WKWebView` in the process launches WebKit's Networking and WebContent
    /// processes before any load can finish. Across three CI runs, whichever
    /// case ran first in this suite paid it — 13.8 s on one runner, past 60 s
    /// on another — while every later case in the same process finished inside
    /// 15 s. Nothing here is slow; a cold WebKit is.
    private let spreadLoadTimeout: TimeInterval = 240

    /// Builds a spread web view carrying the real settle script and the stub
    /// bridge, loads a document, and returns once the settle script has
    /// announced the web view — the same document-start post the plugin needs.
    private func loadSpread(
        settler: SpreadPointerSettler, bridge: PointerEventRecorder, withSubframe: Bool = false
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        for source in [EpubUserScripts.pointerSettleSource, bridgeSource] {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        settler.register(on: configuration.userContentController)
        configuration.userContentController.add(bridge, name: "pointerEventReceived")

        let body =
            withSubframe
            ? "<iframe id='spread' srcdoc=\"\(markup)\"></iframe>"
            : markup
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        let loaded = LoadRecorder(expectation: expectation(description: "spread loaded"))
        webView.navigationDelegate = loaded
        webView.loadHTMLString("<html><body>\(body)</body></html>", baseURL: nil)
        wait(for: [loaded.expectation], timeout: spreadLoadTimeout)
        return webView
    }

    /// Leaves a live pointer id in the document, on a target inside the anchor.
    private func press(pointerId: Int, in webView: WKWebView) {
        dispatch("pointerdown", pointerId: pointerId, in: webView)
    }

    /// Dispatches one pointer event on the anchor's child, where a real touch
    /// would land.
    private func dispatch(_ type: String, pointerId: Int, in webView: WKWebView) {
        evaluate(
            """
            document.getElementById('word').dispatchEvent(
              new PointerEvent('\(type)', { pointerId: \(pointerId), pointerType: 'touch', bubbles: true }));
            """,
            in: webView)
    }

    private func evaluate(_ javaScript: String, in webView: WKWebView) {
        let evaluated = expectation(description: "evaluated")
        webView.evaluateJavaScript(javaScript) { _, _ in evaluated.fulfill() }
        wait(for: [evaluated], timeout: asyncTimeout)
    }
}

/// Collects the payloads a stub Readium bridge posts back.
private final class PointerEventRecorder: NSObject, WKScriptMessageHandler {
    private(set) var payloads: [[String: Any]] = []
    private let received: XCTestExpectation

    init(expected: Int = 1) {
        received = XCTestExpectation(description: "pointer events received")
        received.expectedFulfillmentCount = expected
    }

    @discardableResult
    func awaitPayload(_ test: XCTestCase) -> [String: Any]? {
        test.wait(for: [received], timeout: asyncTimeout)
        return payloads.first
    }

    func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard let payload = message.body as? [String: Any] else { return }
        payloads.append(payload)
        received.fulfill()
    }
}

/// Fulfils its expectation when the stub document has finished loading.
private final class LoadRecorder: NSObject, WKNavigationDelegate {
    let expectation: XCTestExpectation

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        expectation.fulfill()
    }
}
