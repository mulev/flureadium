import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('Publication', () {
    group('fromJson', () {
      test('parses complete publication manifest', () {
        final json = {
          'metadata': {
            'title': 'Test Book',
            'identifier': 'urn:isbn:123456789',
            'language': ['en'],
            'author': [
              {'name': 'Test Author'},
            ],
          },
          'links': [
            {
              'href': 'manifest.json',
              'rel': 'self',
              'type': 'application/json',
            },
          ],
          'readingOrder': [
            {'href': 'chapter1.xhtml', 'type': 'application/xhtml+xml'},
            {'href': 'chapter2.xhtml', 'type': 'application/xhtml+xml'},
          ],
          'resources': [
            {'href': 'cover.jpg', 'rel': 'cover', 'type': 'image/jpeg'},
            {'href': 'style.css', 'type': 'text/css'},
          ],
          'toc': [
            {'href': 'chapter1.xhtml', 'title': 'Chapter 1'},
            {'href': 'chapter2.xhtml', 'title': 'Chapter 2'},
          ],
        };

        final publication = Publication.fromJson(json, packaged: true);

        expect(publication, isNotNull);
        expect(publication!.metadata.title, equals('Test Book'));
        expect(publication.metadata.identifier, equals('urn:isbn:123456789'));
        expect(publication.readingOrder.length, equals(2));
        expect(publication.resources.length, equals(2));
        expect(publication.tableOfContents.length, equals(2));
      });

      test('returns null for null json', () {
        expect(Publication.fromJson(null), isNull);
      });

      test('returns null for json without metadata', () {
        final json = {'links': [], 'readingOrder': []};

        expect(Publication.fromJson(json), isNull);
      });

      test('parses publication with minimal metadata', () {
        final json = {
          'metadata': {'title': 'Minimal Book'},
          'links': [],
          'readingOrder': [],
        };

        final publication = Publication.fromJson(json, packaged: true);

        expect(publication, isNotNull);
        expect(publication!.metadata.title, equals('Minimal Book'));
        expect(publication.readingOrder, isEmpty);
        expect(publication.resources, isEmpty);
      });

      test(
        'parses readingOrder hrefs verbatim when no self link and not packaged',
        () {
          final json = {
            'metadata': {'title': 'Comic'},
            'links': <dynamic>[],
            'readingOrder': [
              {'href': '001.jpg', 'type': 'image/jpeg'},
              {'href': '002.jpg', 'type': 'image/jpeg'},
            ],
          };

          final publication = Publication.fromJson(json);

          expect(publication, isNotNull);
          expect(publication!.readingOrder.first.href, equals('001.jpg'));
          expect(publication.readingOrder[1].href, equals('002.jpg'));
        },
      );

      test('applies baseHref derived from self link when present', () {
        final json = {
          'metadata': {'title': 'Remote Book'},
          'links': [
            {
              'href': 'http://example.com/path/manifest.json',
              'rel': 'self',
              'type': 'application/json',
            },
          ],
          'readingOrder': [
            {'href': 'chapter1.xhtml', 'type': 'application/xhtml+xml'},
          ],
        };

        final publication = Publication.fromJson(json);

        expect(publication, isNotNull);
        expect(
          publication!.readingOrder.first.href,
          equals('http://example.com/path/chapter1.xhtml'),
        );
      });

      test('preserves leading slash when packaged: true', () {
        final json = {
          'metadata': {'title': 'Packaged Book'},
          'links': <dynamic>[],
          'readingOrder': [
            {'href': 'chapter1.xhtml', 'type': 'application/xhtml+xml'},
          ],
        };

        final publication = Publication.fromJson(json, packaged: true);

        expect(publication, isNotNull);
        expect(publication!.readingOrder.first.href, equals('/chapter1.xhtml'));
      });

      // A packaged publication's manifest names itself with a relative href.
      // Resolving against it cannot make siblings absolute, and the Locator
      // stream never carries a leading slash, so hrefs must stay verbatim —
      // see docs/api-reference/publication.md. This is the shape Android sends
      // for .audiobook and packaged .webpub, because readium-kotlin keeps the
      // self link where readium-swift strips it.
      test('keeps hrefs verbatim when the self link is relative', () {
        final json = {
          'metadata': {'title': 'Packaged Audiobook'},
          'links': [
            {
              'href': 'manifest.json',
              'rel': 'self',
              'type': 'application/webpub.json',
            },
          ],
          'readingOrder': [
            {'href': '01_a.mp3', 'type': 'audio/mpeg'},
            {'href': '02_b.mp3', 'type': 'audio/mpeg'},
          ],
          'resources': [
            {'href': 'cover.jpg', 'type': 'image/jpeg'},
          ],
          'toc': [
            {'href': '01_a.mp3', 'title': 'One'},
          ],
        };

        final publication = Publication.fromJson(json);

        expect(publication, isNotNull);
        expect(publication!.readingOrder.first.href, equals('01_a.mp3'));
        expect(publication.readingOrder[1].href, equals('02_b.mp3'));
        expect(publication.resources.first.href, equals('cover.jpg'));
        expect(publication.tableOfContents.first.href, equals('01_a.mp3'));
      });

      // The boundary of the rule above: a self link that does name a location
      // still resolves. Guards against collapsing the rule into "never
      // resolve".
      test('resolves hrefs against a root-relative self link', () {
        final json = {
          'metadata': {'title': 'Rooted Book'},
          'links': [
            {'href': '/dir/manifest.json', 'rel': 'self'},
          ],
          'readingOrder': [
            {'href': 'chapter1.xhtml', 'type': 'application/xhtml+xml'},
          ],
        };

        final publication = Publication.fromJson(json);

        expect(publication, isNotNull);
        expect(
          publication!.readingOrder.first.href,
          equals('/dir/chapter1.xhtml'),
        );
      });

      // Looking up the self link must not consume the links array.
      test('keeps the links the manifest declares', () {
        final json = {
          'metadata': {'title': 'Linked Book'},
          'links': [
            {
              'href': 'manifest.json',
              'rel': 'self',
              'type': 'application/webpub.json',
            },
            {'href': 'about.html', 'rel': 'alternate', 'type': 'text/html'},
          ],
          'readingOrder': [
            {'href': 'chapter1.xhtml', 'type': 'application/xhtml+xml'},
          ],
        };

        final publication = Publication.fromJson(json);

        expect(publication, isNotNull);
        expect(publication!.links, hasLength(2));
        expect(
          publication.links.firstWhere((l) => l.rels.contains('self')).href,
          equals('manifest.json'),
        );
        expect(
          publication.links
              .firstWhere((l) => l.rels.contains('alternate'))
              .href,
          equals('about.html'),
        );
      });

      // The invariant the Android audiobook integration tests assert, pinned
      // here so it cannot regress without a device: a Locator built from a
      // reading-order Link carries that Link's href unchanged.
      test('round-trips a verbatim href through locatorFromLink', () {
        final json = {
          'metadata': {'title': 'Packaged Audiobook'},
          'links': [
            {'href': 'manifest.json', 'rel': 'self'},
          ],
          'readingOrder': [
            {'href': '01_a.mp3', 'type': 'audio/mpeg'},
          ],
        };

        final publication = Publication.fromJson(json)!;
        final link = publication.readingOrder.first;
        final locator = publication.locatorFromLink(link);

        expect(locator, isNotNull);
        expect(locator!.href, equals(link.href));
      });
    });
  });
}
