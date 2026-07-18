import Foundation
import ReadiumShared

/// Reports each audiobook track's first load failure once per publication and
/// builds the `onCreatePublication` transform that wires it in.
///
/// Failures route onto the plugin-owned "error" channel through the existing
/// `FlureadiumPlugin.shared` seam — the same one the reader views use — so no
/// `FlureadiumPlugin` change is required.
final class AudioResourceLoadFailureReporter {
  private var reported: Set<String> = []
  private let lock = NSLock()
  private let send: (_ message: String, _ data: String) -> Void

  /// The default `send` marshals onto the main queue and forwards to the
  /// plugin's single "error" channel. Injectable so the de-dup logic can be
  /// unit-tested without the plugin.
  init(send: ((_ message: String, _ data: String) -> Void)? = nil) {
    self.send = send ?? { message, data in
      DispatchQueue.main.async {
        FlureadiumPlugin.shared?.sendError(message: message, code: "TimebasedError", data: data)
      }
    }
  }

  /// Transform applied to every opened publication. It no-ops unless the
  /// manifest is an audiobook (every reading-order entry is audio); then it
  /// wraps only the audio track resources so their load failures are observed.
  /// Non-track container entries (cover, manifest) are left untouched. The
  /// de-dup set is reset for each publication build.
  func makeTransform() -> Publication.Builder.Transform {
    return { [weak self] manifest, container, _ in
      guard let self else { return }
      self.reset()
      let readingOrder = manifest.readingOrder
      guard !readingOrder.isEmpty, readingOrder.allSatisfy({ $0.mediaType?.isAudio == true }) else {
        return
      }
      let audioHrefs = Set(readingOrder.map { $0.url().normalized.string })
      container = container.map { href, resource in
        guard audioHrefs.contains(href.normalized.string) else { return resource }
        return LoadFailureObservingResource(wrapping: resource) { error in
          self.report(href: href, error: error)
        }
      }
    }
  }

  /// Sends a track's first *genuine* load failure onto the error channel.
  /// AVFoundation issues many range requests per track, so repeats for the same
  /// href after the first are dropped until the next `reset()`. Cancelled HTTP
  /// reads are excluded entirely: AVFoundation routinely cancels in-flight range
  /// requests while re-planning buffering or seeking, so they are benign churn,
  /// not load failures, and must not surface as a `TimebasedError`.
  func report(href: AnyURL, error: ReadError) {
    // Filter benign cancellations BEFORE the de-dup insert — otherwise a genuine
    // failure arriving later on the same track would be suppressed by the slot a
    // cancelled read consumed.
    if case .access(.http(.cancelled)) = error { return }
    lock.lock()
    let isFirstFailure = reported.insert(href.normalized.string).inserted
    lock.unlock()
    guard isFirstFailure else { return }
    send(error.localizedDescription, "\(error)")
  }

  /// Clears the per-publication de-dup set. Called at the start of every
  /// publication build via `makeTransform`.
  func reset() {
    lock.lock()
    reported.removeAll()
    lock.unlock()
  }
}
