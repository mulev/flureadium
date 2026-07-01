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

    /// Builds a publication with `count` resources in the `readingOrder`, so
    /// `resourceIndex` math in `shouldPlayNextResource` is meaningful.
    private func makePublication(readingOrderCount count: Int) -> Publication {
        let links = (0..<count).map { Link(href: "track\($0).mp3", mediaType: .mp3) }
        return Publication(manifest: Manifest(metadata: Metadata(title: "Audio"), readingOrder: links))
    }

    private func makeNavigator(readingOrderCount count: Int) -> (FlutterAudioNavigator, MockTimebasedListener) {
        let nav = FlutterAudioNavigator(
            publication: makePublication(readingOrderCount: count),
            preferences: FlutterAudioPreferences(),
            initialLocator: nil
        )
        let mock = MockTimebasedListener()
        nav.listener = mock
        return (nav, mock)
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

    // MARK: - End-of-book emits .ended

    func testShouldPlayNextResourceAtLastResourceEmitsEnded() {
        let (nav, mock) = makeNavigator(readingOrderCount: 3)
        let shouldContinue = nav.shouldPlayNext(info: MediaPlaybackInfo(resourceIndex: 2))
        XCTAssertFalse(shouldContinue,
            "at the last resource, playback must stop (return false)")
        XCTAssertEqual(mock.stateChanges.count, 1,
            "last resource must emit exactly one state change")
        XCTAssertEqual(mock.stateChanges.first?.state, .ended,
            "last resource must emit a .ended timebased state")
    }

    func testShouldPlayNextResourceBeforeLastReturnsTrueAndEmitsNothing() {
        let (nav, mock) = makeNavigator(readingOrderCount: 3)
        let shouldContinue = nav.shouldPlayNext(info: MediaPlaybackInfo(resourceIndex: 1))
        XCTAssertTrue(shouldContinue,
            "before the last resource, playback must continue (return true)")
        XCTAssertEqual(mock.stateChanges.count, 0,
            "a non-last resource must not emit any timebased state")
    }

    // MARK: - dispose() must not emit a phantom .ended

    func testDisposeDoesNotEmitEnded() {
        let (nav, mock) = makeNavigator(readingOrderCount: 3)
        nav.dispose()
        XCTAssertEqual(mock.stateChanges.count, 0,
            "dispose() is teardown, not end-of-book — it must not emit any timebased state")
        XCTAssertFalse(mock.stateChanges.contains { $0.state == .ended },
            "dispose() must not emit a phantom .ended; only shouldPlayNext at the last resource may emit .ended")
    }

    // MARK: - Locator listener still fires

    func testLocationDidChangeStillReachesLocatorListener() {
        let (nav, mock) = makeNavigator()
        nav.handleLocationChange(makeLocator(href: "track2.mp3"))
        XCTAssertEqual(mock.reachedLocatorCalls.count, 1,
            "locationDidChange must still forward the locator to the listener")
    }
}
