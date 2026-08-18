import Foundation
import AVFoundation
import Combine
import MediaPlayer
import ReadiumShared
import ReadiumNavigator

public class FlutterAudioNavigator: FlutterTimebasedNavigator, AudioNavigatorDelegate
{
  internal let TAG = "FlutterAudioNavigator"

  internal var _publication: Publication
  internal var _initialLocator: Locator?
  internal var _preferences: FlutterAudioPreferences
  internal var _lastTimebasedPlayerState: ReadiumTimebasedState?
  internal var _nowPlayingUpdater: NowPlayingInfoUpdater
  @MainActor internal var _audioNavigator: AudioNavigator?

  /// Last playback info delivered off-lock by Readium's `playbackDidChange`.
  /// Re-entrant delegate callbacks serve state from this cache instead of
  /// reading `_audioNavigator?.playbackInfo`, which re-enters AVPlayer's lock
  /// while `AudioNavigator.go(to:)` holds it and self-deadlocks.
  internal var _lastPlaybackInfo: MediaPlaybackInfo?
  /// Last locator delivered off-lock by `locationDidChange`, cached for the
  /// same reason — keeps `loadedTimeRangesDidChange` off the live navigator.
  internal var _lastLocation: Locator?

  internal var subscriptions: Set<AnyCancellable> = []

  /// NotificationCenter tokens for the best-effort AVFoundation playback-failure
  /// observers. Readium keeps its `AVPlayer` private and routes neither post-load
  /// decode/status failures nor stalls to `AudioNavigatorDelegate`, so these are
  /// the only signal we get for those. (Load-time resource failures are caught
  /// deterministically by the `AudioResourceLoadFailureReporter` wrapper instead —
  /// see `registerPlaybackFailureObservers`.) Held for the navigator's lifetime
  /// and removed in `dispose()`.
  internal var playbackFailureObservers: [NSObjectProtocol] = []

  @Published var cover: UIImage?
  @Published var playback: MediaPlaybackInfo = .init()

  public var publication: Publication {
    get {
      return self._publication
    }
  }
  public var initialLocator: Locator? {
    get {
      return self._initialLocator
    }
  }

  public var listener: (any TimebasedListener)?

  public init(publication: Publication, preferences: FlutterAudioPreferences, initialLocator: Locator?) {
    self._publication = publication
    self._preferences = preferences
    self._initialLocator = initialLocator
    self._nowPlayingUpdater = NowPlayingInfoUpdater(
      withPublication: publication,
      infoType: preferences.controlPanelInfoType
    )
  }

  public func initNavigator() async -> Void {
    _audioNavigator = AudioNavigator(
      publication: publication,
      initialLocation: initialLocator,
      config: AudioNavigator.Configuration(
        preferences: AudioPreferences(fromFlutterPrefs: _preferences)
      )
    )
    _audioNavigator?.delegate = self

    // TODO: Why is this public, if always called from itself?
    self.setupNavigatorListeners()
    self.registerPlaybackFailureObservers()

    Task {
      cover = try? await publication.cover().get()
    }
  }

  public func setupNavigatorListeners() {
    /// Subscribe to changes
    $playback
      .throttle(for: .seconds(self._preferences.updateIntervalSecs), scheduler: RunLoop.main, latest: true)
      .sink { [weak self, TAG] info in
        guard let self = self else {
          return
        }
        debugPrint(TAG, "$playback updated: state=\(info.state),index=\(info.resourceIndex),time=\(info.time),progress=\(info.progress)")

        if let location = _audioNavigator?.currentLocation {
          self.submitTimebasedPlayerStateToListener(info: info, location: location)
        }
      }
      .store(in: &subscriptions)
  }

  public func dispose() -> Void {
    self.removePlaybackFailureObservers()
    self._audioNavigator?.pause()
    self._audioNavigator?.delegate = nil
    self._audioNavigator = nil
    // Teardown is not end-of-book: emitting .ended here is a phantom natural-end
    // signal Android never produces. Only shouldPlayNext at the last resource
    // may emit .ended. See flureadium-amn.
    self.listener = nil
  }

  public func play(fromLocator: Locator?) async -> Void {
    if (fromLocator != nil) {
      let _ = await seek(toLocator: fromLocator!)
    }
    _audioNavigator?.play()
    _nowPlayingUpdater.setupNowPlayingInfo()
    _nowPlayingUpdater.setupCommandCenterControls(
      preferredIntervals: [_preferences.seekInterval],
      seekToEnabled: _preferences.allowExternalSeeking,
      timebasedNavigator: self
    )
  }

