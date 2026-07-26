import Flutter
import Foundation

/// Supplies the CarPlay renderer with browse nodes and forwards selections.
///
/// This protocol is the mechanism-neutral seam between the renderer and however
/// the host answers car requests. The shipping implementation
/// (`CarPlayContentBridge`) routes over the `dev.mulev.flureadium/car` method
/// channel to the Dart `CarContentProvider`. A host that later prefers a
/// different mechanism — a native read-through cache for instant cold browse, or
/// a single shared app engine instead of a dedicated car engine — conforms a new
/// type here without touching the renderer.
public protocol CarPlayContentBridging {
  /// The root tabs (Continue · Library · Search).
  func rootTabs(_ completion: @escaping ([CarTab]) -> Void)

  /// The rows nested under [nodeId] (a tab id or a container node id).
  func children(of nodeId: String, _ completion: @escaping ([CarBrowseNode]) -> Void)

  /// The host's localized status strings, or nil when no provider is registered.
  func strings(_ completion: @escaping (CarContentStrings?) -> Void)

  /// Forwards a playable-row selection to the host (→ provider `play`).
  func select(nodeId: String)
}

/// The `CarPlayContentBridging` backed by the `dev.mulev.flureadium/car` method
/// channel. Bind it to whichever binary messenger the host runs its Dart car
/// entrypoint on (a dedicated headless car engine, or a shared app engine).
///
/// On a cold connect the car engine's Dart entrypoint is still starting when the
/// scene first asks for content, so the channel handler may not be installed
/// yet. A registered provider always answers browse calls with an array (empty
/// when it has nothing), so any *non-array* reply means "handler not ready" — the
/// bridge briefly retries those before giving up, rather than mistaking the
/// startup race for an empty library. A genuine empty result is an array and
/// returns immediately, with no retry latency.
public final class CarPlayContentBridge: CarPlayContentBridging {
  public static let channelName = "dev.mulev.flureadium/car"

  private static let readyRetryLimit = 20
  private static let readyRetryDelay: TimeInterval = 0.15

  private let channel: FlutterMethodChannel

  public init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: binaryMessenger)
  }

  public func rootTabs(_ completion: @escaping ([CarTab]) -> Void) {
    invokeList("rootTabs", arguments: nil) { list in
      completion(list.compactMap { ($0 as? [String: Any]).flatMap(CarTab.init(map:)) })
    }
  }

  public func children(of nodeId: String, _ completion: @escaping ([CarBrowseNode]) -> Void) {
    invokeList("children", arguments: ["nodeId": nodeId]) { list in
      completion(list.compactMap { ($0 as? [String: Any]).flatMap(CarBrowseNode.init(map:)) })
    }
  }

  public func strings(_ completion: @escaping (CarContentStrings?) -> Void) {
    channel.invokeMethod("strings", arguments: nil) { result in
      completion((result as? [String: Any]).flatMap(CarContentStrings.init(map:)))
    }
  }

  public func select(nodeId: String) {
    channel.invokeMethod("play", arguments: ["nodeId": nodeId])
  }

  /// Invokes a list-returning method, retrying while the reply is not yet an
  /// array (the car engine's Dart handler is still starting). Delivers the array
  /// as soon as one arrives, or an empty array once the retry budget is spent.
  private func invokeList(
    _ method: String,
    arguments: Any?,
    attempt: Int = 0,
    completion: @escaping ([Any]) -> Void
  ) {
    channel.invokeMethod(method, arguments: arguments) { [weak self] result in
      if let list = result as? [Any] {
        completion(list)
      } else if let self = self, attempt < Self.readyRetryLimit {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readyRetryDelay) {
          self.invokeList(
            method, arguments: arguments, attempt: attempt + 1, completion: completion)
        }
      } else {
        completion([])
      }
    }
  }
}
