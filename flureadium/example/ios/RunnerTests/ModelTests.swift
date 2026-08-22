import XCTest
import AVFAudio
@testable import flureadium

// MARK: - ControlPanelInfoType Tests

final class ControlPanelInfoTypeTests: XCTestCase {

    func testInitFromStandard() {
        XCTAssertEqual(ControlPanelInfoType(from: "standard"), .standard)
    }

    func testInitFromStandardWCh() {
        XCTAssertEqual(ControlPanelInfoType(from: "standardWCh"), .standardWCh)
    }

    func testInitFromChapterTitleAuthor() {
        XCTAssertEqual(ControlPanelInfoType(from: "chapterTitleAuthor"), .chapterTitleAuthor)
    }

    func testInitFromChapterTitle() {
        XCTAssertEqual(ControlPanelInfoType(from: "chapterTitle"), .chapterTitle)
    }

    func testInitFromTitleChapter() {
        XCTAssertEqual(ControlPanelInfoType(from: "titleChapter"), .titleChapter)
    }

    func testInitFromNil() {
        XCTAssertEqual(ControlPanelInfoType(from: nil), .standard)
    }

    func testInitFromUnknownString() {
        XCTAssertEqual(ControlPanelInfoType(from: "bogus"), .standard)
    }
}

// MARK: - TTSPreferences Tests

final class TTSPreferencesTests: XCTestCase {

    func testInitDefaults() {
        let prefs = TTSPreferences()
        XCTAssertNil(prefs.rate)
        XCTAssertNil(prefs.pitch)
        XCTAssertNil(prefs.overrideLanguage)
        XCTAssertNil(prefs.voiceIdentifier)
    }

    func testInitFromMapDefaults() throws {
        let prefs = try TTSPreferences(fromMap: [:])
        // Default speed 1.0 * AVSpeechUtteranceDefaultSpeechRate
        XCTAssertEqual(prefs.rate!, AVSpeechUtteranceDefaultSpeechRate, accuracy: 0.001)
        XCTAssertEqual(prefs.pitch!, Float(1.0), accuracy: 0.001)
        XCTAssertNil(prefs.overrideLanguage)
        XCTAssertNil(prefs.voiceIdentifier)
    }

    func testInitFromMapWithValues() throws {
        let map: [String: Any] = [
            "speed": 1.5,
            "pitch": 1.2,
            "voiceIdentifier": "com.apple.voice.compact.en-US.Samantha",
            "languageOverride": "en-US",
        ]
        let prefs = try TTSPreferences(fromMap: map)
        XCTAssertNotNil(prefs.rate)
        XCTAssertEqual(prefs.pitch!, Float(1.2), accuracy: 0.001)
        XCTAssertEqual(prefs.voiceIdentifier, "com.apple.voice.compact.en-US.Samantha")
        XCTAssertNotNil(prefs.overrideLanguage)
    }

    func testRateNormalization() throws {
        // speed=1.0 should produce rate = 1.0 * AVSpeechUtteranceDefaultSpeechRate
        let prefs = try TTSPreferences(fromMap: ["speed": 1.0])
        XCTAssertEqual(prefs.rate!, AVSpeechUtteranceDefaultSpeechRate, accuracy: 0.001)
    }

    func testRateClampedToMin() throws {
        // speed=0.0 → rate = 0.0 * default = 0.0, clamped to AVSpeechUtteranceMinimumSpeechRate
        let prefs = try TTSPreferences(fromMap: ["speed": 0.0])
        XCTAssertEqual(prefs.rate!, AVSpeechUtteranceMinimumSpeechRate, accuracy: 0.001)
    }

    func testRateClampedToMax() throws {
        // speed=100.0 → rate = 100.0 * default, clamped to AVSpeechUtteranceMaximumSpeechRate
        let prefs = try TTSPreferences(fromMap: ["speed": 100.0])
        XCTAssertEqual(prefs.rate!, AVSpeechUtteranceMaximumSpeechRate, accuracy: 0.001)
    }

    func testPitchClampedToMin() throws {
        let prefs = try TTSPreferences(fromMap: ["pitch": 0.1])
        XCTAssertEqual(prefs.pitch!, Float(0.5), accuracy: 0.001)
    }

