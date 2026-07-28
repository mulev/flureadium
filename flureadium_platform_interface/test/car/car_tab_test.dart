import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('CarTab', () {
    test('fromMap(toMap()) round-trips every field', () {
      final tab = CarTab(id: 'library', title: 'Library', iconName: 'books');

      final restored = CarTab.fromMap(tab.toMap());

      expect(restored.id, 'library');
      expect(restored.title, 'Library');
      expect(restored.iconName, 'books');
    });

    test('a null icon hint round-trips', () {
      final tab = CarTab(id: 'search', title: 'Search');

      final restored = CarTab.fromMap(tab.toMap());

      expect(restored.iconName, isNull);
    });

    test('a blank title is rejected', () {
      expect(() => CarTab(id: 'x', title: ''), throwsArgumentError);
    });

    test('a blank id is rejected', () {
      expect(() => CarTab(id: '', title: 'Library'), throwsArgumentError);
    });
  });
}
