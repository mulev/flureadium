import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('Link', () {
    group('fromJson', () {
      test('parses complete link', () {
        final json = {
          'href': 'chapter1.xhtml',
          'type': 'application/xhtml+xml',
          'title': 'Chapter 1',
          'rel': 'contents',
          'height': 600,
          'width': 800,
          'bitrate': 128.5,
          'duration': 300.0,
          'language': ['en', 'fr'],
        };

        final link = Link.fromJson(json);

        expect(link, isNotNull);
        expect(link!.href, equals('chapter1.xhtml'));
        expect(link.type, equals('application/xhtml+xml'));
        expect(link.title, equals('Chapter 1'));
        expect(link.rels, contains('contents'));
        expect(link.height, equals(600));
        expect(link.width, equals(800));
        expect(link.bitrate, equals(128.5));
        expect(link.duration, equals(300.0));
        expect(link.languages, equals(['en', 'fr']));
      });

      test('returns null for null json', () {
        expect(Link.fromJson(null), isNull);
      });

      test('returns null for json without href', () {
        final json = {'type': 'text/html', 'title': 'No Href'};

        expect(Link.fromJson(json), isNull);
      });

      test('parses link with minimal required href', () {
        final json = {'href': 'minimal.html'};

        final link = Link.fromJson(json);

        expect(link, isNotNull);
        expect(link!.href, equals('minimal.html'));
        expect(link.type, isNull);
        expect(link.title, isNull);
        expect(link.templated, isFalse);
      });

      test('parses templated link', () {
        final json = {
          'href': 'https://example.com/{id}',
          'templated': true,
          'type': 'text/html',
        };

        final link = Link.fromJson(json);

        expect(link, isNotNull);
        expect(link!.templated, isTrue);
        expect(link.href, equals('https://example.com/{id}'));
      });

      test('parses link with multiple rels', () {
        final json = {
          'href': 'cover.jpg',
          'rel': ['cover', 'contents'],
        };

        final link = Link.fromJson(json);

        expect(link, isNotNull);
        expect(link!.rels, hasLength(2));
        expect(link.rels, contains('cover'));
        expect(link.rels, contains('contents'));
      });

      test('parses link with single rel string', () {
        final json = {'href': 'cover.jpg', 'rel': 'cover'};

        final link = Link.fromJson(json);

        expect(link, isNotNull);
        expect(link!.rels, equals(['cover']));
      });

      test('parses link with single language string', () {
        final json = {'href': 'chapter.html', 'language': 'en'};

        final link = Link.fromJson(json);

        expect(link, isNotNull);
        expect(link!.languages, equals(['en']));
      });

      test('parses link with children', () {
        final json = {
          'href': 'toc.html',
          'children': [
            {'href': 'chapter1.html', 'title': 'Chapter 1'},
            {'href': 'chapter2.html', 'title': 'Chapter 2'},
          ],
        };

        final link = Link.fromJson(json);

        expect(link, isNotNull);
        expect(link!.children, hasLength(2));
        expect(link.children[0].href, equals('chapter1.html'));
        expect(link.children[1].title, equals('Chapter 2'));
      });

      test('parses link with alternates', () {
        final json = {
          'href': 'chapter.html',
          'alternate': [
            {'href': 'chapter.pdf', 'type': 'application/pdf'},
            {'href': 'chapter.epub', 'type': 'application/epub+zip'},
          ],
        };

        final link = Link.fromJson(json);

        expect(link, isNotNull);
        expect(link!.alternates, hasLength(2));
        expect(link.alternates[0].type, equals('application/pdf'));
        expect(link.alternates[1].href, equals('chapter.epub'));
      });

      test('parses link with properties', () {
        final json = {
          'href': 'page.html',
          'properties': {'page': 'left'},
        };

        final link = Link.fromJson(json);

        expect(link, isNotNull);
        expect(link!.properties.page?.value, equals('left'));
      });
    });

    group('fromJsonArray', () {
      test('parses array of links', () {
        final json = [
          {'href': 'link1.html'},
          {'href': 'link2.html'},
          {'href': 'link3.html'},
        ];

        final links = Link.fromJsonArray(json);

        expect(links, hasLength(3));
        expect(links[0].href, equals('link1.html'));
        expect(links[1].href, equals('link2.html'));
        expect(links[2].href, equals('link3.html'));
      });

      test('filters out invalid links', () {
        final json = [
          {'href': 'valid.html'},
          {'type': 'text/html'}, // Missing href - invalid
          {'href': 'another-valid.html'},
        ];

        final links = Link.fromJsonArray(json);

        expect(links, hasLength(2));
        expect(links[0].href, equals('valid.html'));
        expect(links[1].href, equals('another-valid.html'));
      });

      test('returns empty list for null json', () {
        final links = Link.fromJsonArray(null);
        expect(links, isEmpty);
      });

      test('returns empty list for empty array', () {
        final links = Link.fromJsonArray([]);
        expect(links, isEmpty);
      });
    });

    group('toJson', () {
      test('serializes link to JSON', () {
        final link = Link(
          href: 'chapter1.xhtml',
          type: 'application/xhtml+xml',
          title: 'Chapter 1',
          rels: ['contents'],
          height: 600,
          width: 800,
          bitrate: 128.5,
          duration: 300.0,
          languages: ['en'],
        );

        final json = link.toJson();

        expect(json['href'], equals('chapter1.xhtml'));
        expect(json['type'], equals('application/xhtml+xml'));
        expect(json['title'], equals('Chapter 1'));
        expect(json['rel'], equals(['contents']));
        expect(json['height'], equals(600));
        expect(json['width'], equals(800));
        expect(json['bitrate'], equals(128.5));
        expect(json['duration'], equals(300.0));
        expect(json['language'], equals(['en']));
      });

      test('omits null and empty values from JSON', () {
        final link = Link(href: 'minimal.html');

        final json = link.toJson();

        expect(json.containsKey('href'), isTrue);
        expect(json.containsKey('type'), isFalse);
        expect(json.containsKey('title'), isFalse);
        expect(json.containsKey('rel'), isFalse);
        expect(json.containsKey('language'), isFalse);
      });

      test('serializes templated link', () {
        final link = Link(href: 'https://example.com/{id}', templated: true);

        final json = link.toJson();

        expect(json['templated'], isTrue);
        expect(json['href'], equals('https://example.com/{id}'));
      });

      test('roundtrip serialization preserves data', () {
        final original = Link(
          href: 'chapter.xhtml',
          type: 'text/html',
          title: 'Test Chapter',
          rels: ['contents', 'chapter'],
          languages: ['en', 'fr'],
          height: 1024,
          width: 768,
        );

        final json = original.toJson();
        final restored = Link.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.href, equals(original.href));
        expect(restored.type, equals(original.type));
        expect(restored.title, equals(original.title));
        expect(restored.rels, equals(original.rels));
        expect(restored.languages, equals(original.languages));
        expect(restored.height, equals(original.height));
        expect(restored.width, equals(original.width));
      });
    });

    group('copyWith', () {
      test('creates copy with updated href', () {
        final original = Link(
          href: 'chapter1.html',
          type: 'text/html',
          title: 'Chapter 1',
        );

        final copy = original.copyWith(href: 'chapter2.html');

        expect(copy.href, equals('chapter2.html'));
        expect(copy.type, equals(original.type));
        expect(copy.title, equals(original.title));
      });

      test('creates copy with updated type', () {
        final original = Link(href: 'file.dat');

        final copy = original.copyWith(type: 'application/octet-stream');

        expect(copy.type, equals('application/octet-stream'));
        expect(copy.href, equals(original.href));
      });

      test('creates copy with updated templated flag', () {
        final original = Link(href: 'page.html', templated: false);

        final copy = original.copyWith(templated: true);

        expect(copy.templated, isTrue);
        expect(original.templated, isFalse);
      });

      test('creates copy with updated rels', () {
        final original = Link(href: 'cover.jpg', rels: ['cover']);

        final copy = original.copyWith(rels: ['cover', 'thumbnail']);

        expect(copy.rels, hasLength(2));
        expect(copy.rels, contains('thumbnail'));
        expect(original.rels, hasLength(1));
      });

      test('preserves original when no updates provided', () {
        final original = Link(
          href: 'chapter1.html',
          type: 'text/html',
          title: 'Original Title',
        );

        final copy = original.copyWith();

        expect(copy.href, equals(original.href));
        expect(copy.type, equals(original.type));
        expect(copy.title, equals(original.title));
      });
    });

    group('mediaType', () {
      test('returns parsed media type from type field', () {
        final link = Link(href: 'chapter.xhtml', type: 'application/xhtml+xml');

        expect(link.mediaType.toString(), contains('xhtml'));
      });

      test('returns binary media type when type is null', () {
        final link = Link(href: 'unknown.dat');

        expect(link.mediaType, equals(MediaType.binary));
      });

      test(
        'keeps a syntactically valid type even when it is not a known one',
        () {
          final link = Link(href: 'file.xyz', type: 'invalid/type');

          expect(link.mediaType.toString(), equals('invalid/type'));
        },
      );

      test('falls back to binary when the type cannot be parsed', () {
        final link = Link(href: 'file.xyz', type: 'nonsense');

        expect(link.mediaType, equals(MediaType.binary));
      });
    });

    group('templated links', () {
      test('identifies template parameters', () {
        final link = Link(
          href: 'https://example.com/book/{id}/chapter/{chapter}',
          templated: true,
        );

        final params = link.templateParameters;

        expect(params, contains('id'));
        expect(params, contains('chapter'));
      });

      test('returns empty list for non-templated link', () {
        final link = Link(href: 'regular.html');

        expect(link.templateParameters, isEmpty);
      });

      test('expands template with parameters', () {
        final link = Link(
          href: 'https://example.com/{id}/page/{page}',
          templated: true,
        );

        final expanded = link.expandTemplate({'id': 'book1', 'page': '5'});

        expect(expanded.href, equals('https://example.com/book1/page/5'));
        expect(expanded.templated, isFalse);
      });
    });

    group('href parsing', () {
      test('hrefPart extracts path without fragment', () {
        final link = Link(href: 'chapter1.html#section1');

        expect(link.hrefPart, equals('chapter1.html'));
      });

      test('elementId extracts fragment identifier', () {
        final link = Link(href: 'chapter1.html#section1');

        expect(link.elementId, equals('section1'));
      });

      test('elementId is null when no fragment', () {
        final link = Link(href: 'chapter1.html');

        expect(link.elementId, isNull);
      });

      test('handles multiple hash symbols', () {
        final link = Link(href: 'page.html#section#subsection');

        expect(link.hrefPart, equals('page.html'));
        // Split on '#' means only first fragment is captured
        expect(link.elementId, equals('section'));
      });
    });

    group('toUrl', () {
      test('makes absolute URL with base URL', () {
        final link = Link(href: 'chapter1.html');

        final url = link.toUrl('https://example.com/book/');

        expect(url, contains('example.com'));
        expect(url, contains('chapter1.html'));
      });

      test('preserves absolute href', () {
        final link = Link(href: 'https://external.com/resource.html');

        final url = link.toUrl('https://example.com/');

        expect(url, contains('external.com'));
      });

      test('returns null for blank href', () {
        final link = Link(href: '');

        final url = link.toUrl('https://example.com/');

        expect(url, isNull);
      });

      test(
        'resolves a relative href against the root when base URL is null',
        () {
          final link = Link(href: 'chapter.html');

          final url = link.toUrl(null);

          expect(url, equals('/chapter.html'));
        },
      );
    });

    group('equality', () {
      test('equal links have same hashCode', () {
        final link1 = Link(
          href: 'chapter1.html',
          type: 'text/html',
          title: 'Chapter 1',
        );

        final link2 = Link(
          href: 'chapter1.html',
          type: 'text/html',
          title: 'Chapter 1',
        );

        expect(link1, equals(link2));
        expect(link1.hashCode, equals(link2.hashCode));
      });

      test('different links are not equal', () {
        final link1 = Link(href: 'chapter1.html');
        final link2 = Link(href: 'chapter2.html');

        expect(link1, isNot(equals(link2)));
      });

      test('links with different rels are not equal', () {
        final link1 = Link(href: 'page.html', rels: ['cover']);
        final link2 = Link(href: 'page.html', rels: ['contents']);

        expect(link1, isNot(equals(link2)));
      });
    });

    group('copyWithProperties', () {
      test('merges additional properties', () {
        final original = Link(href: 'page.html', properties: Properties());

        final newProps = Properties(page: PresentationPage.left);

        final copy = original.copyWithProperties(newProps);

        expect(copy.properties.page, equals(PresentationPage.left));
      });
    });

    group('edge cases', () {
      test('handles link with all optional fields null', () {
        final link = Link(href: 'minimal.html');

        expect(link.href, equals('minimal.html'));
        expect(link.type, isNull);
        expect(link.title, isNull);
        expect(link.height, isNull);
        expect(link.width, isNull);
        expect(link.bitrate, isNull);
        expect(link.duration, isNull);
        expect(link.rels, isEmpty);
        expect(link.languages, isEmpty);
        expect(link.alternates, isEmpty);
        expect(link.children, isEmpty);
      });

      test('handles nested children deeply', () {
        final link = Link(
          href: 'parent.html',
          children: [
            Link(
              href: 'child.html',
              children: [Link(href: 'grandchild.html')],
            ),
          ],
        );

        expect(link.children, hasLength(1));
        expect(link.children[0].children, hasLength(1));
        expect(link.children[0].children[0].href, equals('grandchild.html'));
      });

      test('toString includes key properties', () {
        final link = Link(href: 'test.html', type: 'text/html', title: 'Test');

        final str = link.toString();

        expect(str, contains('test.html'));
        expect(str, contains('text/html'));
        expect(str, contains('Test'));
      });
    });
  });
}