    func testPitchClampedToMax() throws {
        let prefs = try TTSPreferences(fromMap: ["pitch": 5.0])
        XCTAssertEqual(prefs.pitch!, Float(2.0), accuracy: 0.001)
    }

    func testControlPanelInfoType() throws {
        let prefs = try TTSPreferences(fromMap: ["controlPanelInfoType": "chapterTitle"])
        XCTAssertEqual(prefs.controlPanelInfoType, .chapterTitle)
    }
}

// MARK: - FlutterAudioPreferences Tests

final class FlutterAudioPreferencesTests: XCTestCase {

    func testInitDefaults() {
        let prefs = FlutterAudioPreferences()
        XCTAssertEqual(prefs.volume, 1.0)
        XCTAssertEqual(prefs.speed, 1.0)
        XCTAssertEqual(prefs.pitch, 1.0)
        XCTAssertEqual(prefs.seekInterval, 30)
        XCTAssertEqual(prefs.allowExternalSeeking, true)
    }

    func testInitFromMapDefaults() throws {
        let prefs = try FlutterAudioPreferences(fromMap: [:])
        XCTAssertEqual(prefs.volume, 1.0)
        XCTAssertEqual(prefs.speed, 1.0)
        XCTAssertEqual(prefs.pitch, 1.0)
        XCTAssertEqual(prefs.seekInterval, 30)
        XCTAssertEqual(prefs.allowExternalSeeking, true)
    }

    func testInitFromMapWithValues() throws {
        let map: [String: Any] = [
            "volume": 0.8,
            "speed": 1.5,
            "pitch": 0.9,
            "seekInterval": 15.0,
            "allowExternalSeeking": false,
            "controlPanelInfoType": "chapterTitleAuthor",
            "updateIntervalSecs": 0.5,
        ]
        let prefs = try FlutterAudioPreferences(fromMap: map)
        XCTAssertEqual(prefs.volume, 0.8)
        XCTAssertEqual(prefs.speed, 1.5)
        XCTAssertEqual(prefs.pitch, 0.9, accuracy: 0.001)
        XCTAssertEqual(prefs.seekInterval, 15.0)
        XCTAssertEqual(prefs.allowExternalSeeking, false)
        XCTAssertEqual(prefs.controlPanelInfoType, .chapterTitleAuthor)
        XCTAssertEqual(prefs.updateIntervalSecs, 0.5)
    }

    func testRateClampedToMin() throws {
        let prefs = try FlutterAudioPreferences(fromMap: ["speed": 0.01])
        XCTAssertEqual(prefs.speed, 0.1, accuracy: 0.001)
    }

    func testRateClampedToMax() throws {
        let prefs = try FlutterAudioPreferences(fromMap: ["speed": 10.0])
        XCTAssertEqual(prefs.speed, 5.0, accuracy: 0.001)
    }

    func testPitchClampedToMin() throws {
        let prefs = try FlutterAudioPreferences(fromMap: ["pitch": 0.1])
        XCTAssertEqual(prefs.pitch, 0.5, accuracy: 0.001)
    }

    func testPitchClampedToMax() throws {
        let prefs = try FlutterAudioPreferences(fromMap: ["pitch": 5.0])
        XCTAssertEqual(prefs.pitch, 2.0, accuracy: 0.001)
    }
}

// MARK: - FlutterPdfPreferences Tests

final class FlutterPdfPreferencesTests: XCTestCase {

    // FlutterPdfFit enum

    func testPdfFitFromStringWidth() {
        XCTAssertEqual(FlutterPdfFit.fromString("width"), .width)
    }

    func testPdfFitFromStringContain() {
        XCTAssertEqual(FlutterPdfFit.fromString("contain"), .contain)
    }

    func testPdfFitFromStringCaseInsensitive() {
        XCTAssertEqual(FlutterPdfFit.fromString("Width"), .width)
        XCTAssertEqual(FlutterPdfFit.fromString("CONTAIN"), .contain)
    }

    func testPdfFitFromStringNil() {
        XCTAssertNil(FlutterPdfFit.fromString(nil))
    }

    func testPdfFitFromStringInvalid() {
        XCTAssertNil(FlutterPdfFit.fromString("bogus"))
    }

    func testPdfFitToReadiumScroll() {
        XCTAssertTrue(FlutterPdfFit.width.toReadiumScroll())
        XCTAssertFalse(FlutterPdfFit.contain.toReadiumScroll())
    }

