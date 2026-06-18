import XCTest
import Combine
import ReadiumShared
import ReadiumNavigator
@testable import flureadium

// MARK: - Mock Listener

private final class MockTimebasedListener: TimebasedListener {
    var reachedLocatorCalls: [(locator: Locator, link: Link?)] = []
    var highlightCalls: [(locator: Locator?, wordLocator: Locator?)] = []
    var stateChanges: [ReadiumTimebasedState] = []
    var errors: [(error: Error, description: String?)] = []

    func timebasedNavigator(_ nav: FlutterTimebasedNavigator, didChangeState state: ReadiumTimebasedState) {
        stateChanges.append(state)
    }
    func timebasedNavigator(_ nav: FlutterTimebasedNavigator, encounteredError error: Error, withDescription desc: String?) {
        errors.append((error, desc))
    }
    func timebasedNavigator(_ nav: FlutterTimebasedNavigator, reachedLocator locator: Locator, readingOrderLink: Link?) {
        reachedLocatorCalls.append((locator, readingOrderLink))
    }
    func timebasedNavigator(_ nav: FlutterTimebasedNavigator, requestsHighlightAt locator: Locator?, withWordLocator wordLocator: Locator?) {
        highlightCalls.append((locator, wordLocator))
    }
}

/// Guards the chapter-transition deadlock fix: the two delegate callbacks that
/// used to re-read `_audioNavigator?.playbackInfo` (a re-entrant
/// `AVPlayer.currentTime()` inside `AudioNavigator.go(to:)`) must now serve
/// state from cached off-lock values. Every test runs with `_audioNavigator`
/// left nil — proof the callback bodies never reach the live navigator.
@MainActor
final class FlutterAudioNavigatorTests: XCTestCase {

    // MARK: - Helpers

    private func makePublication() -> Publication {
        Publication(manifest: Manifest(metadata: Metadata(title: "Audio")))
    }

    private func makeLocator(href: String = "track1.mp3") -> Locator {
        Locator(href: URL(string: href)!, mediaType: .mp3)
    }

    /// Builds the navigator WITHOUT `initNavigator()`, so `_audioNavigator`
    /// stays nil. The callbacks must still work from cached state.
    private func makeNavigator() -> (FlutterAudioNavigator, MockTimebasedListener) {
        let nav = FlutterAudioNavigator(
            publication: makePublication(),
            preferences: FlutterAudioPreferences(),
            initialLocator: nil
        )
        let mock = MockTimebasedListener()
        nav.listener = mock
        return (nav, mock)
    }

    // MARK: - Emission from cached state (the deadlock guard)

    func testLocationDidChangeEmitsFromCachedInfoWithoutNavigator() {
        let (nav, mock) = makeNavigator()
        nav._lastPlaybackInfo = MediaPlaybackInfo()
        nav.handleLocationChange(makeLocator())
        XCTAssertEqual(mock.stateChanges.count, 1,
            "locationDidChange must emit using cached info, not _audioNavigator.playbackInfo")
    }

    func testLoadedTimeRangesEmitsFromCachedStateWithoutNavigator() {
        let (nav, mock) = makeNavigator()
        nav._lastPlaybackInfo = MediaPlaybackInfo()
        nav.handleLocationChange(makeLocator())
        let before = mock.stateChanges.count
        nav.handleLoadedTimeRanges([0.0..<42.0])
        XCTAssertGreaterThan(mock.stateChanges.count, before,
            "loadedTimeRangesDidChange must emit using cached info + cached location")
    }

    // MARK: - Guard before any playback info is cached

    func testCallbacksDoNotEmitBeforeAnyPlaybackInfoCached() {
        let (nav, mock) = makeNavigator()
        nav.handleLocationChange(makeLocator())
        nav.handleLoadedTimeRanges([0.0..<10.0])
        XCTAssertEqual(mock.stateChanges.count, 0,
            "with no cached playback info, callbacks must guard and not emit timebased state")
    }

    // MARK: - Locator listener still fires

    func testLocationDidChangeStillReachesLocatorListener() {
        let (nav, mock) = makeNavigator()
        nav.handleLocationChange(makeLocator(href: "track2.mp3"))
        XCTAssertEqual(mock.reachedLocatorCalls.count, 1,
            "locationDidChange must still forward the locator to the listener")
    }
}
