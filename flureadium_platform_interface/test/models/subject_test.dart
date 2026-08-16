import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('Subject', () {
    group('constructor', () {
      test('creates subject with required name', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('Fiction'),
        );

        expect(subject.name, equals('Fiction'));
        expect(subject.scheme, isNull);
        expect(subject.code, isNull);
        expect(subject.links, isEmpty);
      });

      test('creates subject with all parameters', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('Science Fiction'),
          localizedSortAs: LocalizedString.fromString('Fiction, Science'),
          scheme: 'BISAC',
          code: 'FIC028000',
          links: [Link(href: 'category.html')],
        );

        expect(subject.name, equals('Science Fiction'));
        expect(subject.sortAs, equals('Fiction, Science'));
        expect(subject.scheme, equals('BISAC'));
        expect(subject.code, equals('FIC028000'));
        expect(subject.links, hasLength(1));
      });
    });

    group('fromString', () {
      test('creates subject from string', () {
        final subject = Subject.fromString('Fantasy');

        expect(subject.name, equals('Fantasy'));
        expect(subject.scheme, isNull);
        expect(subject.code, isNull);
      });
    });

    group('fromJson', () {
      test('parses subject from string', () {
        final subject = Subject.fromJson('Romance');

        expect(subject, isNotNull);
        expect(subject!.name, equals('Romance'));
        expect(subject.scheme, isNull);
        expect(subject.code, isNull);
      });

      test('parses subject from object with name', () {
        final json = {
          'name': 'Mystery',
          'scheme': 'BISAC',
          'code': 'FIC022000',
        };

        final subject = Subject.fromJson(json);

        expect(subject, isNotNull);
        expect(subject!.name, equals('Mystery'));
        expect(subject.scheme, equals('BISAC'));
        expect(subject.code, equals('FIC022000'));
      });

      test('returns null for null json', () {
        expect(Subject.fromJson(null), isNull);
      });

      test('returns null for object without name', () {
        final json = {'scheme': 'BISAC', 'code': 'FIC000000'};

        expect(Subject.fromJson(json), isNull);
      });

      test('returns null for object with empty name', () {
        final json = {'name': ''};

        expect(Subject.fromJson(json), isNull);
      });

      test('parses subject with localized name', () {
        final json = {
          'name': {'en': 'Science', 'fr': 'Science', 'de': 'Wissenschaft'},
        };

        final subject = Subject.fromJson(json);

        expect(subject, isNotNull);
        expect(subject!.name, equals('Science'));
      });

      test('parses subject with sortAs', () {
        final json = {'name': 'The History', 'sortAs': 'History, The'};

        final subject = Subject.fromJson(json);

        expect(subject, isNotNull);
        expect(subject!.name, equals('The History'));
        expect(subject.sortAs, equals('History, The'));
      });

      test('parses subject with links', () {
        final json = {
          'name': 'Biography',
          'links': [
            {'href': 'category/biography.html'},
            {'href': 'subjects/bio.html'},
          ],
        };

        final subject = Subject.fromJson(json);

        expect(subject, isNotNull);
        expect(subject!.links, hasLength(2));
        expect(subject.links[0].href, equals('category/biography.html'));
        expect(subject.links[1].href, equals('subjects/bio.html'));
      });

      test('parses subject with all fields', () {
        final json = {
          'name': 'Technology',
          'sortAs': 'Tech',
          'scheme': 'Dewey',
          'code': '600',
          'links': [
            {'href': 'tech.html'},
          ],
        };

        final subject = Subject.fromJson(json);

        expect(subject, isNotNull);
        expect(subject!.name, equals('Technology'));
        expect(subject.sortAs, equals('Tech'));
        expect(subject.scheme, equals('Dewey'));
        expect(subject.code, equals('600'));
        expect(subject.links, hasLength(1));
      });
    });

    group('fromJsonArray', () {
      test('parses array of subject objects', () {
        final json = [
          {'name': 'Fiction'},
          {'name': 'Science Fiction', 'scheme': 'BISAC'},
          {'name': 'Adventure'},
        ];

        final subjects = Subject.fromJsonArray(json);

        expect(subjects, hasLength(3));
        expect(subjects[0].name, equals('Fiction'));
        expect(subjects[1].name, equals('Science Fiction'));
        expect(subjects[1].scheme, equals('BISAC'));
        expect(subjects[2].name, equals('Adventure'));
      });

      test('parses array of subject strings', () {
        final json = ['Fiction', 'Mystery', 'Thriller'];

        final subjects = Subject.fromJsonArray(json);

        expect(subjects, hasLength(3));
        expect(subjects[0].name, equals('Fiction'));
        expect(subjects[1].name, equals('Mystery'));
        expect(subjects[2].name, equals('Thriller'));
      });

      test('parses mixed array of strings and objects', () {
        final json = [
          'Fiction',
          {'name': 'Mystery', 'code': 'MYS001'},
          'Adventure',
        ];

        final subjects = Subject.fromJsonArray(json);

        expect(subjects, hasLength(3));
        expect(subjects[0].name, equals('Fiction'));
        expect(subjects[1].name, equals('Mystery'));
        expect(subjects[1].code, equals('MYS001'));
        expect(subjects[2].name, equals('Adventure'));
      });

      test('parses single subject string', () {
        final subjects = Subject.fromJsonArray('Single Subject');

        expect(subjects, hasLength(1));
        expect(subjects[0].name, equals('Single Subject'));
      });

      test('parses single subject object', () {
        final json = {'name': 'Solo Subject', 'scheme': 'TEST'};

        final subjects = Subject.fromJsonArray(json);

        expect(subjects, hasLength(1));
        expect(subjects[0].name, equals('Solo Subject'));
        expect(subjects[0].scheme, equals('TEST'));
      });

      test('filters out invalid subjects', () {
        final json = [
          {'name': 'Valid Subject'},
          {'scheme': 'BISAC'}, // Missing name
          {'name': ''}, // Empty name
          {'name': 'Another Valid'},
        ];

        final subjects = Subject.fromJsonArray(json);

        expect(subjects, hasLength(2));
        expect(subjects[0].name, equals('Valid Subject'));
        expect(subjects[1].name, equals('Another Valid'));
      });

      test('returns empty list for null', () {
        final subjects = Subject.fromJsonArray(null);
        expect(subjects, isEmpty);
      });

      test('returns empty list for empty array', () {
        final subjects = Subject.fromJsonArray([]);
        expect(subjects, isEmpty);
      });
    });

    group('toJson', () {
      test('serializes subject to JSON', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('History'),
          localizedSortAs: LocalizedString.fromString('Hist'),
          scheme: 'LC',
          code: 'D',
        );

        final json = subject.toJson();

        expect(json['name'], equals({'und': 'History'}));
        expect(json['sortAs'], equals({'und': 'Hist'}));
        expect(json['scheme'], equals('LC'));
        expect(json['code'], equals('D'));
      });

      test('omits null and empty values from JSON', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('Minimal'),
        );

        final json = subject.toJson();

        expect(json.containsKey('name'), isTrue);
        expect(json.containsKey('sortAs'), isFalse);
        expect(json.containsKey('scheme'), isFalse);
        expect(json.containsKey('code'), isFalse);
        expect(json.containsKey('links'), isFalse);
      });

      test('serializes subject with links', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('Art'),
          links: [
            Link(href: 'art.html'),
            Link(href: 'category/art.html'),
          ],
        );

        final json = subject.toJson();

        expect(json['links'], hasLength(2));
        expect(json['links'][0]['href'], equals('art.html'));
        expect(json['links'][1]['href'], equals('category/art.html'));
      });

      test('roundtrip serialization preserves data', () {
        final original = Subject(
          localizedName: LocalizedString.fromString('Roundtrip Test'),
          localizedSortAs: LocalizedString.fromString('Test, Roundtrip'),
          scheme: 'TEST',
          code: 'RT001',
        );

        final json = original.toJson();
        final restored = Subject.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.name, equals(original.name));
        expect(restored.sortAs, equals(original.sortAs));
        expect(restored.scheme, equals(original.scheme));
        expect(restored.code, equals(original.code));
      });
    });

    group('equality', () {
      test('equal subjects have same hashCode', () {
        final subject1 = Subject(
          localizedName: LocalizedString.fromString('Fiction'),
          scheme: 'BISAC',
          code: 'FIC000000',
        );

        final subject2 = Subject(
          localizedName: LocalizedString.fromString('Fiction'),
          scheme: 'BISAC',
          code: 'FIC000000',
        );

        expect(subject1, equals(subject2));
        expect(subject1.hashCode, equals(subject2.hashCode));
      });

      test('different subjects are not equal', () {
        final subject1 = Subject(
          localizedName: LocalizedString.fromString('Fiction'),
        );

        final subject2 = Subject(
          localizedName: LocalizedString.fromString('Non-Fiction'),
        );

        expect(subject1, isNot(equals(subject2)));
      });

      test('subjects with different codes are not equal', () {
        final subject1 = Subject(
          localizedName: LocalizedString.fromString('Fiction'),
          code: 'FIC001',
        );

        final subject2 = Subject(
          localizedName: LocalizedString.fromString('Fiction'),
          code: 'FIC002',
        );

        expect(subject1, isNot(equals(subject2)));
      });
    });

    group('edge cases', () {
      test('handles subject with all optional fields null', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('Minimal'),
        );

        expect(subject.name, equals('Minimal'));
        expect(subject.sortAs, isNull);
        expect(subject.scheme, isNull);
        expect(subject.code, isNull);
        expect(subject.links, isEmpty);
      });

      test('toString includes subject properties', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('Test Subject'),
          code: 'TEST001',
        );

        final str = subject.toString();

        expect(str, contains('Subject'));
      });

      test('handles localized sortAs', () {
        final subject = Subject(
          localizedName: LocalizedString.fromStrings({
            'en': 'The Art of Programming',
            'fr': 'L\'Art de la Programmation',
          }),
          localizedSortAs: LocalizedString.fromStrings({
            'en': 'Art of Programming, The',
            'fr': 'Art de la Programmation, L\'',
          }),
        );

        expect(subject.name, equals('The Art of Programming'));
        expect(subject.sortAs, equals('Art of Programming, The'));
      });
    });

    group('classification schemes', () {
      test('works with BISAC scheme', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('Literary Fiction'),
          scheme: 'BISAC',
          code: 'FIC019000',
        );

        expect(subject.scheme, equals('BISAC'));
        expect(subject.code, equals('FIC019000'));
      });

      test('works with Dewey Decimal scheme', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('Mathematics'),
          scheme: 'Dewey',
          code: '510',
        );

        expect(subject.scheme, equals('Dewey'));
        expect(subject.code, equals('510'));
      });

      test('works with Library of Congress scheme', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('World History'),
          scheme: 'LC',
          code: 'D',
        );

        expect(subject.scheme, equals('LC'));
        expect(subject.code, equals('D'));
      });

      test('works with custom scheme', () {
        final subject = Subject(
          localizedName: LocalizedString.fromString('Custom Category'),
          scheme: 'MyCustomScheme',
          code: 'CUSTOM-001',
        );

        expect(subject.scheme, equals('MyCustomScheme'));
        expect(subject.code, equals('CUSTOM-001'));
      });
    });
  });
}
