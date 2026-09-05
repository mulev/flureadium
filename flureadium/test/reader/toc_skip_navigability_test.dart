import 'package:flureadium/src/reader/toc_skip_navigation_mixin.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_reader_channel.dart';

// Test class that uses the mixin.
class TestTocSkipNavigator with TocSkipNavigationMixin {}

/// A publication whose middle contents entry names a file present in neither
/// the reading order nor the resources, so `locatorFromLink` answers null for
/// it and no navigation can ever land there.
///
/// The ghost entry carries a `type:` of its own on purpose: `locatorFromLink`
/// reads the type off `linkWithHref(hrefHead)` — the resource the entry points
/// at — never off the contents entry itself, so a typed entry pointing at
/// nothing is still unreachable.
Publication _ghostMiddlePublication() => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('Ghost Middle Book'),
    identifier: 'ghost-middle-book',
  ),
  readingOrder: [
    Link(href: '/a.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/c.xhtml', type: 'application/xhtml+xml'),
  ],
  tableOfContents: [
    Link(href: '/a.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/ghost.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/c.xhtml', type: 'application/xhtml+xml'),
  ],
);

/// The tail shape: the only entry after the reader's own is unreachable, so
/// the navigable contents end where the reader is standing.
///
/// The reading order carries a second document that no contents entry names —
/// an afterword, a colophon, the ordinary shape of a book whose nav document
/// does not list everything. It is what makes the two roads separable: the
/// already-at-last-chapter branch goes there, and a skip that targets the
/// ghost instead goes nowhere at all.
Publication _ghostTailPublication() => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('Ghost Tail Book'),
    identifier: 'ghost-tail-book',
  ),
  readingOrder: [
    Link(href: '/a.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/b.xhtml', type: 'application/xhtml+xml'),
  ],
  tableOfContents: [
    Link(href: '/a.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/ghost.xhtml', type: 'application/xhtml+xml'),
  ],
);

/// The head shape, the mirror of the tail one and the half the first round of
/// tests left uncovered.
///
/// The only entry before the reader's is unreachable, so the navigable
/// contents begin where the reader is standing and `decideSkipToPrevious`
/// takes its already-at-first-chapter branch. The reading order carries a
/// document before it that no contents entry names — a cover or a
/// frontmatter page — so that branch has somewhere to go and the two roads
/// separate: filtered lands on it, unfiltered aims at the ghost and dies.
Publication _ghostHeadPublication() => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('Ghost Head Book'),
    identifier: 'ghost-head-book',
  ),
  readingOrder: [
    Link(href: '/intro.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/b.xhtml', type: 'application/xhtml+xml'),
  ],
  tableOfContents: [
    Link(href: '/ghost.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/b.xhtml', type: 'application/xhtml+xml'),
  ],
);

/// Every entry resolves — the shape of every book anyone actually reads. The
/// filter must be invisible here.
Publication _healthyPublication() => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('Healthy Book'),
    identifier: 'healthy-book',
  ),
  readingOrder: [
    Link(href: '/a.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/b.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/c.xhtml', type: 'application/xhtml+xml'),
  ],
  tableOfContents: [
    Link(href: '/a.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/b.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/c.xhtml', type: 'application/xhtml+xml'),
  ],
);

Locator _at(String href) => Locator(href: href, type: 'application/xhtml+xml');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TocSkipNavigationMixin navigability', () {
    late TestTocSkipNavigator navigator;
    late MockReaderChannel channel;

    setUp(() {
      navigator = TestTocSkipNavigator();
      channel = MockReaderChannel();
    });

    test('a backward skip passes over an unreachable entry', () async {
      // Unfiltered, the reader in C sits at index 2 of [A, ghost, C] and
      // "previous" targets the ghost: the walk breaks at the resource
      // boundary, `locatorFromLink` answers null, and the tap does nothing.
      await navigator.skipToPreviousChapter(
        publication: _ghostMiddlePublication(),
        currentLocator: _at('/c.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, '/a.xhtml');
    });

    test('a forward skip passes over an unreachable entry', () async {
      await navigator.skipToNextChapter(
        publication: _ghostMiddlePublication(),
        currentLocator: _at('/a.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, '/c.xhtml');
    });

    test('an unreachable last entry ends the contents', () async {
      // The tail case, and the one that pins the boundary. The reader is at
      // the last entry it can reach, so `decideSkipToNext` takes its
      // already-at-last-chapter branch (navigation_helper.dart:103) and
      // continues into the spine — landing on the document after A, which no
      // contents entry names. Aiming at the ghost instead, as the unfiltered
      // list does, lands nowhere: the assertion separates the two branches
      // rather than watching two silences.
      await navigator.skipToNextChapter(
        publication: _ghostTailPublication(),
        currentLocator: _at('/a.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, '/b.xhtml');
    });

    test('an unreachable first entry begins the contents', () async {
      // The mirror of the case above. The reader is at the first entry it can
      // reach, so `decideSkipToPrevious` takes its already-at-first-chapter
      // branch (navigation_helper.dart:203) and steps back into the spine,
      // landing on the document before B. Unfiltered, B sits at index 1 of
      // [ghost, B], "previous" targets the ghost, and the tap does nothing.
      await navigator.skipToPreviousChapter(
        publication: _ghostHeadPublication(),
        currentLocator: _at('/b.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, '/intro.xhtml');
    });

    test('a forward skip on a fully reachable book is unchanged', () async {
      await navigator.skipToNextChapter(
        publication: _healthyPublication(),
        currentLocator: _at('/a.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, '/b.xhtml');
    });

    test('a backward skip on a fully reachable book is unchanged', () async {
      await navigator.skipToPreviousChapter(
        publication: _healthyPublication(),
        currentLocator: _at('/c.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, '/b.xhtml');
    });
  });
}
