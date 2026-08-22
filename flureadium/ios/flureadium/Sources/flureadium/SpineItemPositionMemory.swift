import ReadiumShared

/// Per-spine-item scroll positions, so a swipe back into the previous chapter
/// lands where the reader left it rather than at the chapter's start.
///
/// Only scroll mode remembers anything: paginated navigation has no
/// within-chapter offset to restore.
struct SpineItemPositionMemory {
  private var history: [String: Locator] = [:]
  private var lastLocator: Locator?
  private var currentHref: String?

  /// Records `locator` as the newest position.
  ///
  /// - Returns: the stored position to navigate to, when this call is a
  ///   backward spine-item change in scroll mode and that item has one;
  ///   otherwise `nil`.
  mutating func record(
    _ locator: Locator, in readingOrder: [Link], isScrollMode: Bool
  ) -> Locator? {
    let newHref = strippedHref(locator.href.string)
    var restoration: Locator?

    if isScrollMode, let oldHref = currentHref, newHref != oldHref {
      // Store the last known position for the spine item we are leaving.
      if let outgoing = lastLocator {
        history[oldHref] = outgoing
      }
      if isBackwardNavigation(from: oldHref, to: newHref, in: readingOrder) {
        restoration = history[newHref]
      }
    }

    currentHref = newHref
    lastLocator = locator
    return restoration
  }

  /// Drops `href`'s remembered position, so explicit navigation to it wins.
  mutating func forget(href: String) {
    history.removeValue(forKey: strippedHref(href))
  }
}

func strippedHref(_ href: String) -> String {
  href.components(separatedBy: "#").first?
      .components(separatedBy: "?").first ?? href
}

func isBackwardNavigation(from oldHref: String, to newHref: String, in readingOrder: [Link]) -> Bool {
  let cleanOld = strippedHref(oldHref)
  let cleanNew = strippedHref(newHref)
  guard let oldIdx = readingOrder.firstIndex(where: { strippedHref($0.href) == cleanOld }),
        let newIdx = readingOrder.firstIndex(where: { strippedHref($0.href) == cleanNew }) else {
    return false
  }
  return newIdx < oldIdx
}
