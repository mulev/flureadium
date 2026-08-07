import XCTest
import ReadiumShared
import ReadiumNavigator
@testable import flureadium

// MARK: - Locator Extension Tests

final class LocatorExtensionTests: XCTestCase {

    func testTimeOffsetFromFragment() {
        let locator = Locator(
            href: URL(string: "ch1.xhtml")!,
            mediaType: .html,
            locations: .init(fragments: ["t=1.5"])
        )
        XCTAssertEqual(locator.timeOffset, 1.5)
    }

    func testTimeOffsetNilWhenNoFragment() {
        let locator = Locator(href: URL(string: "ch1.xhtml")!, mediaType: .html)
        XCTAssertNil(locator.timeOffset)
    }

    func testTimeOffsetNilWhenNonTimeFragment() {
        let locator = Locator(
            href: URL(string: "ch1.xhtml")!,
            mediaType: .html,
            locations: .init(fragments: ["#heading1"])
        )
        XCTAssertNil(locator.timeOffset)
    }

    func testTextIdFromHashFragment() {
        let locator = Locator(
            href: URL(string: "ch1.xhtml")!,
            mediaType: .html,
            locations: .init(fragments: ["#heading1"])
        )
        XCTAssertEqual(locator.textId, "heading1")
    }

    func testTextIdFromCssSelector() {
        let locator = Locator(
            href: URL(string: "ch1.xhtml")!,
            mediaType: .html,
            locations: .init(otherLocations: ["cssSelector": "#para5"])
        )
        XCTAssertEqual(locator.textId, "para5")
    }

    func testTextIdNil() {
        let locator = Locator(href: URL(string: "ch1.xhtml")!, mediaType: .html)
        XCTAssertNil(locator.textId)
    }
}

final class LocatorParsingTests: XCTestCase {

    func testParseLocatorFragmentsResultReturnsLocatorForValidJson() {
        let result: [String: Any?] = [
            "href": "https://example.com/ch1.xhtml",
            "type": MediaType.html.string,
            "locations": [
                "fragments": ["#page-1"],
            ],
        ]

        let locator = parseLocatorFragmentsResult(result)

        XCTAssertEqual(locator?.href.string, "https://example.com/ch1.xhtml")
        XCTAssertEqual(locator?.mediaType, .html)
        XCTAssertEqual(locator?.locations.fragments, ["#page-1"])
    }

    func testParseLocatorFragmentsResultReturnsNilForNullJavascriptValue() {
        XCTAssertNil(parseLocatorFragmentsResult(()))
    }

    func testParseLocatorFragmentsResultReturnsNilForMalformedJson() {
        let result: [String: Any?] = [
            "href": "https://example.com/ch1.xhtml",
        ]

        XCTAssertNil(parseLocatorFragmentsResult(result))
    }
}

// MARK: - State Mapping Tests

final class StateMappingTests: XCTestCase {

    // Note: .paused(Utterance) and .playing(Utterance, range:) cannot be tested here
    // because PublicationSpeechSynthesizer.Utterance has an internal initializer
    // (auto-generated memberwise init in Readium module is not public).

    func testSynthesizerStateStoppedMapping() {
        XCTAssertEqual(PublicationSpeechSynthesizer.State.stopped.asTimebasedState, .ended)
    }
}

// MARK: - EPUBPreferences Extension Tests

final class EPUBPreferencesExtensionTests: XCTestCase {

    func testFromMapBackgroundColor() {
        let prefs = EPUBPreferences(fromMap: ["backgroundColor": "#FF0000"])
        XCTAssertNotNil(prefs.backgroundColor)
    }

    func testFromMapFontSize() {
        let prefs = EPUBPreferences(fromMap: ["fontSize": "18.0"])
        XCTAssertEqual(prefs.fontSize, 18.0)
    }

    func testFromMapFontFamily() {
        let prefs = EPUBPreferences(fromMap: ["fontFamily": "Georgia"])
        XCTAssertNotNil(prefs.fontFamily)
    }

    func testFromMapVerticalScroll() {
        let prefs = EPUBPreferences(fromMap: ["verticalScroll": "true"])
        XCTAssertEqual(prefs.scroll, true)
    }

    func testFromMapHyphens() {
        let prefs = EPUBPreferences(fromMap: ["hyphens": "true"])
        XCTAssertEqual(prefs.hyphens, true)
    }

    func testFromMapLineHeight() {
        let prefs = EPUBPreferences(fromMap: ["lineHeight": "1.5"])
        XCTAssertEqual(prefs.lineHeight, 1.5)
    }

    func testFromMapPageMargins() {
        let prefs = EPUBPreferences(fromMap: ["pageMargins": "2.0"])
        XCTAssertEqual(prefs.pageMargins, 2.0)
    }

    func testFromMapTextColor() {
        let prefs = EPUBPreferences(fromMap: ["textColor": "#000000"])
        XCTAssertNotNil(prefs.textColor)
    }

    func testFromMapTextNormalization() {
        let prefs = EPUBPreferences(fromMap: ["textNormalization": "true"])
        XCTAssertEqual(prefs.textNormalization, true)
    }

