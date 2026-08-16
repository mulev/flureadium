import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('Collection', () {
    group('constructor', () {
      test('creates instance with required name', () {
        final collection = Collection(
          localizedName: LocalizedString.fromString('Test Collection'),
        );

        expect(collection.name, equals('Test Collection'));
        expect(collection.identifier, isNull);
        expect(collection.roles, isEmpty);
        expect(collection.links, isEmpty);
      });

      test('creates instance with all parameters', () {
        final collection = Collection(
          localizedName: LocalizedString.fromString('My Series'),
          identifier: 'series-123',
          localizedSortAs: LocalizedString.fromString('Series, My'),
          roles: ['collection'],
          position: 3.0,
          links: [Link(href: 'series.html')],
        );

        expect(collection.name, equals('My Series'));
        expect(collection.identifier, equals('series-123'));
        expect(collection.sortAs, equals('Series, My'));
        expect(collection.roles, equals(['collection']));
        expect(collection.position, equals(3.0));
        expect(collection.links, hasLength(1));
      });
    });

    group('fromJson', () {
      test('parses collection from string', () {
        final collection = Collection.fromJson('Simple Name');

        expect(collection, isNotNull);
        expect(collection!.name, equals('Simple Name'));
        expect(collection.identifier, isNull);
      });

      test('parses collection from object with name', () {
        final json = {
          'name': 'Collection Name',
          'identifier': 'id-123',
          'role': ['series'],
          'position': 5.0,
        };

        final collection = Collection.fromJson(json);

        expect(collection, isNotNull);
        expect(collection!.name, equals('Collection Name'));
        expect(collection.identifier, equals('id-123'));
        expect(collection.roles, equals(['series']));
        expect(collection.position, equals(5.0));
      });

      test('returns null for null json', () {
        expect(Collection.fromJson(null), isNull);
      });

      test('returns null for object without name', () {
        final json = {'identifier': 'id-only'};

        expect(Collection.fromJson(json), isNull);
      });

      test('returns null for object with empty name', () {
        final json = {'name': ''};

        expect(Collection.fromJson(json), isNull);
      });

      test('parses collection with localized name', () {
        final json = {
          'name': {'en': 'English Name', 'fr': 'Nom Français'},
        };

        final collection = Collection.fromJson(json);

        expect(collection, isNotNull);
        expect(collection!.name, equals('English Name'));
      });

      test('parses collection with single role string', () {
        final json = {'name': 'Test', 'role': 'series'};

        final collection = Collection.fromJson(json);

        expect(collection, isNotNull);
        expect(collection!.roles, equals(['series']));
      });

      test('parses collection with multiple roles', () {
        final json = {
          'name': 'Test',
          'role': ['series', 'collection'],
        };

        final collection = Collection.fromJson(json);

        expect(collection, isNotNull);
        expect(collection!.roles, hasLength(2));
        expect(collection.roles, contains('series'));
        expect(collection.roles, contains('collection'));
      });

      test('parses collection with links', () {
        final json = {
          'name': 'Test Collection',
          'links': [
            {'href': 'collection.html'},
            {'href': 'index.html'},
          ],
        };

        final collection = Collection.fromJson(json);

        expect(collection, isNotNull);
        expect(collection!.links, hasLength(2));
        expect(collection.links[0].href, equals('collection.html'));
      });
    });

    group('fromJsonArray', () {
      test('parses array of collection objects', () {
        final json = [
          {'name': 'Collection 1'},
          {'name': 'Collection 2'},
          {'name': 'Collection 3'},
        ];

        final collections = Collection.fromJsonArray(json);

        expect(collections, hasLength(3));
        expect(collections[0].name, equals('Collection 1'));
        expect(collections[1].name, equals('Collection 2'));
        expect(collections[2].name, equals('Collection 3'));
      });

      test('parses array of collection strings', () {
        final json = ['Name 1', 'Name 2'];

        final collections = Collection.fromJsonArray(json);

        expect(collections, hasLength(2));
        expect(collections[0].name, equals('Name 1'));
        expect(collections[1].name, equals('Name 2'));
      });

      test('parses single collection string', () {
        final collections = Collection.fromJsonArray('Single Collection');

        expect(collections, hasLength(1));
        expect(collections[0].name, equals('Single Collection'));
      });

      test('parses single collection object', () {
        final json = {'name': 'Single Object'};

        final collections = Collection.fromJsonArray(json);

        expect(collections, hasLength(1));
        expect(collections[0].name, equals('Single Object'));
      });

      test('filters out invalid collections', () {
        final json = [
          {'name': 'Valid'},
          {'identifier': 'no-name'},
          {'name': ''},
          {'name': 'Also Valid'},
        ];

        final collections = Collection.fromJsonArray(json);

        expect(collections, hasLength(2));
        expect(collections[0].name, equals('Valid'));
        expect(collections[1].name, equals('Also Valid'));
      });

      test('returns empty list for null', () {
        final collections = Collection.fromJsonArray(null);
        expect(collections, isEmpty);
      });
    });

    group('toJson', () {
      test('serializes collection to JSON', () {
        final collection = Collection(
          localizedName: LocalizedString.fromString('Test Collection'),
          identifier: 'col-123',
          localizedSortAs: LocalizedString.fromString('Collection, Test'),
          roles: ['series'],
          position: 2.5,
        );

        final json = collection.toJson();

        expect(json['name'], equals({'und': 'Test Collection'}));
        expect(json['identifier'], equals('col-123'));
        expect(json['sortAs'], equals({'und': 'Collection, Test'}));
        expect(json['role'], equals(['series']));
        expect(json['position'], equals(2.5));
      });

      test('omits null and empty values from JSON', () {
        final collection = Collection(
          localizedName: LocalizedString.fromString('Minimal'),
        );

        final json = collection.toJson();

        expect(json.containsKey('name'), isTrue);
        expect(json.containsKey('identifier'), isFalse);
        expect(json.containsKey('role'), isFalse);
        expect(json.containsKey('position'), isFalse);
        expect(json.containsKey('links'), isFalse);
      });

      test('roundtrip serialization preserves data', () {
        final original = Collection(
          localizedName: LocalizedString.fromString('Roundtrip Test'),
          identifier: 'rt-123',
          roles: ['series', 'collection'],
          position: 7.0,
        );

        final json = original.toJson();
        final restored = Collection.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.name, equals(original.name));
        expect(restored.identifier, equals(original.identifier));
        expect(restored.roles, equals(original.roles));
        expect(restored.position, equals(original.position));
      });
    });

    group('copyWith', () {
      test('creates copy with updated name', () {
        final original = Collection(
          localizedName: LocalizedString.fromString('Original'),
        );

        final copy = original.copyWith(
          localizedName: LocalizedString.fromString('Updated'),
        );

        expect(copy.name, equals('Updated'));
        expect(original.name, equals('Original'));
      });

      test('creates copy with updated identifier', () {
        final original = Collection(
          localizedName: LocalizedString.fromString('Test'),
          identifier: 'old-id',
        );

        final copy = original.copyWith(identifier: 'new-id');

        expect(copy.identifier, equals('new-id'));
        expect(original.identifier, equals('old-id'));
      });

      test('creates copy with updated roles', () {
        final original = Collection(
          localizedName: LocalizedString.fromString('Test'),
          roles: ['series'],
        );

        final copy = original.copyWith(roles: ['collection', 'set']);

        expect(copy.roles, hasLength(2));
        expect(original.roles, hasLength(1));
      });

      test('preserves original when no updates provided', () {
        final original = Collection(
          localizedName: LocalizedString.fromString('Test'),
          identifier: 'id-123',
          roles: ['series'],
        );

        final copy = original.copyWith();

        expect(copy.name, equals(original.name));
        expect(copy.identifier, equals(original.identifier));
        expect(copy.roles, equals(original.roles));
      });
    });

    group('equality', () {
      test('equal collections have same hashCode', () {
        final collection1 = Collection(
          localizedName: LocalizedString.fromString('Test'),
          identifier: 'id-1',
        );

        final collection2 = Collection(
          localizedName: LocalizedString.fromString('Test'),
          identifier: 'id-1',
        );

        expect(collection1, equals(collection2));
        expect(collection1.hashCode, equals(collection2.hashCode));
      });

      test('different collections are not equal', () {
        final collection1 = Collection(
          localizedName: LocalizedString.fromString('Collection 1'),
        );

        final collection2 = Collection(
          localizedName: LocalizedString.fromString('Collection 2'),
        );

        expect(collection1, isNot(equals(collection2)));
      });
    });
  });

  group('Contributor', () {
    group('constructor', () {
      test('creates contributor with required name', () {
        final contributor = Contributor(
          localizedName: LocalizedString.fromString('Author Name'),
        );

        expect(contributor.name, equals('Author Name'));
        expect(contributor.identifier, isNull);
        expect(contributor.roles, isEmpty);
      });

      test('creates contributor with all parameters', () {
        final contributor = Contributor(
          localizedName: LocalizedString.fromString('Jane Doe'),
          identifier: 'author-123',
          localizedSortAs: LocalizedString.fromString('Doe, Jane'),
          roles: ['author'],
          position: 1.0,
          links: [Link(href: 'author.html')],
        );

        expect(contributor.name, equals('Jane Doe'));
        expect(contributor.identifier, equals('author-123'));
        expect(contributor.sortAs, equals('Doe, Jane'));
        expect(contributor.roles, equals(['author']));
        expect(contributor.position, equals(1.0));
        expect(contributor.links, hasLength(1));
      });
    });

    group('fromString', () {
      test('creates contributor from string', () {
        final contributor = Contributor.fromString('John Smith');

        expect(contributor.name, equals('John Smith'));
        expect(contributor.identifier, isNull);
        expect(contributor.roles, isEmpty);
      });
    });

    group('fromJson', () {
      test('parses contributor from string', () {
        final contributor = Contributor.fromJson('Author Name');

        expect(contributor, isNotNull);
        expect(contributor!.name, equals('Author Name'));
      });

      test('parses contributor from object', () {
        final json = {
          'name': 'John Doe',
          'identifier': 'orcid:0000-0001-2345-6789',
          'sortAs': 'Doe, John',
          'role': ['author', 'editor'],
          'position': 1.0,
        };

        final contributor = Contributor.fromJson(json);

        expect(contributor, isNotNull);
        expect(contributor!.name, equals('John Doe'));
        expect(contributor.identifier, equals('orcid:0000-0001-2345-6789'));
        expect(contributor.sortAs, equals('Doe, John'));
        expect(contributor.roles, hasLength(2));
        expect(contributor.roles, contains('author'));
        expect(contributor.roles, contains('editor'));
        expect(contributor.position, equals(1.0));
      });

      test('returns null for null json', () {
        expect(Contributor.fromJson(null), isNull);
      });

      test('returns null for object without name', () {
        final json = {
          'identifier': 'id-only',
          'role': ['author'],
        };

        expect(Contributor.fromJson(json), isNull);
      });

      test('parses contributor with localized name', () {
        final json = {
          'name': {'en': 'English Author', 'de': 'Deutscher Autor'},
        };

        final contributor = Contributor.fromJson(json);

        expect(contributor, isNotNull);
        expect(contributor!.name, equals('English Author'));
      });

      test('parses contributor with links', () {
        final json = {
          'name': 'Author',
          'links': [
            {'href': 'author-page.html', 'type': 'text/html'},
          ],
        };

        final contributor = Contributor.fromJson(json);

        expect(contributor, isNotNull);
        expect(contributor!.links, hasLength(1));
        expect(contributor.links[0].href, equals('author-page.html'));
      });
    });

    group('fromJsonArray', () {
      test('parses array of contributor objects', () {
        final json = [
          {
            'name': 'Author 1',
            'role': ['author'],
          },
          {
            'name': 'Author 2',
            'role': ['author'],
          },
          {
            'name': 'Editor 1',
            'role': ['editor'],
          },
        ];

        final contributors = Contributor.fromJsonArray(json);

        expect(contributors, hasLength(3));
        expect(contributors[0].name, equals('Author 1'));
        expect(contributors[1].name, equals('Author 2'));
        expect(contributors[2].name, equals('Editor 1'));
      });

      test('parses array of contributor strings', () {
        final json = ['John Doe', 'Jane Smith'];

        final contributors = Contributor.fromJsonArray(json);

        expect(contributors, hasLength(2));
        expect(contributors[0].name, equals('John Doe'));
        expect(contributors[1].name, equals('Jane Smith'));
      });

      test('parses single contributor string', () {
        final contributors = Contributor.fromJsonArray('Single Author');

        expect(contributors, hasLength(1));
        expect(contributors[0].name, equals('Single Author'));
      });

      test('parses single contributor object', () {
        final json = {
          'name': 'Solo Contributor',
          'role': ['author'],
        };

        final contributors = Contributor.fromJsonArray(json);

        expect(contributors, hasLength(1));
        expect(contributors[0].name, equals('Solo Contributor'));
      });

      test('filters out invalid contributors', () {
        final json = [
          {'name': 'Valid Author'},
          {
            'role': ['author'],
          }, // Missing name
          {'name': ''}, // Empty name
          {'name': 'Another Valid'},
        ];

        final contributors = Contributor.fromJsonArray(json);

        expect(contributors, hasLength(2));
        expect(contributors[0].name, equals('Valid Author'));
        expect(contributors[1].name, equals('Another Valid'));
      });

      test('returns empty list for null', () {
        final contributors = Contributor.fromJsonArray(null);
        expect(contributors, isEmpty);
      });
    });

    group('toJson', () {
      test('serializes contributor to JSON', () {
        final contributor = Contributor(
          localizedName: LocalizedString.fromString('Test Author'),
          identifier: 'auth-123',
          localizedSortAs: LocalizedString.fromString('Author, Test'),
          roles: ['author', 'illustrator'],
        );

        final json = contributor.toJson();

        expect(json['name'], equals({'und': 'Test Author'}));
        expect(json['identifier'], equals('auth-123'));
        expect(json['sortAs'], equals({'und': 'Author, Test'}));
        expect(json['role'], equals(['author', 'illustrator']));
      });

      test('roundtrip serialization preserves data', () {
        final original = Contributor(
          localizedName: LocalizedString.fromString('Roundtrip Author'),
          identifier: 'rt-auth-456',
          roles: ['author'],
        );

        final json = original.toJson();
        final restored = Contributor.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.name, equals(original.name));
        expect(restored.identifier, equals(original.identifier));
        expect(restored.roles, equals(original.roles));
      });
    });

    group('copyWith', () {
      test('creates copy with updated values', () {
        final original = Contributor(
          localizedName: LocalizedString.fromString('Original Author'),
          identifier: 'old-id',
          roles: ['author'],
        );

        final copy = original.copyWith(
          identifier: 'new-id',
          roles: ['author', 'editor'],
        );

        expect(copy.identifier, equals('new-id'));
        expect(copy.roles, hasLength(2));
        expect(original.identifier, equals('old-id'));
        expect(original.roles, hasLength(1));
      });
    });

    group('toCollection', () {
      test('converts contributor to collection', () {
        final contributor = Contributor(
          localizedName: LocalizedString.fromString('Test Author'),
          identifier: 'auth-123',
          roles: ['author'],
          position: 1.0,
        );

        final collection = contributor.toCollection();

        expect(collection.name, equals(contributor.name));
        expect(collection.identifier, equals(contributor.identifier));
        expect(collection.roles, equals(contributor.roles));
        expect(collection.position, equals(contributor.position));
      });
    });

    group('equality', () {
      test('equal contributors have same hashCode', () {
        final contributor1 = Contributor(
          localizedName: LocalizedString.fromString('Author'),
          identifier: 'id-1',
        );

        final contributor2 = Contributor(
          localizedName: LocalizedString.fromString('Author'),
          identifier: 'id-1',
        );

        expect(contributor1, equals(contributor2));
        expect(contributor1.hashCode, equals(contributor2.hashCode));
      });

      test('different contributors are not equal', () {
        final contributor1 = Contributor(
          localizedName: LocalizedString.fromString('Author 1'),
        );

        final contributor2 = Contributor(
          localizedName: LocalizedString.fromString('Author 2'),
        );

        expect(contributor1, isNot(equals(contributor2)));
      });
    });
  });
}
