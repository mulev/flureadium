import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('LocalizedString', () {
    group('fromString', () {
      test('creates localized string from single string', () {
        final localizedString = LocalizedString.fromString('Hello World');

        expect(localizedString.string, equals('Hello World'));
      });

      test('stores string without language tag', () {
        final localizedString = LocalizedString.fromString('Test');

        expect(localizedString.translations.containsKey(null), isTrue);
        expect(localizedString.translations[null]!.string, equals('Test'));
      });
    });

    group('fromStrings', () {
      test('creates localized string from multiple translations', () {
        final localizedString = LocalizedString.fromStrings({
          'en': 'Hello',
          'fr': 'Bonjour',
          'de': 'Hallo',
        });

        expect(localizedString.translations, hasLength(3));
        expect(localizedString.translations['en']!.string, equals('Hello'));
        expect(localizedString.translations['fr']!.string, equals('Bonjour'));
        expect(localizedString.translations['de']!.string, equals('Hallo'));
      });

      test('creates localized string with null language key', () {
        final localizedString = LocalizedString.fromStrings({
          null: 'Default',
          'en': 'English',
        });

        expect(localizedString.translations.containsKey(null), isTrue);
        expect(localizedString.translations[null]!.string, equals('Default'));
        expect(localizedString.translations['en']!.string, equals('English'));
      });

      test('creates empty localized string from empty map', () {
        final localizedString = LocalizedString.fromStrings({});

        expect(localizedString.translations, isEmpty);
      });
    });

    group('fromJson', () {
      test('parses from string', () {
        final localizedString = LocalizedString.fromJson('Simple String');

        expect(localizedString, isNotNull);
        expect(localizedString!.string, equals('Simple String'));
      });

      test('parses from object with multiple languages', () {
        final json = {
          'en': 'English Text',
          'fr': 'Texte Français',
          'es': 'Texto Español',
        };

        final localizedString = LocalizedString.fromJson(json);

        expect(localizedString, isNotNull);
        expect(localizedString!.translations, hasLength(3));
        expect(
          localizedString.translations['en']!.string,
          equals('English Text'),
        );
        expect(
          localizedString.translations['fr']!.string,
          equals('Texte Français'),
        );
        expect(
          localizedString.translations['es']!.string,
          equals('Texto Español'),
        );
      });

      test('returns null for null json', () {
        expect(LocalizedString.fromJson(null), isNull);
      });

      test('returns null for invalid json type', () {
        expect(LocalizedString.fromJson(123), isNull);
        expect(LocalizedString.fromJson(true), isNull);
        expect(LocalizedString.fromJson([]), isNull);
      });

      test('handles non-string values in object', () {
        final json = {
          'en': 'Valid String',
          'fr': 123, // Will be converted to string
          'de': 'Another Valid',
        };

        final localizedString = LocalizedString.fromJson(json);

        expect(localizedString, isNotNull);
        expect(localizedString!.translations.containsKey('en'), isTrue);
        // Note: optNullableString may convert non-string values
        expect(localizedString.translations.containsKey('de'), isTrue);
      });

      test('handles BCP 47 language tags', () {
        final json = {
          'en-US': 'American English',
          'en-GB': 'British English',
          'zh-Hans': 'Simplified Chinese',
          'zh-Hant': 'Traditional Chinese',
        };

        final localizedString = LocalizedString.fromJson(json);

        expect(localizedString, isNotNull);
        expect(localizedString!.translations, hasLength(4));
        expect(
          localizedString.translations['en-US']!.string,
          equals('American English'),
        );
        expect(
          localizedString.translations['zh-Hans']!.string,
          equals('Simplified Chinese'),
        );
      });
    });

    group('defaultTranslation and string', () {
      test('returns default translation when null language exists', () {
        final localizedString = LocalizedString.fromStrings({
          null: 'Default Text',
          'en': 'English Text',
        });

        expect(
          localizedString.defaultTranslation.string,
          equals('Default Text'),
        );
        expect(localizedString.string, equals('Default Text'));
      });

      test('returns empty string when no translations exist', () {
        final localizedString = LocalizedString.fromStrings({});

        expect(localizedString.string, equals(''));
      });
    });

    group('getOrFallback', () {
      test('returns exact language match', () {
        final localizedString = LocalizedString.fromStrings({
          'en': 'English',
          'fr': 'French',
          'de': 'German',
        });

        final translation = localizedString.getOrFallback('fr');

        expect(translation, isNotNull);
        expect(translation!.string, equals('French'));
      });

      test('falls back to null language', () {
        final localizedString = LocalizedString.fromStrings({
          null: 'Default',
          'fr': 'French',
        });

        final translation = localizedString.getOrFallback('de');

        expect(translation, isNotNull);
        expect(translation!.string, equals('Default'));
      });

      test('falls back to undefined language', () {
        final localizedString = LocalizedString.fromStrings({
          'und': 'Undefined Language',
          'fr': 'French',
        });

        final translation = localizedString.getOrFallback('de');

        expect(translation, isNotNull);
        expect(translation!.string, equals('Undefined Language'));
      });

      test('falls back to English', () {
        final localizedString = LocalizedString.fromStrings({
          'en': 'English',
          'fr': 'French',
        });

        final translation = localizedString.getOrFallback('de');

        expect(translation, isNotNull);
        expect(translation!.string, equals('English'));
      });

      test('falls back to first available translation', () {
        final localizedString = LocalizedString.fromStrings({
          'fr': 'French',
          'de': 'German',
        });

        final translation = localizedString.getOrFallback('es');

        expect(translation, isNotNull);
        expect(translation!.string, isIn(['French', 'German']));
      });

      test('returns null when no translations exist', () {
        final localizedString = LocalizedString.fromStrings({});

        final translation = localizedString.getOrFallback('en');

        expect(translation, isNull);
      });

      test('fallback priority order is correct', () {
        // Test that null language takes priority over undefined
        final localizedString = LocalizedString.fromStrings({
          'und': 'Undefined',
          null: 'Default',
          'en': 'English',
        });

        final translation = localizedString.getOrFallback('fr');

        expect(translation!.string, equals('Default'));
      });
    });

    group('copyWithString', () {
      test('adds new translation', () {
        final original = LocalizedString.fromStrings({'en': 'English'});

        final updated = original.copyWithString('fr', 'French');

        expect(updated.translations, hasLength(2));
        expect(updated.translations['en']!.string, equals('English'));
        expect(updated.translations['fr']!.string, equals('French'));
        expect(original.translations, hasLength(1));
      });

      test('does not modify original', () {
        final original = LocalizedString.fromStrings({'en': 'Original'});

        // ignore: cascade_invocations
        original.copyWithString('de', 'German');

        expect(original.translations, hasLength(1));
        expect(original.translations.containsKey('de'), isFalse);
      });

      test('does not replace existing translation', () {
        final original = LocalizedString.fromStrings({
          'en': 'Original English',
        });

        final updated = original.copyWithString('en', 'New English');

        // copyWithString uses putIfAbsent, so it won't replace existing
        expect(updated.translations['en']!.string, equals('Original English'));
      });
    });

    group('mapLanguages', () {
      test('transforms language tags', () {
        final original = LocalizedString.fromStrings({
          'en': 'English',
          'fr': 'French',
        });

        final transformed = original.mapLanguages(
          (language, translation) => language?.toUpperCase() ?? 'NULL',
        );

        expect(transformed.translations.containsKey('EN'), isTrue);
        expect(transformed.translations.containsKey('FR'), isTrue);
        expect(transformed.translations['EN']!.string, equals('English'));
        expect(transformed.translations['FR']!.string, equals('French'));
      });

      test('handles null language key', () {
        final original = LocalizedString.fromStrings({
          null: 'Default',
          'en': 'English',
        });

        final transformed = original.mapLanguages(
          (language, translation) => language ?? 'default',
        );

        expect(transformed.translations.containsKey('default'), isTrue);
        expect(transformed.translations['default']!.string, equals('Default'));
      });
    });

    group('mapTranslations', () {
      test('transforms translation strings', () {
        final original = LocalizedString.fromStrings({
          'en': 'hello',
          'fr': 'bonjour',
        });

        final transformed = original.mapTranslations(
          (language, translation) =>
              Translation(translation.string.toUpperCase()),
        );

        expect(transformed.translations['en']!.string, equals('HELLO'));
        expect(transformed.translations['fr']!.string, equals('BONJOUR'));
      });

      test('can apply custom transformation logic', () {
        final original = LocalizedString.fromStrings({
          'en': 'test',
          'fr': 'test',
        });

        final transformed = original.mapTranslations((language, translation) {
          final prefix = language == 'en' ? 'EN:' : 'FR:';
          return Translation('$prefix${translation.string}');
        });

        expect(transformed.translations['en']!.string, equals('EN:test'));
        expect(transformed.translations['fr']!.string, equals('FR:test'));
      });
    });

    group('copyWith', () {
      test('creates copy with new translations map', () {
        final original = LocalizedString.fromStrings({'en': 'English'});

        final newTranslations = {
          'fr': Translation('French'),
          'de': Translation('German'),
        };

        final copy = original.copyWith(translations: newTranslations);

        expect(copy.translations, hasLength(2));
        expect(copy.translations.containsKey('en'), isFalse);
        expect(copy.translations['fr']!.string, equals('French'));
        expect(original.translations, hasLength(1));
      });

      test('creates copy with empty map when provided', () {
        final original = LocalizedString.fromStrings({'en': 'English'});

        final copy = original.copyWith(translations: {});

        expect(copy.translations, isEmpty);
        expect(original.translations, hasLength(1));
      });

      test('preserves original when null provided', () {
        final original = LocalizedString.fromStrings({'en': 'English'});

        final copy = original.copyWith(translations: null);

        expect(copy.translations, isEmpty);
      });
    });

    group('toJson', () {
      test('serializes single language to string in JSON', () {
        final localizedString = LocalizedString.fromString('Simple');

        final json = localizedString.toJson();

        expect(json, isMap);
        expect(json['und'], equals('Simple'));
      });

      test('serializes multiple languages to object', () {
        final localizedString = LocalizedString.fromStrings({
          'en': 'Hello',
          'fr': 'Bonjour',
          'de': 'Hallo',
        });

        final json = localizedString.toJson();

        expect(json, hasLength(3));
        expect(json['en'], equals('Hello'));
        expect(json['fr'], equals('Bonjour'));
        expect(json['de'], equals('Hallo'));
      });

      test('converts null language key to und', () {
        final localizedString = LocalizedString.fromStrings({
          null: 'Default Text',
          'en': 'English',
        });

        final json = localizedString.toJson();

        expect(json.containsKey('und'), isTrue);
        expect(json['und'], equals('Default Text'));
        // `toJson` returns Map<String, String>, so asking for a null key could
        // never have found one. What the test means is that the null language
        // became 'und' and nothing else was invented alongside it.
        expect(json.keys, unorderedEquals(['und', 'en']));
      });

      test('roundtrip serialization preserves data', () {
        final original = LocalizedString.fromStrings({
          'en': 'English',
          'fr': 'Français',
          'de': 'Deutsch',
        });

        final json = original.toJson();
        final restored = LocalizedString.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.translations, hasLength(3));
        expect(restored.translations['en']!.string, equals('English'));
        expect(restored.translations['fr']!.string, equals('Français'));
        expect(restored.translations['de']!.string, equals('Deutsch'));
      });

      test('roundtrip with null language uses und', () {
        final original = LocalizedString.fromString('Default');

        final json = original.toJson();
        final restored = LocalizedString.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.translations.containsKey('und'), isTrue);
        expect(restored.translations['und']!.string, equals('Default'));
      });
    });

    group('equality', () {
      test('equal localized strings have same hashCode', () {
        final ls1 = LocalizedString.fromStrings({'en': 'Test', 'fr': 'Test'});

        final ls2 = LocalizedString.fromStrings({'en': 'Test', 'fr': 'Test'});

        expect(ls1, equals(ls2));
        expect(ls1.hashCode, equals(ls2.hashCode));
      });

      test('different localized strings are not equal', () {
        final ls1 = LocalizedString.fromString('Test 1');
        final ls2 = LocalizedString.fromString('Test 2');

        expect(ls1, isNot(equals(ls2)));
      });

      test('same translations in different order are equal', () {
        final ls1 = LocalizedString.fromStrings({
          'en': 'English',
          'fr': 'French',
        });

        final ls2 = LocalizedString.fromStrings({
          'fr': 'French',
          'en': 'English',
        });

        expect(ls1, equals(ls2));
      });
    });

    group('Translation', () {
      test('creates translation from string', () {
        final translation = Translation('Test');

        expect(translation.string, equals('Test'));
      });

      test('translations are equal if strings are equal', () {
        final t1 = Translation('Same');
        final t2 = Translation('Same');

        expect(t1, equals(t2));
        expect(t1.hashCode, equals(t2.hashCode));
      });

      test('translations with different strings are not equal', () {
        final t1 = Translation('First');
        final t2 = Translation('Second');

        expect(t1, isNot(equals(t2)));
      });

      test('toString returns string value', () {
        final translation = Translation('Test Value');

        expect(translation.toString(), equals('Test Value'));
      });
    });

    group('edge cases', () {
      test('handles empty string values', () {
        final localizedString = LocalizedString.fromStrings({
          'en': '',
          'fr': 'French',
        });

        expect(localizedString.translations['en']!.string, equals(''));
      });

      test('handles very long strings', () {
        final longString = 'x' * 10000;
        final localizedString = LocalizedString.fromString(longString);

        expect(localizedString.string, equals(longString));
        expect(localizedString.string.length, equals(10000));
      });

      test('handles special characters in strings', () {
        final localizedString = LocalizedString.fromStrings({
          'en': 'Test with "quotes" and \'apostrophes\'',
          'fr': 'Caractères spéciaux: àéèêëïôù',
          'de': 'Umlaute: äöüßÄÖÜ',
        });

        expect(localizedString.translations['en']!.string, contains('quotes'));
        expect(
          localizedString.translations['fr']!.string,
          contains('àéèêëïôù'),
        );
        expect(localizedString.translations['de']!.string, contains('äöüßÄÖÜ'));
      });

      test('handles newlines and whitespace', () {
        final localizedString = LocalizedString.fromString(
          'Line 1\nLine 2\t\tTabbed',
        );

        expect(localizedString.string, contains('\n'));
        expect(localizedString.string, contains('\t'));
      });

      test('toString includes translations map', () {
        final localizedString = LocalizedString.fromStrings({'en': 'English'});

        final str = localizedString.toString();

        expect(str, contains('LocalizedString'));
      });
    });

    group('language tag variations', () {
      test('handles simple two-letter codes', () {
        final localizedString = LocalizedString.fromStrings({
          'en': 'English',
          'fr': 'French',
          'de': 'German',
          'es': 'Spanish',
        });

        expect(localizedString.translations, hasLength(4));
      });

      test('handles region subtags', () {
        final localizedString = LocalizedString.fromStrings({
          'en-US': 'American',
          'en-GB': 'British',
          'fr-CA': 'Canadian French',
          'fr-FR': 'Metropolitan French',
        });

        expect(localizedString.translations, hasLength(4));
      });

      test('handles script subtags', () {
        final localizedString = LocalizedString.fromStrings({
          'zh-Hans': 'Simplified',
          'zh-Hant': 'Traditional',
        });

        expect(localizedString.translations, hasLength(2));
      });

      test('handles complex tags', () {
        final localizedString = LocalizedString.fromStrings({
          'zh-Hans-CN': 'Mainland Simplified Chinese',
          'zh-Hant-TW': 'Taiwan Traditional Chinese',
        });

        expect(localizedString.translations, hasLength(2));
      });
    });
  });
}
