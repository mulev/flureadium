import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flureadium/src/utils/toc_matcher.dart';

Locator _locator(String href) =>
    Locator(href: href, type: 'application/xhtml+xml');

Locator _pdfLocator(String href, {int? position}) => Locator(
  href: href,
  type: 'application/pdf',
  locations: Locations(position: position),
);

void main() {
  group('tocHrefWithFragment', () {
    test('returns null for a null locator', () {
      expect(tocHrefWithFragment(null), isNull);
    });

    test('returns null when the locator carries no toc= fragment', () {
      final locator = Locator(
        href: '/ch1.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(fragments: ['page=3']),
      );

      expect(tocHrefWithFragment(locator), isNull);
    });

    test('appends the fragment value to the text locator href path', () {
      final locator = Locator(
        href: '/ch1.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(fragments: ['toc=intro']),
      );

      // `hrefPath` normalises through `String.path`, which guarantees a
      // leading slash — TOC hrefs carry one too, so the two compare equal.
      expect(tocHrefWithFragment(locator), '/ch1.xhtml#intro');
    });

    test('is unchanged by a redundant second toTextLocator pass', () {
      final locator = Locator(
        href: '/ch1.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(fragments: ['toc=intro']),
      );

      // Pins the behaviour the collapsed double call used to produce.
      expect(
        tocHrefWithFragment(locator),
        '${locator.toTextLocator().toTextLocator().hrefPath}#intro',
      );
    });

    test('drops a query string and picks the toc= fragment among others', () {
      final locator = Locator(
        href: '/OEBPS/ch2.xhtml?v=2',
        type: 'application/xhtml+xml',
        locations: Locations(fragments: ['t=12.5', 'toc=part-two']),
      );

      expect(tocHrefWithFragment(locator), '/OEBPS/ch2.xhtml#part-two');
    });
  });

  group('resolveCurrentTocIndex', () {
    final toc = [
      Link(href: 'ch1.xhtml'),
      Link(href: 'ch2.xhtml'),
      Link(href: 'ch3.xhtml'),
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
      final sharedFileToc = [
        Link(href: 'ch1.xhtml'),
        Link(href: 'ch1.xhtml#a'),
        Link(href: 'ch1.xhtml#b'),
        Link(href: 'ch2.xhtml'),
      ];

      final resolved = resolveCurrentTocIndex(
        currentLocator: _locator('/ch1.xhtml'),
        toc: sharedFileToc,
        lastNavigatedTocIndex: null,
        lastMatch: true,
      );

      expect(resolved.index, 2);
    });

    test('falls back to the first path match when lastMatch is false', () {
      final sharedFileToc = [
        Link(href: 'ch1.xhtml'),
        Link(href: 'ch1.xhtml#a'),
        Link(href: 'ch1.xhtml#b'),
        Link(href: 'ch2.xhtml'),
      ];

      final resolved = resolveCurrentTocIndex(
        currentLocator: _locator('/ch1.xhtml'),
        toc: sharedFileToc,
        lastNavigatedTocIndex: null,
        lastMatch: false,
      );

      expect(resolved.index, 0);
    });

    test('uses page matching for a PDF-shaped TOC', () {
      final pdfToc = [
        Link(href: 'doc.pdf#page=1'),
        Link(href: 'doc.pdf#page=10'),
        Link(href: 'doc.pdf#page=20'),
      ];

      final resolved = resolveCurrentTocIndex(
        currentLocator: _pdfLocator('doc.pdf', position: 12),
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