  public func pause() async -> Void {
    _audioNavigator?.pause()
  }

  public func resume() async -> Void {
    _audioNavigator?.play()
  }

  public func togglePlayPause() async -> Void {
    if (playback.state == .playing) {
      await pause()
    } else {
      await resume()
    }
  }

  public func seekForward() async -> Bool {
    await _audioNavigator?.seek(by: self._preferences.seekInterval)
    return true
  }

  public func seekBackward() async -> Bool {
    await _audioNavigator?.seek(by: -1 * self._preferences.seekInterval)
    return true
  }

  public func seek(toLocator: Locator) async -> Bool {
    let wasPlaying = _audioNavigator?.state == .playing || _audioNavigator?.state == .loading
    let navigated = await _audioNavigator?.go(to: toLocator) ?? false
    if (wasPlaying && navigated) {
      _audioNavigator?.play()
    }
    return navigated
  }

  public func seek(toOffset: Double) async -> Bool {
    let wasPlaying = _audioNavigator?.state == .playing || _audioNavigator?.state == .loading
    await _audioNavigator?.seek(to: toOffset)
    if (wasPlaying) {
      _audioNavigator?.play()
    }
    return true
  }
  
  public func seekRelative(byOffsetSeconds: Double) async -> Bool {
    await _audioNavigator?.seek(by: byOffsetSeconds)
    return true
  }

  // MARK: AudioNavigatorDelegate

