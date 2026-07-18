import Foundation
import ReadiumShared

/// Wraps a Readium `Resource` to surface load failures to a callback while
/// forwarding every read unchanged.
///
/// `PublicationMediaLoader` serves audiobook tracks through the publication's
/// container. When a length probe or byte read fails, the loader hands the error
/// straight to `AVAssetResourceLoadingRequest.finishLoading(with:)` plus a log
/// line, so the failure dies inside AVFoundation and never reaches the
/// `AudioNavigatorDelegate`. This decorator observes those failures at the read
/// boundary without altering the content or the estimated length — unlike
/// `TransformingResource`, which nils the estimated length and buffers the whole
/// resource (breaking streaming and byte-range access).
final class LoadFailureObservingResource: Resource {
  private let resource: Resource
  private let onFailure: (ReadError) -> Void

  init(wrapping resource: Resource, onFailure: @escaping (ReadError) -> Void) {
    self.resource = resource
    self.onFailure = onFailure
  }

  var sourceURL: AbsoluteURL? { resource.sourceURL }

  func properties() async -> ReadResult<ResourceProperties> {
    await resource.properties()
  }

  func estimatedLength() async -> ReadResult<UInt64?> {
    let result = await resource.estimatedLength()
    if case let .failure(error) = result { onFailure(error) }
    return result
  }

  func stream(range: Range<UInt64>?, consume: @escaping (Data) -> Void) async -> ReadResult<Void> {
    let result = await resource.stream(range: range, consume: consume)
    if case let .failure(error) = result { onFailure(error) }
    return result
  }
}
