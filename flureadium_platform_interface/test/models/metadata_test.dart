import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('Metadata', () {
    group('fromJson', () {
      test('parses complete metadata', () {
        final json = {
          'title': 'Test Book',
          'identifier': 'urn:isbn:123456789',
          '@type': 'https://schema.org/Book',
          'conformsTo': ['https://readium.org/webpub-manifest/profiles/epub'],
          'subtitle': 'A Subtitle',
          'modified': '2024-01-15T10:30:00Z',
          'published': '2023-06-01T00:00:00Z',
          'language': ['en', 'fr'],
          'author': [
            {'name': 'John Doe'},
          ],
          'publisher': [
            {'name': 'Test Publisher'},
          ],
          'description': 'A test book description',
          'duration': 3600.5,
          'numberOfPages': 300,
          'readingProgression': 'ltr',
        };

        final metadata = Metadata.fromJson(json);

        expect(metadata, isNotNull);
        expect(metadata!.title, equals('Test Book'));
        expect(metadata.identifier, equals('urn:isbn:123456789'));
        expect(metadata.rdfType, equals('https://schema.org/Book'));
        expect(
          metadata.conformsTo,
          contains('https://readium.org/webpub-manifest/profiles/epub'),
        );
        expect(metadata.languages, equals(['en', 'fr']));
        expect(metadata.language, equals('en'));
        expect(metadata.description, equals('A test book description'));
        expect(metadata.duration, equals(3600.5));
        expect(metadata.numberOfPages, equals(300));
        expect(metadata.readingProgression, equals(ReadingProgression.ltr));
      });

      test('returns null for null json', () {
        expect(Metadata.fromJson(null), isNull);
      });

      test('parses metadata with minimal title', () {
        final json = {'title': 'Minimal Book'};

        final metadata = Metadata.fromJson(json);

        expect(metadata, isNotNull);
        expect(metadata!.title, equals('Minimal Book'));
        expect(metadata.identifier, isNull);
        expect(metadata.authors, isEmpty);
      });

      test('falls back to empty title when missing', () {
        final json = <String, dynamic>{};

        final metadata = Metadata.fromJson(json);

        expect(metadata, isNotNull);
        expect(metadata!.title, equals(''));
      });

      test('parses date fields correctly', () {
        final json = {
          'title': 'Test',
          'modified': '2024-01-15T10:30:00Z',
          'published': '2023-06-01',
        };

        final metadata = Metadata.fromJson(json);

        expect(metadata, isNotNull);
        expect(metadata!.modified, isNotNull);
        expect(metadata.modified!.year, equals(2024));
        expect(metadata.modified!.month, equals(1));
        expect(metadata.modified!.day, equals(15));
      });

      test('parses contributor types', () {
        final json = {
          'title': 'Test',
          'author': [
            {'name': 'Author 1'},
          ],
          'translator': [
            {'name': 'Translator 1'},
          ],
          'editor': [
            {'name': 'Editor 1'},
          ],
          'illustrator': [
            {'name': 'Illustrator 1'},
          ],
          'narrator': [
            {'name': 'Narrator 1'},
          ],
          'contributor': [
            {'name': 'Contributor 1'},
          ],
        };

        final metadata = Metadata.fromJson(json);

        expect(metadata, isNotNull);
        expect(metadata!.authors.length, equals(1));
        expect(metadata.translators.length, equals(1));
        expect(metadata.editors.length, equals(1));
        expect(metadata.illustrators.length, equals(1));
        expect(metadata.narrators.length, equals(1));
        expect(metadata.contributors.length, equals(1));
      });

      test('parses single language as array', () {
        final json = {'title': 'Test', 'language': 'en'};

        final metadata = Metadata.fromJson(json);

        expect(metadata, isNotNull);
        expect(metadata!.languages, equals(['en']));
      });
    });

    group('toJson', () {
      test('serializes metadata to JSON', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test Book'),
          identifier: 'test-id',
          languages: ['en'],
          description: 'A description',
          readingProgression: ReadingProgression.ltr,
        );

        final json = metadata.toJson();

        expect(json['title'], equals({'und': 'Test Book'}));
        expect(json['identifier'], equals('test-id'));
        expect(json['language'], equals(['en']));
        expect(json['description'], equals('A description'));
        expect(json['readingProgression'], equals('ltr'));
      });

      test('roundtrip serialization preserves data', () {
        final original = Metadata(
          localizedTitle: LocalizedString.fromString('Roundtrip Test'),
          identifier: 'roundtrip-id',
          languages: ['en', 'de'],
          description: 'Test description',
          numberOfPages: 150,
        );

        final json = original.toJson();
        final restored = Metadata.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.title, equals(original.title));
        expect(restored.identifier, equals(original.identifier));
        expect(restored.description, equals(original.description));
        expect(restored.numberOfPages, equals(original.numberOfPages));
      });
    });

    group('effectiveReadingProgression', () {
      test('returns explicit reading progression', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          readingProgression: ReadingProgression.rtl,
          languages: ['en'],
        );

        expect(
          metadata.effectiveReadingProgression,
          equals(ReadingProgression.rtl),
        );
      });

      test('returns ltr for auto with multiple languages', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          readingProgression: ReadingProgression.auto,
          languages: ['en', 'fr'],
        );

        expect(
          metadata.effectiveReadingProgression,
          equals(ReadingProgression.ltr),
        );
      });

      test('returns rtl for Arabic language', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          readingProgression: ReadingProgression.auto,
          languages: ['ar'],
        );

        expect(
          metadata.effectiveReadingProgression,
          equals(ReadingProgression.rtl),
        );
      });

      test('returns rtl for Hebrew language', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          readingProgression: ReadingProgression.auto,
          languages: ['he'],
        );

        expect(
          metadata.effectiveReadingProgression,
          equals(ReadingProgression.rtl),
        );
      });

      test('returns rtl for Persian language', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          readingProgression: ReadingProgression.auto,
          languages: ['fa'],
        );

        expect(
          metadata.effectiveReadingProgression,
          equals(ReadingProgression.rtl),
        );
      });

      test('returns rtl for Traditional Chinese', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          readingProgression: ReadingProgression.auto,
          languages: ['zh-Hant'],
        );

        expect(
          metadata.effectiveReadingProgression,
          equals(ReadingProgression.rtl),
        );
      });

      test('returns ltr for Simplified Chinese', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          readingProgression: ReadingProgression.auto,
          languages: ['zh-Hans'],
        );

        expect(
          metadata.effectiveReadingProgression,
          equals(ReadingProgression.ltr),
        );
      });
    });

    group('copyWith', () {
      test('creates copy with updated values', () {
        final original = Metadata(
          localizedTitle: LocalizedString.fromString('Original'),
          identifier: 'orig-id',
          languages: ['en'],
        );

        final copy = original.copyWith(
          identifier: 'new-id',
          description: 'New description',
        );

        expect(copy.title, equals('Original'));
        expect(copy.identifier, equals('new-id'));
        expect(copy.description, equals('New description'));
      });

      test('preserves original values when not updated', () {
        final original = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          identifier: 'test-id',
          description: 'Original description',
        );

        final copy = original.copyWith();

        expect(copy.title, equals(original.title));
        expect(copy.identifier, equals(original.identifier));
        expect(copy.description, equals(original.description));
      });
    });

    group('convenience getters', () {
      test('title returns default translation', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromStrings({
            'en': 'English Title',
            'fr': 'French Title',
          }),
        );

        expect(metadata.title, equals('English Title'));
      });

      test('language returns first language', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          languages: ['en', 'fr', 'de'],
        );

        expect(metadata.language, equals('en'));
      });

      test('language returns null for empty languages', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
        );

        expect(metadata.language, isNull);
      });

      test('sortAs returns localized sort value', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('The Test'),
          localizedSortAs: LocalizedString.fromString('Test, The'),
        );

        expect(metadata.sortAs, equals('Test, The'));
      });
    });

    group('edge cases', () {
      test('handles empty authors list', () {
        final metadata = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
        );

        expect(metadata.authors, isEmpty);
        expect(metadata.publishers, isEmpty);
        expect(metadata.contributors, isEmpty);
      });

      test('equality works correctly', () {
        final metadata1 = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          identifier: 'id-1',
        );

        final metadata2 = Metadata(
          localizedTitle: LocalizedString.fromString('Test'),
          identifier: 'id-1',
        );

        expect(metadata1, equals(metadata2));
      });
    });
  });

  group('LocalizedString', () {
    test('fromString creates single-value localized string', () {
      final str = LocalizedString.fromString('Hello');

      expect(str.string, equals('Hello'));
    });

    test('fromStrings creates multi-language string', () {
      final str = LocalizedString.fromStrings({'en': 'Hello', 'fr': 'Bonjour'});

      expect(str.string, equals('Hello'));
      expect(str.translations['fr']?.string, equals('Bonjour'));
    });
  });
}
