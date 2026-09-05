import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

import '../../reader_channel.dart';
import '../utils/navigation_helper.dart';
import '../utils/toc_matcher.dart';

/// Mixin that moves the reader to the adjacent table-of-contents entry.
///
/// Owns the last-navigated TOC index. That index is the highest-priority hint
/// for where the reader sits, because the JS-reported `toc=` heading can differ
/// from the entry navigation actually targeted.
mixin TocSkipNavigationMixin {
  int? _lastNavigatedTocIndex;
  int _stateGeneration = 0;

  /// Drops the remembered TOC index.
  ///
  /// Call when the hosted publication changes — otherwise the next skip indexes
  /// the new publication's TOC with the previous publication's position. A skip
  /// already waiting on the native navigation will not write its index back.
  void resetSkipNavigationState() {
    _lastNavigatedTocIndex = null;
    _stateGeneration++;
  }

  /// Navigates to the table-of-contents entry after [currentLocator].
  ///
  /// [whenReady] is the host view's first-locator future. It is awaited only
  /// when [currentLocator] is null — the window between a reader mounting and
  /// its first `onPageChanged`, in which a host can already hold a position
  /// from the `text-locator` channel while this cache is still empty.
  Future<void> skipToNextChapter({
    required Publication publication,
    required Locator? currentLocator,
    required ReadiumReaderChannel? channel,
    Future<Locator?>? whenReady,
  }) => _skip(
    publication: publication,
    currentLocator: currentLocator,
    channel: channel,
    whenReady: whenReady,
    forward: true,
  );

  /// Navigates to the table-of-contents entry before [currentLocator].
  ///
  /// [whenReady] is awaited on a cold cache, exactly as in [skipToNextChapter].
  Future<void> skipToPreviousChapter({
    required Publication publication,
    required Locator? currentLocator,
    required ReadiumReaderChannel? channel,
    Future<Locator?>? whenReady,
  }) => _skip(
    publication: publication,
    currentLocator: currentLocator,
    channel: channel,
    whenReady: whenReady,
    forward: false,
  );

  Future<void> _skip({
    required Publication publication,
    required Locator? currentLocator,
    required ReadiumReaderChannel? channel,
    required bool forward,
    Future<Locator?>? whenReady,
  }) async {
    final label = forward ? 'skipToNext' : 'skipToPrevious';
    final toc = navigableToc(publication);
    if (toc.isEmpty) {
      R2Log.d('$label: no TOC');
      return;
    }

    var resolvedLocator = currentLocator;
    if (resolvedLocator == null && whenReady != null) {
      R2Log.d('$label: locator cache is cold, waiting for the reader');
      try {
        resolvedLocator = await whenReady;
      } on ReadiumError {
        // The view was released before it reported a locator — a publication
        // swap. There is no position to skip from and no channel to skip on.
        return;
      }
    }
    if (resolvedLocator == null) {
      R2Log.d('$label: no current locator');
      return;
    }
    final position = resolvedLocator;

    final resolved = resolveCurrentTocIndex(
      currentLocator: position,
      toc: toc,
      lastNavigatedTocIndex: _lastNavigatedTocIndex,
      lastMatch: forward,
    );
    if (resolved.storedIndexStale) {
      _lastNavigatedTocIndex = null;
    }
    R2Log.d('$label: curIndex=${resolved.index}, tocLength=${toc.length}');

    final decide = forward ? decideSkipToNext : decideSkipToPrevious;
    NavigationDecision decideFrom(int tocIndex) => decide(
      currentLocator: position,
      toc: toc,
      readingOrder: publication.readingOrder,
      currentTocIndex: tocIndex,
      publication: publication,
    );

    var decision = decideFrom(resolved.index);

    // An entry on the page the reader is already showing cannot move it:
    // `EpubPage._scrollToProcessedRange` declines to scroll a visible range,
    // and in paginated mode the page is the unit of display. Walk past those,
    // so a tap always lands somewhere new. Bounded by construction — the walk
    // stops at the first entry in another resource, and a resource holds
    // finitely many entries.
    if (channel != null && !isPdfToc(toc)) {
      final currentPath = normalizePath(position.hrefPath);

      while (decision.canNavigate) {
        final link = decision.targetLink!;
        // Another resource always re-renders, so it always moves.
        if (normalizePath(link.hrefPart) != currentPath) break;
        final candidate = publication.locatorFromLink(link);
        // Not reachable from a contents entry since 0.19.0: line 69 filters the
        // list to entries that resolve. It stays for the other source of links
        // here — `decide*` hands back a raw `readingOrder` link when it walks
        // past the last or first contents entry (`navigation_helper.dart`,
        // `navigate(nextPage, null)` and `navigate(firstPage, null)`), and that
        // link is unfiltered. `Publication.fromJson` drops reading-order links
        // with no media type, so a parsed book cannot get here, but this mixin
        // is a library API and takes whatever publication a host builds.
        if (candidate == null) break;
        if (!await channel.isLocatorVisible(candidate)) break;
        final nextIndex = decision.targetTocIndex;
        // A decision with no index targets a non-TOC page; there is nothing to
        // advance past.
        if (nextIndex == null) break;
        R2Log.d('$label: entry $nextIndex is already on screen, advancing');
        decision = decideFrom(nextIndex);
      }
    }

    if (!decision.canNavigate) {
      R2Log.d('$label: ${decision.reason}');
      return;
    }

    final targetLink = decision.targetLink!;
    final targetLocator = publication.locatorFromLink(targetLink);
    if (targetLocator == null) {
      return;
    }

    R2Log.d('$label: navigating to ${targetLink.href}');
    final generation = _stateGeneration;
    await channel?.go(
      targetLocator,
      isAudioBookWithText: false,
      animated: true,
    );
    if (generation != _stateGeneration) {
      // A reset landed while native was navigating — most likely a publication
      // swap. This index belongs to the publication that was just torn down.
      return;
    }
    _lastNavigatedTocIndex = decision.targetTocIndex;
  }
}