    func testFromMapVerticalText() {
        let prefs = EPUBPreferences(fromMap: ["verticalText": "true"])
        XCTAssertEqual(prefs.verticalText, true)
    }

    func testFromMapWordSpacing() {
        let prefs = EPUBPreferences(fromMap: ["wordSpacing": "0.25"])
        XCTAssertEqual(prefs.wordSpacing, 0.25)
    }

    func testFromMapLetterSpacing() {
        let prefs = EPUBPreferences(fromMap: ["letterSpacing": "0.1"])
        XCTAssertEqual(prefs.letterSpacing, 0.1)
    }

    func testFromMapParagraphIndent() {
        let prefs = EPUBPreferences(fromMap: ["paragraphIndent": "1.5"])
        XCTAssertEqual(prefs.paragraphIndent, 1.5)
    }

    func testFromMapParagraphSpacing() {
        let prefs = EPUBPreferences(fromMap: ["paragraphSpacing": "0.5"])
        XCTAssertEqual(prefs.paragraphSpacing, 0.5)
    }

    func testFromMapFontWeight() {
        let prefs = EPUBPreferences(fromMap: ["fontWeight": "700.0"])
        XCTAssertEqual(prefs.fontWeight, 700.0)
    }

    func testFromMapLigatures() {
        let prefs = EPUBPreferences(fromMap: ["ligatures": "true"])
        XCTAssertEqual(prefs.ligatures, true)
    }

    func testFromMapUnknownKeyIgnored() {
        let prefs = EPUBPreferences(fromMap: ["nonExistentKey": "value"])
        XCTAssertNil(prefs.fontSize)
    }

    func testFromMapEmptyMap() {
        let prefs = EPUBPreferences(fromMap: [:])
        XCTAssertNil(prefs.fontSize)
        XCTAssertNil(prefs.scroll)
    }
}

// MARK: - PDFPreferences Extension Tests

final class PDFPreferencesExtensionTests: XCTestCase {

    func testFromMapFitWidth() {
        let prefs = PDFPreferences(fromMap: ["fit": "width"])
        XCTAssertEqual(prefs.scroll, true)
    }

    func testFromMapFitContain() {
        let prefs = PDFPreferences(fromMap: ["fit": "contain"])
        XCTAssertEqual(prefs.scroll, false)
    }

    func testFromMapScrollModeVertical() {
        let prefs = PDFPreferences(fromMap: ["scrollMode": "vertical"])
        XCTAssertEqual(prefs.scrollAxis, .vertical)
    }

    func testFromMapScrollModeHorizontal() {
        let prefs = PDFPreferences(fromMap: ["scrollMode": "horizontal"])
        XCTAssertEqual(prefs.scrollAxis, .horizontal)
    }

    func testFromMapPageLayoutSingle() {
        let prefs = PDFPreferences(fromMap: ["pageLayout": "single"])
        XCTAssertEqual(prefs.spread, .never)
    }

    func testFromMapPageLayoutDouble() {
        let prefs = PDFPreferences(fromMap: ["pageLayout": "double"])
        XCTAssertEqual(prefs.spread, .always)
    }

    func testFromMapPageLayoutAutomatic() {
        let prefs = PDFPreferences(fromMap: ["pageLayout": "automatic"])
        XCTAssertEqual(prefs.spread, .auto)
    }

    func testFromMapOffsetFirstPage() {
        let prefs = PDFPreferences(fromMap: ["offsetFirstPage": true])
        XCTAssertEqual(prefs.offsetFirstPage, true)
    }

    func testFromMapPageSpacing() {
        let prefs = PDFPreferences(fromMap: ["pageSpacing": 16.0])
        XCTAssertEqual(prefs.pageSpacing, 16.0)
    }

    func testFromMapVisibleScrollbar() {
        let prefs = PDFPreferences(fromMap: ["visibleScrollbar": false])
        XCTAssertEqual(prefs.visibleScrollbar, false)
    }

    func testFromMapBackgroundColor() {
        let prefs = PDFPreferences(fromMap: ["backgroundColor": "#FFFFFF"])
        XCTAssertNotNil(prefs.backgroundColor)
    }

    func testFromMapUnknownKeyIgnored() {
        let prefs = PDFPreferences(fromMap: ["bogusKey": "value"])
        XCTAssertNil(prefs.scroll)
    }
}

// MARK: - TTSVoice.Quality Extension Tests

final class TTSVoiceQualityExtensionTests: XCTestCase {

    func testLowToFlutterString() {
        XCTAssertEqual(TTSVoice.Quality.low.toFlutterString, "low")
    }

    func testLowerToFlutterString() {
        XCTAssertEqual(TTSVoice.Quality.lower.toFlutterString, "low")
    }

    func testMediumToFlutterString() {
        XCTAssertEqual(TTSVoice.Quality.medium.toFlutterString, "normal")
    }

    func testHighToFlutterString() {
        XCTAssertEqual(TTSVoice.Quality.high.toFlutterString, "high")
    }

    func testHigherToFlutterString() {
        XCTAssertEqual(TTSVoice.Quality.higher.toFlutterString, "high")
    }
}
