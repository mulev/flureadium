import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('Locator', () {
    group('fromJson', () {
      test('parses complete locator', () {
        final json = {
          'href': 'chapter1.xhtml',
          'type': 'application/xhtml+xml',
          'title': 'Chapter 1',
          'locations': {
            'position': 1,
            'progression': 0.5,
            'totalProgression': 0.25,
            'fragments': ['section1'],
            'cssSelector': '#paragraph1',
          },
          'text': {
            'before': 'Text before',
            'highlight': 'Highlighted text',
            'after': 'Text after',
          },
        };

        final locator = Locator.fromJson(json);

        expect(locator, isNotNull);
        expect(locator!.href, equals('chapter1.xhtml'));
        expect(locator.type, equals('application/xhtml+xml'));
        expect(locator.title, equals('Chapter 1'));
        expect(locator.locations?.position, equals(1));
        expect(locator.locations?.progression, equals(0.5));
        expect(locator.locations?.totalProgression, equals(0.25));
        expect(locator.locations?.fragments, contains('section1'));
        expect(locator.locations?.cssSelector, equals('#paragraph1'));
        expect(locator.text?.before, equals('Text before'));
        expect(locator.text?.highlight, equals('Highlighted text'));
        expect(locator.text?.after, equals('Text after'));
      });

      test('returns null for null json', () {
        expect(Locator.fromJson(null), isNull);
      });

      test('returns null for json without href', () {
        final json = {'type': 'application/xhtml+xml'};

        expect(Locator.fromJson(json), isNull);
      });

      test('returns null for json without type', () {
        final json = {'href': 'chapter1.xhtml'};

        expect(Locator.fromJson(json), isNull);
      });

      test('parses locator with minimal required fields', () {
        final json = {
          'href': 'chapter1.xhtml',
          'type': 'application/xhtml+xml',
        };

        final locator = Locator.fromJson(json);

        expect(locator, isNotNull);
        expect(locator!.href, equals('chapter1.xhtml'));
        expect(locator.type, equals('application/xhtml+xml'));
        expect(locator.title, isNull);
        // locations and text may be null or empty defaults
      });
    });

    group('fromJsonString', () {
      test('parses locator from JSON string', () {
        final jsonString = json.encode({
          'href': 'chapter1.xhtml',
          'type': 'text/html',
          'title': 'Test Chapter',
        });

        final locator = Locator.fromJsonString(jsonString);

        expect(locator, isNotNull);
        expect(locator!.href, equals('chapter1.xhtml'));
        expect(locator.title, equals('Test Chapter'));
      });

      test('returns null for invalid JSON string', () {
        expect(Locator.fromJsonString('invalid json'), isNull);
      });
    });

    group('toJson', () {
      test('serializes locator to JSON', () {
        final locator = Locator(
          href: 'chapter1.xhtml',
          type: 'application/xhtml+xml',
          title: 'Chapter 1',
          locations: Locations(
            position: 1,
            progression: 0.5,
            totalProgression: 0.25,
          ),
          text: LocatorText(
            before: 'Before',
            highlight: 'Highlight',
            after: 'After',
          ),
        );

        final json = locator.toJson();

        expect(json['href'], equals('chapter1.xhtml'));
        expect(json['type'], equals('application/xhtml+xml'));
        expect(json['title'], equals('Chapter 1'));
        expect(json['locations']['position'], equals(1));
        expect(json['locations']['progression'], equals(0.5));
        expect(json['text']['highlight'], equals('Highlight'));
      });

      test('roundtrip serialization preserves data', () {
        final original = Locator(
          href: 'chapter2.xhtml',
          type: 'text/html',
          title: 'Chapter 2',
          locations: Locations(
            position: 5,
            progression: 0.75,
            fragments: ['section1', 'paragraph2'],
          ),
          text: LocatorText(highlight: 'Important text'),
        );

        final json = original.toJson();
        final restored = Locator.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.href, equals(original.href));
        expect(restored.type, equals(original.type));
        expect(restored.title, equals(original.title));
        expect(
          restored.locations?.position,
          equals(original.locations?.position),
        );
        expect(
          restored.locations?.progression,
          equals(original.locations?.progression),
        );
        expect(restored.text?.highlight, equals(original.text?.highlight));
      });

      test('json property returns JSON string', () {
        final locator = Locator(href: 'test.xhtml', type: 'text/html');

        final jsonString = locator.json;
        final decoded = json.decode(jsonString) as Map<String, dynamic>;

        expect(decoded['href'], equals('test.xhtml'));
        expect(decoded['type'], equals('text/html'));
      });
    });

    group('copyWith', () {
      test('creates copy with updated href', () {
        final original = Locator(
          href: 'chapter1.xhtml',
          type: 'text/html',
          title: 'Chapter 1',
        );

        final copy = original.copyWith(href: 'chapter2.xhtml');

        expect(copy.href, equals('chapter2.xhtml'));
        expect(copy.type, equals(original.type));
        expect(copy.title, equals(original.title));
      });

      test('creates copy with updated locations', () {
        final original = Locator(
          href: 'chapter1.xhtml',
          type: 'text/html',
          locations: Locations(position: 1),
        );

        final copy = original.copyWith(
          locations: Locations(position: 5, progression: 0.5),
        );

        expect(copy.locations?.position, equals(5));
        expect(copy.locations?.progression, equals(0.5));
      });

      test('creates copy with updated text', () {
        final original = Locator(href: 'chapter1.xhtml', type: 'text/html');

        final copy = original.copyWith(
          text: LocatorText(highlight: 'New highlight'),
        );

        expect(copy.text?.highlight, equals('New highlight'));
      });

      test('preserves original when no updates provided', () {
        final original = Locator(
          href: 'chapter1.xhtml',
          type: 'text/html',
          title: 'Original Title',
        );

        final copy = original.copyWith();

        expect(copy.href, equals(original.href));
        expect(copy.type, equals(original.type));
        expect(copy.title, equals(original.title));
      });
    });

    group('copyWithLocations', () {
      test('creates copy with updated progression', () {
        final original = Locator(
          href: 'chapter1.xhtml',
          type: 'text/html',
          locations: Locations(position: 1, progression: 0.25),
        );

        final copy = original.copyWithLocations(progression: 0.75);

        expect(copy.locations?.progression, equals(0.75));
        expect(copy.locations?.position, equals(1));
      });

      test('creates copy with updated position', () {
        final original = Locator(
          href: 'chapter1.xhtml',
          type: 'text/html',
          locations: Locations(position: 1),
        );

        final copy = original.copyWithLocations(position: 10);

        expect(copy.locations?.position, equals(10));
      });

      test('creates copy with updated fragments', () {
        final original = Locator(href: 'chapter1.xhtml', type: 'text/html');

        final copy = original.copyWithLocations(
          fragments: ['section1', 'para1'],
        );

        expect(copy.locations?.fragments, contains('section1'));
        expect(copy.locations?.fragments, contains('para1'));
      });
    });

    group('hrefPath', () {
      test('returns href path without fragment', () {
        final locator = Locator(
          href: 'chapter1.xhtml#section1',
          type: 'text/html',
        );

        // hrefPath extracts the path component from the href
        expect(locator.hrefPath, contains('chapter1.xhtml'));
        expect(locator.hrefPath.contains('#'), isFalse);
      });

      test('returns href path without query params', () {
        final locator = Locator(
          href: 'chapter1.xhtml?page=1',
          type: 'text/html',
        );

        expect(locator.hrefPath, contains('chapter1.xhtml'));
        expect(locator.hrefPath.contains('?'), isFalse);
      });

      test('returns path for simple href', () {
        final locator = Locator(href: 'chapter1.xhtml', type: 'text/html');

        expect(locator.hrefPath, contains('chapter1.xhtml'));
      });
    });

    group('href encoding', () {
      test('fromJson decodes percent-encoded href', () {
        final json = {
          'href': 'Happiness%20v01%20%5BHD%5D.jpg',
          'type': 'image/jpeg',
        };

        final locator = Locator.fromJson(json);

        expect(locator, isNotNull);
        expect(locator!.href, equals('Happiness v01 [HD].jpg'));
      });

      test('fromJson decodes href with spaces only', () {
        final json = {'href': 'my%20chapter.xhtml', 'type': 'text/html'};

        final locator = Locator.fromJson(json);

        expect(locator, isNotNull);
        expect(locator!.href, equals('my chapter.xhtml'));
      });

      test('fromJson preserves already-decoded href', () {
        final json = {'href': 'chapter1.xhtml', 'type': 'text/html'};

        final locator = Locator.fromJson(json);

        expect(locator, isNotNull);
        expect(locator!.href, equals('chapter1.xhtml'));
      });

      test('toJson encodes decoded href with special characters', () {
        final locator = Locator(
          href: '/Happiness - c001 [HD].jpg',
          type: 'image/jpeg',
        );

        final json = locator.toJson();

        expect(json['href'], equals('/Happiness%20-%20c001%20%5BHD%5D.jpg'));
      });

      test('toJson encodes brackets in href', () {
        final locator = Locator(href: 'page[1].jpg', type: 'image/jpeg');

        final json = locator.toJson();

        expect(json['href'], equals('page%5B1%5D.jpg'));
      });

      test('toJson preserves simple href unchanged', () {
        final locator = Locator(href: 'chapter1.xhtml', type: 'text/html');

        final json = locator.toJson();

        expect(json['href'], equals('chapter1.xhtml'));
      });

      test(
        'roundtrip: encoded JSON → fromJson → toJson → same encoded JSON',
        () {
          final originalJson = {
            'href': 'file%20name%20%5Btag%5D.jpg',
            'type': 'image/jpeg',
          };

          final locator = Locator.fromJson(originalJson);
          final reserialized = locator!.toJson();

          expect(reserialized['href'], equals('file%20name%20%5Btag%5D.jpg'));
        },
      );

      test(
        'roundtrip: decoded constructor → toJson → fromJson → same decoded internal',
        () {
          final original = Locator(
            href: 'file name [tag].jpg',
            type: 'image/jpeg',
          );

          final json = original.toJson();
          final restored = Locator.fromJson(json);

          expect(restored, isNotNull);
          expect(restored!.href, equals('file name [tag].jpg'));
        },
      );
    });

    group('equality', () {
      test('equal locators have same hashCode', () {
        final locator1 = Locator(
          href: 'chapter1.xhtml',
          type: 'text/html',
          title: 'Chapter 1',
        );

        final locator2 = Locator(
          href: 'chapter1.xhtml',
          type: 'text/html',
          title: 'Chapter 1',
        );

        expect(locator1, equals(locator2));
        expect(locator1.hashCode, equals(locator2.hashCode));
      });

      test('different locators are not equal', () {
        final locator1 = Locator(href: 'chapter1.xhtml', type: 'text/html');

        final locator2 = Locator(href: 'chapter2.xhtml', type: 'text/html');

        expect(locator1, isNot(equals(locator2)));
      });
    });
  });

  group('Locations', () {
    group('fromJson', () {
      test('parses complete locations', () {
        final json = {
          'position': 5,
          'progression': 0.5,
          'totalProgression': 0.25,
          'fragments': ['section1', 'para2'],
          'cssSelector': '#element',
          'partialCfi': '/4/2/4',
        };

        final locations = Locations.fromJson(json);

        expect(locations.position, equals(5));
        expect(locations.progression, equals(0.5));
        expect(locations.totalProgression, equals(0.25));
        expect(locations.fragments, equals(['section1', 'para2']));
        expect(locations.cssSelector, equals('#element'));
        expect(locations.partialCfi, equals('/4/2/4'));
      });

      test('returns empty locations for null json', () {
        final locations = Locations.fromJson(null);

        expect(locations.position, isNull);
        expect(locations.progression, isNull);
        expect(locations.fragments, isEmpty);
      });

      test('validates progression range 0-1', () {
        final validJson = {'progression': 0.5};
        final invalidJson = {'progression': 1.5};

        expect(Locations.fromJson(validJson).progression, equals(0.5));
        expect(Locations.fromJson(invalidJson).progression, isNull);
      });

      test('validates position is positive', () {
        final validJson = {'position': 1};
        final invalidJson = {'position': 0};

        expect(Locations.fromJson(validJson).position, equals(1));
        expect(Locations.fromJson(invalidJson).position, isNull);
      });

      test('parses single fragment as array', () {
        final json = {'fragment': 'section1'};

        final locations = Locations.fromJson(json);

        expect(locations.fragments, equals(['section1']));
      });
    });

    group('toJson', () {
      test('serializes locations to JSON', () {
        final locations = Locations(
          position: 3,
          progression: 0.6,
          totalProgression: 0.3,
          fragments: ['frag1'],
          cssSelector: '#test',
        );

        final json = locations.toJson();

        expect(json['position'], equals(3));
        expect(json['progression'], equals(0.6));
        expect(json['totalProgression'], equals(0.3));
        expect(json['fragments'], equals(['frag1']));
        expect(json['cssSelector'], equals('#test'));
      });

      test('omits null values from JSON', () {
        final locations = Locations(position: 1);

        final json = locations.toJson();

        expect(json.containsKey('position'), isTrue);
        expect(json.containsKey('progression'), isFalse);
        expect(json.containsKey('totalProgression'), isFalse);
      });
    });

    group('copyWith', () {
      test('creates copy with updated values', () {
        final original = Locations(position: 1, progression: 0.5);

        final copy = original.copyWith(position: 10);

        expect(copy.position, equals(10));
        expect(copy.progression, equals(0.5));
      });
    });

    group('timestamp', () {
      test('extracts timestamp from fragments', () {
        final locations = Locations(fragments: ['t=300']);

        expect(locations.timestamp, equals(300));
      });

      test('returns 0 when no time fragment', () {
        final locations = Locations(fragments: ['section1']);

        expect(locations.timestamp, equals(0));
      });

      test('returns 0 for empty fragments', () {
        final locations = Locations();

        expect(locations.timestamp, equals(0));
      });
    });
  });

  group('LocatorText', () {
    group('fromJson', () {
      test('parses complete text', () {
        final json = {
          'before': 'Text before',
          'highlight': 'Highlighted text',
          'after': 'Text after',
        };

        final text = LocatorText.fromJson(json);

        expect(text.before, equals('Text before'));
        expect(text.highlight, equals('Highlighted text'));
        expect(text.after, equals('Text after'));
      });

      test('returns empty text for null json', () {
        final text = LocatorText.fromJson(null);

        expect(text.before, isNull);
        expect(text.highlight, isNull);
        expect(text.after, isNull);
      });

      test('parses partial text', () {
        final json = {'highlight': 'Only highlight'};

        final text = LocatorText.fromJson(json);

        expect(text.highlight, equals('Only highlight'));
        expect(text.before, isNull);
        expect(text.after, isNull);
      });
    });

    group('toJson', () {
      test('serializes text to JSON', () {
        final text = LocatorText(
          before: 'Before',
          highlight: 'Highlight',
          after: 'After',
        );

        final json = text.toJson();

        expect(json['before'], equals('Before'));
        expect(json['highlight'], equals('Highlight'));
        expect(json['after'], equals('After'));
      });

      test('omits null values from JSON', () {
        final text = LocatorText(highlight: 'Only highlight');

        final json = text.toJson();

        expect(json.containsKey('highlight'), isTrue);
        expect(json.containsKey('before'), isFalse);
        expect(json.containsKey('after'), isFalse);
      });
    });

    group('equality', () {
      test('equal text objects are equal', () {
        final text1 = LocatorText(highlight: 'Same');
        final text2 = LocatorText(highlight: 'Same');

        expect(text1, equals(text2));
      });
    });
  });
}
