import Flutter
import ReadiumShared

private let TAG = "EpubLocatorReporter"

/// Publishes a page change to Dart: fragments resolved over the WebView, then
/// the locator on the view's method channel and on the plugin's text-locator
/// stream.
///
/// `isDisposed` is checked on both sides of the WebView hop. A page change
/// already in flight when the reader tore down must not reach a dead channel —
/// see `docs/troubleshooting.md`, "Reader crash while turning pages or closing
/// the reader". Passing the flag as a closure keeps the view its single owner,
/// the same arrangement `observeTaps(on:reportingTo:isDisposed:)` uses.
///
/// Fragment resolution fails while a spread is being swapped, which is while a
/// page turn is in flight. Such a page change publishes the locator Readium
/// reported rather than nothing, matching Android. Disposal is the separate
/// case and still drops.
@MainActor
final class EpubLocatorReporter {

  private let channel: ReadiumReaderChannel
  private let resolveFragments: @MainActor (String, Bool) async -> Locator?
  private let sendTextLocator: @MainActor (String?) -> Void
  private let isDisposed: @MainActor () -> Bool

  /// Increments on every `report`. A resolution publishes only if its stamp is
  /// still the latest one, so a page change the reader has already left cannot
  /// overwrite the one it moved to.
  private var latestReportSequence: UInt64 = 0

  init(
    channel: ReadiumReaderChannel,
    resolveFragments: @MainActor @escaping (String, Bool) async -> Locator?,
    sendTextLocator: @MainActor @escaping (String?) -> Void,
    isDisposed: @MainActor @escaping () -> Bool
  ) {
    self.channel = channel
    self.resolveFragments = resolveFragments
    self.sendTextLocator = sendTextLocator
    self.isDisposed = isDisposed
  }

  func report(_ locator: Locator, isScrollMode: Bool) {
    let json = locator.jsonString ?? "null"
    readerLog(TAG, "report: locator=\(String(describing: locator))")

    latestReportSequence &+= 1
    let sequence = latestReportSequence

    Task.detached(priority: .high) { [weak self] in
      await self?.resolveAndPublish(
        json, reported: locator, isScrollMode: isScrollMode, sequence: sequence)
    }
  }

  func reportExternalLink(_ url: URL) {
    readerLog(TAG, "reportExternalLink: \(url)")
    Task.detached(priority: .high) { [weak self] in
      await self?.publishExternalLink(url)
    }
  }

  private func publishExternalLink(_ url: URL) {
    channel.onExternalLinkActivated(url: url)
  }

  private func resolveAndPublish(
    _ json: String, reported: Locator, isScrollMode: Bool, sequence: UInt64
  ) async {
    guard !isDisposed() else { return }
    let resolved = await resolveFragments(json, isScrollMode)
    guard !isDisposed() else { return }

    guard sequence == latestReportSequence else {
      readerLog(TAG, "resolveAndPublish: superseded by a newer report, dropping")
      return
    }

    let published: Locator
    if let resolved {
      published = resolved
    } else {
      readerLog(
        TAG, "resolveAndPublish: fragment resolution failed, publishing the reported locator")
      published = reported
    }

    channel.onPageChanged(locator: published)
    sendTextLocator(published.jsonString)
  }
}
