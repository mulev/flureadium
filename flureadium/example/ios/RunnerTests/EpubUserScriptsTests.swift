import WebKit
import XCTest

@testable import flureadium

final class EpubUserScriptsTests: XCTestCase {

    private let comicsJs = "/* comics */ var comics = 1;"
    private let epubJs = "/* epub */ var epub = 2;"
    private let comicsCss = "body { color: red; }"
    private let epubCss = "p { margin: 0; }"

    private func makeScripts() -> [WKUserScript] {
        EpubUserScripts.make(
            js: [Data(comicsJs.utf8), Data(epubJs.utf8)],
            css: [Data(comicsCss.utf8), Data(epubCss.utf8)]
        )
    }

    func testMakeReturnsSixScripts() {
        XCTAssertEqual(
            makeScripts().count,
            6,
            "two JS helpers, the platform flags, two CSS injections, and click synthesis"
        )
    }

    func testJavascriptIsInjectedAtDocumentStart() {
        let scripts = makeScripts()

        XCTAssertEqual(scripts[0].injectionTime, .atDocumentStart, "comics.js runs before the document")
        XCTAssertEqual(scripts[1].injectionTime, .atDocumentStart, "epub.js runs before the document")
        XCTAssertEqual(
            scripts[2].injectionTime,
            .atDocumentStart,
            "platform flags are defined before the document loads, last of the three document-start scripts as the pre-refactor build injected them"
        )
    }

    func testCssIsInjectedAtDocumentEnd() {
        let scripts = makeScripts()

        XCTAssertEqual(scripts[3].injectionTime, .atDocumentEnd, "comics.css lands on top of the page's own styles")
        XCTAssertEqual(scripts[4].injectionTime, .atDocumentEnd, "epub.css lands on top of the page's own styles")
        XCTAssertEqual(scripts[5].injectionTime, .atDocumentEnd, "click synthesis needs a loaded document to listen on")
    }

    func testScriptsRunInAllFrames() {
        for (index, script) in makeScripts().enumerated() {
            XCTAssertFalse(
                script.isForMainFrameOnly,
                "script \(index) must reach iframes: EPUB content is frequently framed"
            )
        }
    }

    func testJavascriptSourceIsPassedThroughVerbatim() {
        let scripts = makeScripts()

        XCTAssertEqual(scripts[0].source, comicsJs)
        XCTAssertEqual(scripts[1].source, epubJs)
    }

    func testCssInjectionSourceWrapsBase64Payload() {
        let base64 = Data(epubCss.utf8).base64EncodedString()

        XCTAssertEqual(
            EpubUserScripts.cssInjectionSource(base64: base64),
            """
            (function() {
            var parent = document.getElementsByTagName('head').item(0);
            var style = document.createElement('style');
            style.type = 'text/css';
            style.innerHTML = window.atob('\(base64)');
            parent.appendChild(style)})();
            """
        )
    }

    func testCssScriptsCarryTheirOwnPayload() {
        let scripts = makeScripts()

        XCTAssertTrue(scripts[3].source.contains(Data(comicsCss.utf8).base64EncodedString()))
        XCTAssertTrue(scripts[4].source.contains(Data(epubCss.utf8).base64EncodedString()))
    }

    func testClickSynthesisSourceKeepsThe50msFallback() {
        let source = EpubUserScripts.clickSynthesisSource

        XCTAssertTrue(source.contains("addEventListener('pointerdown'"), "needs the press position")
        XCTAssertTrue(source.contains("addEventListener('pointerup'"), "the fallback is armed on release")
        XCTAssertTrue(source.contains("addEventListener('click'"), "a native click must cancel the fallback")
        XCTAssertTrue(source.contains("> 10) return"), "a drag over 10 px is a scroll, not a tap")
        XCTAssertTrue(source.contains("new MouseEvent('click'"), "the fallback dispatches a real click")
        XCTAssertTrue(source.contains("}, 50);"), "50 ms is the window WKWebView gets to deliver its own click")
    }

    func testPlatformFlagsSourceIsExact() {
        XCTAssertEqual(
            EpubUserScripts.platformFlagsSource,
            "const isAndroid=false,isIos=true;",
            "the helper JS branches on these two globals"
        )
        XCTAssertEqual(makeScripts()[2].source, EpubUserScripts.platformFlagsSource)
    }
}
