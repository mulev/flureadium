import 'package:collection/collection.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

/// Strips leading '/' from a path for consistent comparison.
String normalizePath(String path) {
  return path.startsWith('/') ? path.substring(1) : path;
}

/// Finds the index of the given [locator]'s chapter in the [toc] by
/// matching file paths.
///
/// This is a fallback for when toc= fragment matching is unavailable
/// (e.g. EPUBs without heading element IDs).
///
/// Compares the base file path (without fragment/query) of the locator
/// against each TOC entry's href path.
///
/// When [lastMatch] is true, returns the last matching index (useful for
/// skipToNext — so "next" skips past all sub-sections in the same file).
/// When false, returns the first matching index (useful for skipToPrevious —
/// so "previous" goes before the first sub-section).
///
/// Returns -1 if no match is found.
int findTocIndexByPath(
  Locator locator,
  List<Link> toc, {
  bool lastMatch = false,
}) {
  final locatorPath = normalizePath(locator.hrefPath);

  // Exact path match
  int matchedIndex = -1;
  for (int i = 0; i < toc.length; i++) {
    final tocPath = normalizePath(toc[i].hrefPart);
    if (locatorPath == tocPath) {
      if (!lastMatch) return i;
      matchedIndex = i;
    }
  }
  if (matchedIndex != -1) return matchedIndex;

  // Fallback: match by filename only (last path segment)
  final locatorFilename = locatorPath.split('/').last;
  for (int i = 0; i < toc.length; i++) {
    final tocFilename = normalizePath(toc[i].hrefPart).split('/').last;
    if (locatorFilename == tocFilename) {
      if (!lastMatch) return i;
      matchedIndex = i;
    }
  }

  return matchedIndex;
}

/// Checks if a publication appears to be a PDF based on TOC structure.
///
/// PDFs have all TOC entries with the same base path and page fragments
/// (e.g., "doc.pdf#page=1", "doc.pdf#page=5").
///
/// Returns true if the TOC appears to be PDF-based.
bool isPdfToc(List<Link> toc) {
  if (toc.isEmpty) return false;

  // Check if first TOC entry has a page fragment
  final firstHref = toc.first.href;
  R2Log.d('isPdfToc: first href = $firstHref');
  if (!firstHref.contains('#page=')) {
    R2Log.d('isPdfToc: no #page= fragment, returning false');
    return false;
  }

  // Check if all entries have same base path (single PDF file)
  final basePath = firstHref.split('#').first;
  final result = toc.every((link) => link.href.startsWith(basePath));
  R2Log.d('isPdfToc: basePath=$basePath, result=$result');
  return result;
}

/// Finds the TOC index for a PDF locator by matching page numbers.
///
/// PDFs have all TOC entries pointing to the same file with different
/// page fragments (e.g., "doc.pdf#page=5"). This function finds the
/// TOC entry that matches or precedes the current page.
///
/// [locator] - The current position locator
/// [toc] - The table of contents links
///
/// Returns the index of the TOC entry at or before the current page,
/// or -1 if no match is found or if page info is unavailable.
int findTocIndexByPage(Locator locator, List<Link> toc) {
  // Get current page from locator - try position/fragments first
  int? currentPage = _extractPageFromLocator(locator);
  R2Log.d('findTocIndexByPage: _extractPageFromLocator returned $currentPage');

  // Fallback: estimate page from progression if position unavailable
  if (currentPage == null) {
    currentPage = _estimatePageFromProgression(locator, toc);
    R2Log.d(
      'findTocIndexByPage: _estimatePageFromProgression returned $currentPage',
    );
  }

  if (currentPage == null) {
    R2Log.d('findTocIndexByPage: no currentPage, returning -1');
    return -1;
  }

  R2Log.d(
    'findTocIndexByPage: currentPage=$currentPage, tocLength=${toc.length}',
  );

  // Log first few TOC entries for debugging
  for (int i = 0; i < toc.length && i < 3; i++) {
    final tocPage = _extractPageFromHref(toc[i].href);
    R2Log.d('findTocIndexByPage: toc[$i].href=${toc[i].href}, page=$tocPage');
  }

  int matchedIndex = -1;

  for (int i = 0; i < toc.length; i++) {
    final tocPage = _extractPageFromHref(toc[i].href);
    if (tocPage == null) continue;

    // Find TOC entries at or before current page
    if (tocPage <= currentPage) {
      matchedIndex = i;
    } else {
      // TOC page is after current page - we've found our answer
      break;
    }
  }

  R2Log.d('findTocIndexByPage: returning $matchedIndex');
  return matchedIndex;
}