    // FlutterPdfScrollMode enum

    func testPdfScrollModeFromStringHorizontal() {
        XCTAssertEqual(FlutterPdfScrollMode.fromString("horizontal"), .horizontal)
    }

    func testPdfScrollModeFromStringVertical() {
        XCTAssertEqual(FlutterPdfScrollMode.fromString("vertical"), .vertical)
    }

    func testPdfScrollModeFromStringNil() {
        XCTAssertNil(FlutterPdfScrollMode.fromString(nil))
    }

    func testPdfScrollModeFromStringInvalid() {
        XCTAssertNil(FlutterPdfScrollMode.fromString("diagonal"))
    }

    // FlutterPdfPageLayout enum

    func testPdfPageLayoutFromStringSingle() {
        XCTAssertEqual(FlutterPdfPageLayout.fromString("single"), .single)
    }

    func testPdfPageLayoutFromStringDouble() {
        XCTAssertEqual(FlutterPdfPageLayout.fromString("double"), .double)
    }

    func testPdfPageLayoutFromStringAutomatic() {
        XCTAssertEqual(FlutterPdfPageLayout.fromString("automatic"), .automatic)
    }

    func testPdfPageLayoutFromStringNil() {
        XCTAssertNil(FlutterPdfPageLayout.fromString(nil))
    }

    // FlutterPdfPreferences model

    func testPdfPreferencesFromMapFull() {
        let map: [String: Any] = [
            "fit": "width",
            "scrollMode": "vertical",
            "pageLayout": "double",
            "offsetFirstPage": true,
        ]
        let prefs = FlutterPdfPreferences(fromMap: map)
        XCTAssertEqual(prefs.fit, .width)
        XCTAssertEqual(prefs.scrollMode, .vertical)
        XCTAssertEqual(prefs.pageLayout, .double)
        XCTAssertEqual(prefs.offsetFirstPage, true)
    }

    func testPdfPreferencesFromNilMap() {
        let prefs = FlutterPdfPreferences(fromMap: nil)
        XCTAssertNil(prefs.fit)
        XCTAssertNil(prefs.scrollMode)
        XCTAssertNil(prefs.pageLayout)
        XCTAssertNil(prefs.offsetFirstPage)
    }

    func testPdfPreferencesFromEmptyMap() {
        let prefs = FlutterPdfPreferences(fromMap: [:])
        XCTAssertNil(prefs.fit)
    }

    func testPdfPreferencesToReadiumPreferences() {
        let prefs = FlutterPdfPreferences(
            fit: .width,
            scrollMode: .vertical,
            pageLayout: .single,
            offsetFirstPage: true
        )
        let readium = prefs.toReadiumPreferences()
        XCTAssertEqual(readium.scroll, true)     // width → scroll
        XCTAssertEqual(readium.offsetFirstPage, true)
    }

    func testPdfPreferencesToMap() {
        let prefs = FlutterPdfPreferences(
            fit: .contain,
            scrollMode: .horizontal,
            pageLayout: .automatic,
            offsetFirstPage: false
        )
        let map = prefs.toMap()
        XCTAssertEqual(map["fit"] as? String, "contain")
        XCTAssertEqual(map["scrollMode"] as? String, "horizontal")
        XCTAssertEqual(map["pageLayout"] as? String, "automatic")
        XCTAssertEqual(map["offsetFirstPage"] as? Bool, false)
    }

    func testPdfPreferencesToMapOmitsNils() {
        let prefs = FlutterPdfPreferences()
        let map = prefs.toMap()
        XCTAssertTrue(map.isEmpty)
    }

    func testPdfPreferencesFromMapWithInvalidValues() {
        let map: [String: Any] = [
            "fit": "invalid",
            "scrollMode": 123,
            "pageLayout": true,
            "offsetFirstPage": "notabool",
        ]
        let prefs = FlutterPdfPreferences(fromMap: map)
        // Invalid enum strings and wrong-typed bools decode to nil
        XCTAssertNil(prefs.fit)
        XCTAssertNil(prefs.scrollMode)
        XCTAssertNil(prefs.pageLayout)
        XCTAssertNil(prefs.offsetFirstPage)
    }
}
