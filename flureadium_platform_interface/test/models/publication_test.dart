import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('Publication', () {
    group('toJson', () {
      test('serializes publication to JSON', () {
        final publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Test Book'),
            identifier: 'test-id',
            languages: ['en'],
          ),
          links: [Link(href: 'manifest.json', type: 'application/json')],
          readingOrder: [
            Link(href: 'chapter1.xhtml', type: 'application/xhtml+xml'),
          ],
          resources: [
            Link(href: 'cover.jpg', type: 'image/jpeg', rels: ['cover']),
          ],
        );

        final json = publication.toJson();

        expect(json['metadata']['title'], equals({'und': 'Test Book'}));
        expect(json['links'], hasLength(1));
        expect(json['links'][0]['href'], equals('manifest.json'));
        expect(json['readingOrder'], hasLength(1));
        expect(json['readingOrder'][0]['href'], equals('chapter1.xhtml'));
      });

      test('roundtrip serialization preserves data', () {
        final original = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Roundtrip Test'),
            identifier: 'roundtrip-id',
            languages: ['en', 'fr'],
          ),
          readingOrder: [
            Link(
              href: 'chapter1.xhtml',
              type: 'application/xhtml+xml',
              title: 'Chapter 1',
            ),
          ],
        );

        final json = original.toJson();
        final restored = Publication.fromJson(json, packaged: true);

        expect(restored, isNotNull);
        expect(restored!.metadata.title, equals(original.metadata.title));
        expect(
          restored.metadata.identifier,
          equals(original.metadata.identifier),
        );
      });
    });

    group('linkWithHref', () {
      late Publication publication;

      setUp(() {
        publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Test'),
          ),
          readingOrder: [
            Link(href: 'chapter1.xhtml', type: 'text/html', title: 'Chapter 1'),
            Link(href: 'chapter2.xhtml', type: 'text/html', title: 'Chapter 2'),
          ],
          resources: [
            Link(href: 'cover.jpg', type: 'image/jpeg'),
            Link(href: 'style.css', type: 'text/css'),
          ],
        );
      });

      test('finds link in readingOrder', () {
        final link = publication.linkWithHref('chapter1.xhtml');
        expect(link, isNotNull);
        expect(link!.title, equals('Chapter 1'));
      });

      test('finds link in resources', () {
        final link = publication.linkWithHref('cover.jpg');
        expect(link, isNotNull);
        expect(link!.type, equals('image/jpeg'));
      });

      test('returns null for non-existent href', () {
        final link = publication.linkWithHref('nonexistent.xhtml');
        expect(link, isNull);
      });

      test('finds link ignoring fragment', () {
        final link = publication.linkWithHref('chapter1.xhtml#section1');
        expect(link, isNotNull);
        expect(link!.href, equals('chapter1.xhtml'));
      });

      test('finds link ignoring query parameters', () {
        final link = publication.linkWithHref('chapter1.xhtml?page=1');
        expect(link, isNotNull);
        expect(link!.href, equals('chapter1.xhtml'));
      });
    });

    group('linkWithRel', () {
      late Publication publication;

      setUp(() {
        publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Test'),
          ),
          links: [
            Link(
              href: 'manifest.json',
              rels: ['self'],
              type: 'application/json',
            ),
          ],
          resources: [
            Link(href: 'cover.jpg', rels: ['cover'], type: 'image/jpeg'),
          ],
        );
      });

      test('finds link with relation', () {
        final link = publication.linkWithRel('cover');
        expect(link, isNotNull);
        expect(link!.href, equals('cover.jpg'));
      });

      test('returns null for non-existent relation', () {
        final link = publication.linkWithRel('nonexistent');
        expect(link, isNull);
      });
    });

    group('locatorFromLink', () {
      late Publication publication;

      setUp(() {
        publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Test'),
          ),
          readingOrder: [
            Link(
              href: 'chapter1.xhtml',
              type: 'application/xhtml+xml',
              title: 'Chapter 1',
            ),
            Link(
              href: 'chapter2.xhtml',
              type: 'application/xhtml+xml',
              title: 'Chapter 2',
            ),
          ],
        );
      });

      test('creates locator from link', () {
        final link = Link(
          href: 'chapter1.xhtml',
          type: 'application/xhtml+xml',
        );
        final locator = publication.locatorFromLink(link);

        expect(locator, isNotNull);
        expect(locator!.href, equals('chapter1.xhtml'));
        expect(locator.type, equals('application/xhtml+xml'));
      });

      test('creates locator with fragment', () {
        final link = Link(
          href: 'chapter1.xhtml#section1',
          type: 'application/xhtml+xml',
        );
        final locator = publication.locatorFromLink(link);

        expect(locator, isNotNull);
        expect(locator!.href, equals('chapter1.xhtml'));
        expect(locator.locations?.fragments, contains('section1'));
      });

      test('sets position based on reading order index', () {
        final link = Link(
          href: 'chapter2.xhtml',
          type: 'application/xhtml+xml',
        );
        final locator = publication.locatorFromLink(link);

        expect(locator, isNotNull);
        expect(locator!.locations?.position, equals(2));
      });
    });

    group('coverLink', () {
      test('finds cover link by rel', () {
        final publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Test'),
          ),
          resources: [
            Link(href: 'cover.jpg', rels: ['cover'], type: 'image/jpeg'),
            Link(href: 'other.jpg', type: 'image/jpeg'),
          ],
        );

        expect(publication.coverLink, isNotNull);
        expect(publication.coverLink!.href, equals('cover.jpg'));
      });

      test('returns null when no cover link exists', () {
        final publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Test'),
          ),
          resources: [Link(href: 'image.jpg', type: 'image/jpeg')],
        );

        expect(publication.coverLink, isNull);
      });
    });

    group('edge cases', () {
      test('handles empty collections', () {
        final publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Empty Test'),
          ),
        );

        expect(publication.readingOrder, isEmpty);
        expect(publication.resources, isEmpty);
        expect(publication.links, isEmpty);
        expect(publication.tableOfContents, isEmpty);
        expect(publication.context, isEmpty);
      });

      test('copyWith creates new instance with updated values', () {
        final original = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Original'),
          ),
        );

        final copied = original.copyWith(
          context: ['https://readium.org/webpub-manifest/context.jsonld'],
        );

        expect(
          copied.context,
          equals(['https://readium.org/webpub-manifest/context.jsonld']),
        );
        expect(original.context, isEmpty);
      });

      test('identifier uses metadata identifier or fallback', () {
        final withId = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Test'),
            identifier: 'custom-id',
          ),
        );

        final withoutId = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Test'),
          ),
        );

        expect(withId.identifier, equals('custom-id'));
        expect(withoutId.identifier, equals('unidentified'));
      });

      test('toc is alias for tableOfContents', () {
        final publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Test'),
          ),
          tableOfContents: [Link(href: 'ch1.xhtml', title: 'Chapter 1')],
        );

        expect(publication.toc, equals(publication.tableOfContents));
        expect(publication.toc.length, equals(1));
      });
    });

    group('conformsTo', () {
      test('conformsToReadiumAudiobook returns true for audiobook', () {
        final publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Audiobook'),
            conformsTo: [
              'https://readium.org/webpub-manifest/profiles/audiobook',
            ],
          ),
        );

        expect(publication.conformsToReadiumAudiobook, isTrue);
        expect(publication.conformsToReadiumEbook, isFalse);
      });

      test('conformsToReadiumEbook returns true for epub', () {
        final publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Ebook'),
            conformsTo: ['https://readium.org/webpub-manifest/profiles/epub'],
          ),
        );

        expect(publication.conformsToReadiumEbook, isTrue);
        expect(publication.conformsToReadiumAudiobook, isFalse);
      });
    });
  });
}
