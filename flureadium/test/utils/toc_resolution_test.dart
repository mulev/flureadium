import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flureadium/src/utils/toc_matcher.dart';

Locator _locator(String href) =>
    Locator(href: href, type: 'application/xhtml+xml');

void main() {
  group('findTocIndexByFragment', () {
    final toc = [
      Link(href: '/ch1.xhtml#top'),
      Link(href: '/ch2.xhtml#top'),
      Link(href: '/ch2.xhtml#middle'),
      Link(href: '/ch3.xhtml'),
    ];

    test('finds an id in the reader\'s own resource', () {
      final match = findTocIndexByFragment(toc, 'middle', '/ch2.xhtml');

      expect(match, (index: 2, ownFile: true));
    });

    test('own resource wins over the same id earlier in the contents', () {
      final match = findTocIndexByFragment(toc, 'top', '/ch2.xhtml');

      expect(match, (index: 1, ownFile: true));
    });

    test('falls back to the whole contents, reporting ownFile false', () {
      final match = findTocIndexByFragment(toc, 'middle', '/ch3.xhtml');

      expect(match, (index: 2, ownFile: false));
    });

    test('returns -1 when the id is nowhere in the contents', () {
      final match = findTocIndexByFragment(toc, 'nowhere', '/ch1.xhtml');

      expect(match, (index: -1, ownFile: false));
    });

    test('returns -1 for an empty fragment without scanning', () {
      final match = findTocIndexByFragment(toc, '', '/ch1.xhtml');

      expect(match, (index: -1, ownFile: false));
    });

    test('matches when the contents carry a leading slash and the path '
        'does not', () {
      final match = findTocIndexByFragment(toc, 'middle', 'ch2.xhtml');

      expect(match, (index: 2, ownFile: true));
    });

    test('matches when the path carries a leading slash and the contents '
        'do not', () {
      final unslashed = [Link(href: 'ch1.xhtml#a'), Link(href: 'ch1.xhtml#b')];
      final match = findTocIndexByFragment(unslashed, 'b', '/ch1.xhtml');

      expect(match, (index: 1, ownFile: true));
    });
  });

  group('resolveCurrentTocIndex', () {
    final toc = [
      Link(href: 'ch1.xhtml'),
      Link(href: 'ch2.xhtml'),
      Link(href: 'ch3.xhtml'),
    ];
    // Three entries share ch1.xhtml, so first- and last-match path fallbacks
    // land on different indices.
    final sharedFileToc = [
      Link(href: 'ch1.xhtml'),
      Link(href: 'ch1.xhtml#a'),
      Link(href: 'ch1.xhtml#b'),
      Link(href: 'ch2.xhtml'),
    ];

    test('keeps a stored index that still points at the locator file', () {
      final resolved = resolveCurrentTocIndex(
        currentLocator: _locator('/ch2.xhtml'),
        toc: toc,
        lastNavigatedTocIndex: 1,
        lastMatch: true,
      );

      expect(resolved.index, 1);
      expect(resolved.storedIndexStale, isFalse);
    });

    test('reports a stored index stale once the file changed', () {
      final resolved = resolveCurrentTocIndex(
        currentLocator: _locator('/ch3.xhtml'),
        toc: toc,
        lastNavigatedTocIndex: 1,
        lastMatch: true,
      );

      expect(resolved.index, 2);
      expect(resolved.storedIndexStale, isTrue);
    });

    test('ignores a stored index that is out of range for the TOC', () {
      final resolved = resolveCurrentTocIndex(
        currentLocator: _locator('/ch1.xhtml'),
        toc: toc,
        lastNavigatedTocIndex: 9,
        lastMatch: true,
      );

      expect(resolved.index, 0);
      expect(resolved.storedIndexStale, isFalse);
    });

    test('prefers a toc= fragment match over the path fallback', () {
      // Ordered so the two strategies disagree: the fragment match is index 1,
      // the lastMatch path fallback would be index 2.
      final fragmentToc = [
        Link(href: '/ch2.xhtml'),
        Link(href: '/ch1.xhtml#section-two'),
        Link(href: '/ch1.xhtml'),
      ];
      final locator = Locator(
        href: '/ch1.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(fragments: ['toc=section-two']),
      );

      final resolved = resolveCurrentTocIndex(
        currentLocator: locator,
        toc: fragmentToc,
        lastNavigatedTocIndex: null,
        lastMatch: true,
      );

      expect(resolved.index, 1);
      expect(resolved.storedIndexStale, isFalse);
    });

    test(
      'falls back to path matching when the toc= fragment matches no entry',
      () {
        final fragmentToc = [
          Link(href: '/ch1.xhtml'),
          Link(href: '/ch2.xhtml'),
        ];
        final locator = Locator(
          href: '/ch2.xhtml',
          type: 'application/xhtml+xml',
          locations: Locations(fragments: ['toc=nowhere']),
        );

        final resolved = resolveCurrentTocIndex(
          currentLocator: locator,
          toc: fragmentToc,
          lastNavigatedTocIndex: null,
          lastMatch: true,
        );

        expect(resolved.index, 1);
      },
    );

    test('falls back to the last path match when lastMatch is true', () {
      final resolved = resolveCurrentTocIndex(
        currentLocator: _locator('/ch1.xhtml'),
        toc: sharedFileToc,
        lastNavigatedTocIndex: null,
        lastMatch: true,
      );

      expect(resolved.index, 2);
    });

    test('falls back to the first path match when lastMatch is false', () {
      final resolved = resolveCurrentTocIndex(
        currentLocator: _locator('/ch1.xhtml'),
        toc: sharedFileToc,
        lastNavigatedTocIndex: null,
        lastMatch: false,
      );

      expect(resolved.index, 0);
    });

    test('a cross-resource fragment does not beat path matching', () {
      // The id-collision book: `chapter` names an entry in ch1 while the
      // reader is in ch2. Path matching is the better answer.
      final collidingToc = [
        Link(href: '/ch1.xhtml#chapter'),
        Link(href: '/ch2.xhtml'),
      ];

      final resolved = resolveCurrentTocIndex(
        currentLocator: Locator(
          href: '/ch2.xhtml',
          type: 'application/xhtml+xml',
          locations: Locations(fragments: ['toc=chapter']),
        ),
        toc: collidingToc,
        lastNavigatedTocIndex: null,
        lastMatch: false,
      );

      expect(resolved.index, 1);
    });

    test('a nav document with no leading slashes resolves by fragment', () {
      final unslashedToc = [
        Link(href: 'ch1.xhtml#a'),
        Link(href: 'ch1.xhtml#b'),
      ];

      final resolved = resolveCurrentTocIndex(
        currentLocator: Locator(
          href: 'ch1.xhtml',
          type: 'application/xhtml+xml',
          locations: Locations(fragments: ['toc=b']),
        ),
        toc: unslashedToc,
        lastNavigatedTocIndex: null,
        lastMatch: false,
      );

      expect(resolved.index, 1);
    });

    test('uses page matching for a PDF-shaped TOC', () {
      final pdfToc = [
        Link(href: 'doc.pdf#page=1'),
        Link(href: 'doc.pdf#page=10'),
        Link(href: 'doc.pdf#page=20'),
      ];

      final resolved = resolveCurrentTocIndex(
        currentLocator: Locator(
          href: 'doc.pdf',
          type: 'application/pdf',
          locations: Locations(position: 12),
        ),
        toc: pdfToc,
        lastNavigatedTocIndex: null,
        lastMatch: true,
      );

      expect(resolved.index, 1);
    });

    test('returns -1 when nothing matches', () {
      final resolved = resolveCurrentTocIndex(
        currentLocator: _locator('/unknown.xhtml'),
        toc: toc,
        lastNavigatedTocIndex: null,
        lastMatch: true,
      );

      expect(resolved.index, -1);
      expect(resolved.storedIndexStale, isFalse);
    });
  });
}