  /// Called when the playback updates.
  public func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
    // Cache the off-lock info first so the re-entrant callbacks below can reuse
    // it without reading back into the live navigator.
    self._lastPlaybackInfo = info
    self._nowPlayingUpdater.updatePlaybackFromInfo(info, withSpeedSetting: _audioNavigator?.settings.speed)
    self._nowPlayingUpdater.updateCommandCenterControls()
    self.playback = info
  }

  public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    handleLocationChange(locator)
  }

  /// Param-free seam reused by tests: serves state from cached values only,
  /// never touching `_audioNavigator`.
  internal func handleLocationChange(_ locator: Locator) {
    self._lastLocation = locator
    // Submit new locator to the listener
    self.submitAudioLocatorToListener(locator)

    if let info = _lastPlaybackInfo {
      self.submitTimebasedPlayerStateToListener(info: info, location: locator)
    }
  }

  /// Called when the ranges of buffered media data change.
  /// Warning: They may be discontinuous.
  public func navigator(_ navigator: AudioNavigator, loadedTimeRangesDidChange ranges: [Range<Double>]) {
    handleLoadedTimeRanges(ranges)
  }

  internal func handleLoadedTimeRanges(_ ranges: [Range<Double>]) {
    // Simplified buffer range to TimeInterval, by just taking highest upper bound.
    // May be too optimistic if ranges are discontinuous.
    let highestUpperBound: TimeInterval = ranges.map(\.upperBound).max() ?? 0

    if let info = _lastPlaybackInfo,
       let location = _lastLocation {
      self.submitTimebasedPlayerStateToListener(info: info, location: location, bufferedInterval: highestUpperBound)
    }
  }

  /// Called when the navigator finished playing the current resource.
  /// Returns whether the next resource should be played. Default is true.
  public func navigator(_ navigator: AudioNavigator, shouldPlayNextResource info: MediaPlaybackInfo) -> Bool {
    return shouldPlayNext(info: info)
  }

  /// Param-free seam reused by tests: decides whether to continue to the next
  /// resource without touching the live navigator. Mirrors `handleLocationChange`.
  internal func shouldPlayNext(info: MediaPlaybackInfo) -> Bool {
    let lastIndex = publication.readingOrder.count - 1
    if info.resourceIndex >= lastIndex {
      self.listener?.timebasedNavigator(self, didChangeState: .init(state: .ended))
      return false
    }
    return true
  }

  public func navigator(_ navigator: any ReadiumNavigator.Navigator, presentError error: ReadiumNavigator.NavigatorError) {
    debugPrint(TAG, "presentError: \(error)")
    // TODO: Only relevant when supporting LCP, error can only be copyForbidden.
  }

  public func navigator(_ navigator: any ReadiumNavigator.Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    self.listener?.timebasedNavigator(self, encounteredError: error, withDescription: "DidFailToLoadResourceAt: \(href)")
  }

  // MARK: AVFoundation playback-failure observation (best-effort)

  /// Converts an AVFoundation playback failure into a listener error. Kept as an
  /// `internal` seam so it can be unit-tested without a live `AVPlayer`, which
  /// Readium keeps private. A missing `error` is synthesized from `description`
  /// so the listener always receives a non-nil error.
  internal func handlePlaybackFailure(_ error: Error?, description: String) {
    let resolved = error ?? NSError(
      domain: TAG,
      code: -1,
      userInfo: [NSLocalizedDescriptionKey: description]
    )
    self.listener?.timebasedNavigator(self, encounteredError: resolved, withDescription: description)
  }

  /// Registers best-effort AVFoundation failure observers (`object: nil`, since
  /// the player item is private). These catch failed-to-play-to-end and new
  /// error-log entries — mid-stream and post-load failures Readium's audio stack
  /// swallows. Load-time resource failures no longer rely on this net: the
  /// `AudioResourceLoadFailureReporter` container wrapper (see `Readium.swift`)
  /// catches them deterministically during opening. The accepted limitation now
  /// applies only to post-load AVPlayer decode/status failures and healthy-URL
  /// stalls, which remain KVO-only signals with no guaranteed notification.
  internal func registerPlaybackFailureObservers() {
    let center = NotificationCenter.default
    let failedToken = center.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime,
      object: nil,
      queue: .main
    ) { [weak self] note in
      let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
      Task { @MainActor in
        self?.handlePlaybackFailure(error, description: "AVPlayerItemFailedToPlayToEndTime")
      }
    }
    let errorLogToken = center.addObserver(
      forName: .AVPlayerItemNewErrorLogEntry,
      object: nil,
      queue: .main
    ) { [weak self] note in
      let event = (note.object as? AVPlayerItem)?.errorLog()?.events.last
      let error = event.map { event -> NSError in
        NSError(
          domain: event.errorDomain,
          code: event.errorStatusCode,
          userInfo: [NSLocalizedDescriptionKey: event.errorComment ?? "AVPlayerItemNewErrorLogEntry"]
        )
      }
      Task { @MainActor in
        self?.handlePlaybackFailure(error, description: "AVPlayerItemNewErrorLogEntry")
      }
    }
    playbackFailureObservers = [failedToken, errorLogToken]
  }

  /// Removes all playback-failure observers. Called from `dispose()` so the
  /// observers never outlive the navigator (leak-free).
  internal func removePlaybackFailureObservers() {
    let center = NotificationCenter.default
    playbackFailureObservers.forEach { center.removeObserver($0) }
    playbackFailureObservers = []
  }

  // MARK: AudioNavigator specific API

  @MainActor
  func setAudioPreferences(_ preferences: FlutterAudioPreferences) {
    self._preferences = preferences
    /// Update the Audio Navigator.
    self._audioNavigator?.submitPreferences(AudioPreferences(fromFlutterPrefs: preferences))
    /// Update the CommandCenter controls.
    self._nowPlayingUpdater.setupCommandCenterControls(
      preferredIntervals: [_preferences.seekInterval],
      seekToEnabled: _preferences.allowExternalSeeking,
      timebasedNavigator: self
    )
  }

  var canGoBackward: Bool {
    self._audioNavigator?.canGoBackward ?? false
  }

  var canGoForward: Bool {
    self._audioNavigator?.canGoForward ?? false
  }

  @MainActor
  public func skipForward() async -> Bool {
    if _audioNavigator?.canGoForward != true {
      return false
    }
    return await _audioNavigator?.goForward() ?? false
  }

  @MainActor
  public func skipBackward() async -> Bool {
    if _audioNavigator?.canGoBackward != true {
      return false
    }
    return await _audioNavigator?.goBackward() ?? false
  }

  // MARK: Internal AudioNavigator API

  internal func submitAudioLocatorToListener(_ locator: Locator) {
    let readingOrderLink = self.publication.readingOrder.firstWithHREF(locator.href)
    self.listener?.timebasedNavigator(self, reachedLocator: locator, readingOrderLink: readingOrderLink)
  }

  internal func submitTimebasedPlayerStateToListener(info: MediaPlaybackInfo, location: Locator, bufferedInterval: TimeInterval? = nil) {
    // Create TimebasedState and send it over the timebased-state stream.
    let state = ReadiumTimebasedState(
      state: info.state.asTimebasedState,
      currentOffset: info.time,
      currentBuffered: bufferedInterval,
      currentDuration: info.duration ?? nil,
      currentLocator: location
    )

    // If state has changed, submit it to listener.
    if (state != self._lastTimebasedPlayerState) {
      self._lastTimebasedPlayerState = state
      self.listener?.timebasedNavigator(self, didChangeState: state)
    } else {
      debugPrint(TAG, "Skipped state submission - duplicate")
    }
  }
}
