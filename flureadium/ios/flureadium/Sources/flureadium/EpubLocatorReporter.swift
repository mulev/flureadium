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
@MainActor
final class EpubLocatorReporter {

  private let channel: ReadiumReaderChannel
  private let resolveFragments: @MainActor (String, Bool) async -> Locator?
  private let sendTextLocator: @MainActor (String?) -> Void
  private let isDisposed: @MainActor () -> Bool

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
    print(TAG, "report: locator=\(String(describing: locator))")

    Task.detached(priority: .high) { [weak self] in
      await self?.resolveAndPublish(json, isScrollMode: isScrollMode)
    }
  }

  func reportExternalLink(_ url: URL) {
    print(TAG, "reportExternalLink: \(url)")
    Task.detached(priority: .high) { [weak self] in
      await self?.publishExternalLink(url)
    }
  }

  private func publishExternalLink(_ url: URL) {
    channel.onExternalLinkActivated(url: url)
  }

  private func resolveAndPublish(_ json: String, isScrollMode: Bool) async {
    guard !isDisposed() else { return }
    guard let resolved = await resolveFragments(json, isScrollMode) else {
      print(TAG, "report: fragment resolution failed")
      return
    }
    guard !isDisposed() else { return }

    channel.onPageChanged(locator: resolved)
    sendTextLocator(resolved.jsonString)
  }
}