/// Extracts page number from a Locator's locations.
///
/// Tries locations.position first, then parses fragments for "page=X".
int? _extractPageFromLocator(Locator locator) {
  // Try position field first (1-indexed page number)
  if (locator.locations?.position != null) {
    return locator.locations!.position!;
  }

  // Try parsing from fragments
  final fragments = locator.locations?.fragments ?? [];
  for (final fragment in fragments) {
    final page = _parsePageFragment(fragment);
    if (page != null) return page;
  }

  return null;
}

/// Extracts page number from an href like "doc.pdf#page=5".
int? _extractPageFromHref(String href) {
  final fragmentIndex = href.indexOf('#');
  if (fragmentIndex == -1) return null;

  final fragment = href.substring(fragmentIndex + 1);
  return _parsePageFragment(fragment);
}

/// Parses "page=5" fragment to integer 5.
int? _parsePageFragment(String fragment) {
  if (fragment.startsWith('page=')) {
    return int.tryParse(fragment.substring(5));
  }
  return null;
}

/// Recursively flattens a hierarchical TOC list into a single ordered list.
///
/// Readium iOS serializes EPUB3 nav documents hierarchically — chapters
/// nested inside a parent section appear as `link.children`, not as top-level
/// entries. Navigation and boundary-state logic must operate on the flat list
/// to correctly handle these publications.
List<Link> flattenToc(List<Link> toc) {
  final result = <Link>[];
  for (final link in toc) {
    result.add(link);
    if (link.children.isNotEmpty) {
      result.addAll(flattenToc(link.children));
    }
  }
  return result;
}

/// The href of [locator]'s text locator with its `toc=` fragment appended as
/// an identifier, or null when the locator carries no `toc=` fragment.
String? tocHrefWithFragment(Locator? locator) {
  if (locator == null) {
    return null;
  }

  const prefix = 'toc=';
  final tocFragment = locator.locations?.fragments.firstWhereOrNull(
    (f) => f.startsWith(prefix),
  );
  if (tocFragment == null) {
    return null;
  }

  final identifier = tocFragment.substring(prefix.length);
  return '${locator.toTextLocator().hrefPath}#$identifier';
}

/// Resolves [currentLocator]'s index in a flattened [toc].
///
/// Tries three sources in order: [lastNavigatedTocIndex] while it still points
/// at the locator's file, then `toc=` fragment matching for sub-chapter
/// granularity, then a page-based (PDF) or path-based fallback. Returns -1
/// when nothing matches.
///
/// [lastMatch] picks the last path match rather than the first — skipping
/// forward must clear all sub-sections of the current file, skipping backward
/// must land before them.
///
/// `storedIndexStale` is true when [lastNavigatedTocIndex] was supplied but no
/// longer points at the current file, so the caller can drop it.
({int index, bool storedIndexStale}) resolveCurrentTocIndex({
  required Locator currentLocator,
  required List<Link> toc,
  required int? lastNavigatedTocIndex,
  required bool lastMatch,
}) {
  if (lastNavigatedTocIndex != null && lastNavigatedTocIndex < toc.length) {
    final expectedPath = normalizePath(toc[lastNavigatedTocIndex].hrefPart);
    if (normalizePath(currentLocator.hrefPath) == expectedPath) {
      return (index: lastNavigatedTocIndex, storedIndexStale: false);
    }
    return (
      index: _matchTocIndex(currentLocator, toc, lastMatch),
      storedIndexStale: true,
    );
  }

  return (
    index: _matchTocIndex(currentLocator, toc, lastMatch),
    storedIndexStale: false,
  );
}

int _matchTocIndex(Locator currentLocator, List<Link> toc, bool lastMatch) {
  final currentHref = tocHrefWithFragment(currentLocator);
  if (currentHref != null) {
    final index = toc.indexWhere((l) => l.href == currentHref);
    if (index != -1) {
      return index;
    }
  }

  if (isPdfToc(toc)) {
    return findTocIndexByPage(currentLocator, toc);
  }
  return findTocIndexByPath(currentLocator, toc, lastMatch: lastMatch);
}

/// Estimates current page from progression (0-1 ratio).
///
/// Used as fallback when locator.locations.position is unavailable.
/// Calculates page based on: progression * lastTocPage.
int? _estimatePageFromProgression(Locator locator, List<Link> toc) {
  final progression = locator.locations?.progression;
  if (progression == null || toc.isEmpty) return null;

  // Get last page number from last TOC entry
  final lastPage = _extractPageFromHref(toc.last.href);
  if (lastPage == null) return null;

  // Estimate current page: progression goes from 0 to 1
  // page 1 = progression ~0, page N = progression ~1
  final estimatedPage = (progression * lastPage).round().clamp(1, lastPage);
  return estimatedPage;
}
