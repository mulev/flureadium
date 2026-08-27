import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flureadium/src/utils/toc_matcher.dart';

Locator _locator(String href) =>
    Locator(href: href, type: 'application/xhtml+xml');

void main() {
  group('normalizePath', () {
    test('strips leading slash', () {
      expect(normalizePath('/OEBPS/chapter1.xhtml'), 'OEBPS/chapter1.xhtml');
    });

    test('returns unchanged if no leading slash', () {
      expect(normalizePath('chapter1.xhtml'), 'chapter1.xhtml');
    });

    test('handles empty string', () {
      expect(normalizePath(''), '');
    });

    test('strips only the first slash', () {
      expect(normalizePath('//double.xhtml'), '/double.xhtml');
    });
  });

  group('findTocIndexByPath', () {
    test('matches locator href against TOC entry - exact path', () {
      final toc = [
        Link(href: 'OEBPS/ch1.xhtml'),
        Link(href: 'OEBPS/ch2.xhtml'),
        Link(href: 'OEBPS/ch3.xhtml'),
      ];
      final locator = _locator('/OEBPS/ch2.xhtml');

      expect(findTocIndexByPath(locator, toc), 1);
    });

    test('matches locator with leading slash against TOC without', () {
      final toc = [Link(href: 'chapter1.xhtml'), Link(href: 'chapter2.xhtml')];
      final locator = _locator('/chapter2.xhtml');

      expect(findTocIndexByPath(locator, toc), 1);
    });

    test('matches TOC with leading slash against locator without', () {
      final toc = [
        Link(href: '/chapter1.xhtml'),
        Link(href: '/chapter2.xhtml'),
      ];
      // Locator.hrefPath strips query/fragment but preserves leading slash,
      // so this tests the normalization in both directions
      final locator = _locator('chapter2.xhtml');

      expect(findTocIndexByPath(locator, toc), 1);
    });

    test('strips fragment from TOC href when matching', () {
      final toc = [
        Link(href: 'chapter1.xhtml#section1'),
        Link(href: 'chapter1.xhtml#section2'),
        Link(href: 'chapter2.xhtml'),
      ];
      final locator = _locator('/chapter1.xhtml');

      // firstMatch (default) returns first matching index
      expect(findTocIndexByPath(locator, toc), 0);
    });

    test('returns -1 for empty TOC', () {
      final locator = _locator('/chapter1.xhtml');

      expect(findTocIndexByPath(locator, []), -1);
    });

    test('returns -1 when no match found', () {
      final toc = [Link(href: 'chapter1.xhtml'), Link(href: 'chapter2.xhtml')];
      final locator = _locator('/chapter99.xhtml');

      expect(findTocIndexByPath(locator, toc), -1);
    });

    test('fallback matches by filename only when paths differ', () {
      final toc = [
        Link(href: 'Text/chapter1.xhtml'),
        Link(href: 'Text/chapter2.xhtml'),
      ];
      // Locator has a different directory structure
      final locator = _locator('/OEBPS/Text/chapter2.xhtml');

      // Full path won't match (Text/chapter2.xhtml != OEBPS/Text/chapter2.xhtml)
      // but filename fallback should match
      expect(findTocIndexByPath(locator, toc), 1);
    });

    group('lastMatch parameter', () {
      test('lastMatch=false returns first matching index', () {
        final toc = [
          Link(href: 'chapter1.xhtml#part1'),
          Link(href: 'chapter1.xhtml#part2'),
          Link(href: 'chapter1.xhtml#part3'),
          Link(href: 'chapter2.xhtml'),
        ];
        final locator = _locator('/chapter1.xhtml');

        expect(findTocIndexByPath(locator, toc, lastMatch: false), 0);
      });

      test('lastMatch=true returns last matching index', () {
        final toc = [
          Link(href: 'chapter1.xhtml#part1'),
          Link(href: 'chapter1.xhtml#part2'),
          Link(href: 'chapter1.xhtml#part3'),
          Link(href: 'chapter2.xhtml'),
        ];
        final locator = _locator('/chapter1.xhtml');

        expect(findTocIndexByPath(locator, toc, lastMatch: true), 2);
      });

      test('lastMatch with single match returns same index either way', () {
        final toc = [
          Link(href: 'chapter1.xhtml'),
          Link(href: 'chapter2.xhtml'),
          Link(href: 'chapter3.xhtml'),
        ];
        final locator = _locator('/chapter2.xhtml');

        expect(findTocIndexByPath(locator, toc, lastMatch: false), 1);
        expect(findTocIndexByPath(locator, toc, lastMatch: true), 1);
      });
    });

    group('filename fallback with lastMatch', () {
      test('fallback also respects lastMatch=true', () {
        final toc = [
          Link(href: 'Text/chapter1.xhtml#s1'),
          Link(href: 'Text/chapter1.xhtml#s2'),
          Link(href: 'Text/chapter2.xhtml'),
        ];
        final locator = _locator('/OEBPS/Text/chapter1.xhtml');

        expect(findTocIndexByPath(locator, toc, lastMatch: true), 1);
      });

      test('fallback also respects lastMatch=false', () {
        final toc = [
          Link(href: 'Text/chapter1.xhtml#s1'),
          Link(href: 'Text/chapter1.xhtml#s2'),
          Link(href: 'Text/chapter2.xhtml'),
        ];
        final locator = _locator('/OEBPS/Text/chapter1.xhtml');

        expect(findTocIndexByPath(locator, toc, lastMatch: false), 0);
      });
    });
  });

  group('isPdfToc', () {
    test('returns true for PDF TOC with page fragments', () {
      final toc = [
        Link(href: 'document.pdf#page=1'),
        Link(href: 'document.pdf#page=5'),
        Link(href: 'document.pdf#page=10'),
      ];

      expect(isPdfToc(toc), true);
    });

    test('returns false for EPUB TOC without page fragments', () {
      final toc = [
        Link(href: 'chapter1.xhtml'),
        Link(href: 'chapter2.xhtml#section1'),
        Link(href: 'chapter3.xhtml'),
      ];

      expect(isPdfToc(toc), false);
    });

    test('returns false for empty TOC', () {
      expect(isPdfToc([]), false);
    });

    test('returns false for EPUB with different file paths', () {
      final toc = [
        Link(href: 'OEBPS/ch1.xhtml'),
        Link(href: 'OEBPS/ch2.xhtml'),
        Link(href: 'OEBPS/ch3.xhtml'),
      ];

      expect(isPdfToc(toc), false);
    });

    test(
      'returns false if first entry has page but others do not share base',
      () {
        final toc = [
          Link(href: 'document.pdf#page=1'),
          Link(href: 'other.pdf#page=5'),
        ];

        expect(isPdfToc(toc), false);
      },
    );
  });

  group('flattenToc', () {
    test('returns empty list for empty input', () {
      expect(flattenToc([]), isEmpty);
    });

    test('returns same entries for flat list with no children', () {
      final toc = [Link(href: '/a.xhtml'), Link(href: '/b.xhtml')];
      final result = flattenToc(toc);
      expect(result.map((l) => l.href).toList(), ['/a.xhtml', '/b.xhtml']);
    });

    test('includes children after parent in depth-first order', () {
      final toc = [
        Link(
          href: '/part.xhtml',
          children: [
            Link(href: '/ch1.xhtml'),
            Link(href: '/ch2.xhtml'),
          ],
        ),
        Link(href: '/end.xhtml'),
      ];
      final result = flattenToc(toc);
      expect(result.map((l) => l.href).toList(), [
        '/part.xhtml',
        '/ch1.xhtml',
        '/ch2.xhtml',
        '/end.xhtml',
      ]);
    });

    test('handles multi-level nesting depth-first', () {
      final toc = [
        Link(
          href: '/top.xhtml',
          children: [
            Link(
              href: '/mid.xhtml',
              children: [Link(href: '/leaf.xhtml')],
            ),
          ],
        ),
      ];
      final result = flattenToc(toc);
      expect(result.map((l) => l.href).toList(), [
        '/top.xhtml',
        '/mid.xhtml',
        '/leaf.xhtml',
      ]);
    });
  });
}
