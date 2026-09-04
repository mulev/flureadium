import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flureadium/src/utils/toc_matcher.dart';

Publication _publication({
  List<Link> toc = const [],
  List<Link> readingOrder = const [],
}) => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('Test Book'),
    identifier: 'test-book',
  ),
  readingOrder: readingOrder,
  tableOfContents: toc,
);

void main() {
  group('navigableToc', () {
    const xhtml = 'application/xhtml+xml';

    test('returns every entry when all of them resolve', () {
      final publication = _publication(
        toc: [
          Link(href: '/a.xhtml'),
          Link(href: '/b.xhtml'),
          Link(href: '/c.xhtml'),
        ],
        readingOrder: [
          Link(href: '/a.xhtml', type: xhtml),
          Link(href: '/b.xhtml', type: xhtml),
          Link(href: '/c.xhtml', type: xhtml),
        ],
      );

      expect(
        navigableToc(publication).map((l) => l.href).toList(),
        flattenToc(publication.toc).map((l) => l.href).toList(),
      );
    });

    test('drops an unresolvable entry from the middle and keeps the order', () {
      final publication = _publication(
        toc: [
          Link(href: '/a.xhtml'),
          Link(href: '/b.xhtml'),
          Link(href: '/c.xhtml'),
        ],
        readingOrder: [
          Link(href: '/a.xhtml', type: xhtml),
          Link(href: '/c.xhtml', type: xhtml),
        ],
      );

      expect(navigableToc(publication).map((l) => l.href).toList(), [
        '/a.xhtml',
        '/c.xhtml',
      ]);
    });

    // This is the case that makes decideSkipToNext's already-at-last-chapter
    // branch correct: a reader in /a.xhtml is at index 0 of a one-element
    // list, so `currentTocIndex >= toc.length - 1` holds.
    test('the last element is the last reachable entry when the final entry '
        'cannot resolve', () {
      final publication = _publication(
        toc: [
          Link(href: '/a.xhtml'),
          Link(href: '/b.xhtml'),
        ],
        readingOrder: [Link(href: '/a.xhtml', type: xhtml)],
      );

      expect(navigableToc(publication).map((l) => l.href).toList(), [
        '/a.xhtml',
      ]);
    });

    test('flattens a nested tree before filtering', () {
      final publication = _publication(
        toc: [
          Link(
            href: '/part.xhtml',
            children: [
              Link(href: '/ch1.xhtml'),
              Link(href: '/ghost.xhtml'),
            ],
          ),
        ],
        readingOrder: [
          Link(href: '/part.xhtml', type: xhtml),
          Link(href: '/ch1.xhtml', type: xhtml),
        ],
      );

      expect(navigableToc(publication).map((l) => l.href).toList(), [
        '/part.xhtml',
        '/ch1.xhtml',
      ]);
    });

    test('returns an empty list for empty contents', () {
      expect(navigableToc(_publication()), isEmpty);
    });

    // The second way locatorFromLink returns null: the href matches a
    // resource, but that resource carries no type. Publication.fromJson
    // filters null-type readingOrder links out (publication.dart:240, 245);
    // the const constructor used here does not, which is why this fixture can
    // express the shape at all.
    test('drops an entry whose resource carries a null type', () {
      final publication = _publication(
        toc: [
          Link(href: '/a.xhtml'),
          Link(href: '/b.xhtml'),
        ],
        readingOrder: [
          Link(href: '/a.xhtml', type: xhtml),
          Link(href: '/b.xhtml'),
        ],
      );

      expect(navigableToc(publication).map((l) => l.href).toList(), [
        '/a.xhtml',
      ]);
    });
  });
}
