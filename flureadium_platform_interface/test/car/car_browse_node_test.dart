import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('CarBrowseNode', () {
    test('fromMap(toMap()) round-trips every field for each CarNodeKind', () {
      for (final kind in CarNodeKind.values) {
        final node = CarBrowseNode(
          id: 'book:42',
          title: 'Project Hail Mary',
          subtitle: 'Andy Weir · 62%',
          artworkPath: '/covers/phm.jpg',
          kind: kind,
          isPlayable: true,
          progress: 0.62,
          isNowPlaying: true,
        );

        final restored = CarBrowseNode.fromMap(node.toMap());

        expect(restored.id, node.id);
        expect(restored.title, node.title);
        expect(restored.subtitle, node.subtitle);
        expect(restored.artworkPath, node.artworkPath);
        expect(restored.kind, kind);
        expect(restored.isPlayable, isTrue);
        expect(restored.progress, 0.62);
        expect(restored.isNowPlaying, isTrue);
      }
    });

    test('missing optional fields decode to defaults', () {
      final node = CarBrowseNode.fromMap(<String, Object?>{
        'id': 'genre:sci-fi',
        'title': 'Science Fiction',
        'kind': 'container',
      });

      expect(node.subtitle, isNull);
      expect(node.artworkPath, isNull);
      expect(node.progress, isNull);
      expect(node.isPlayable, isFalse);
      expect(node.isNowPlaying, isFalse);
    });

    test('progress decodes from an int map value', () {
      final node = CarBrowseNode.fromMap(<String, Object?>{
        'id': 'x',
        'title': 'y',
        'kind': 'audiobook',
        'progress': 1,
      });

      expect(node.progress, 1.0);
    });

    test('boundary progress values 0 and 1 are accepted', () {
      expect(
        CarBrowseNode(
          id: 'x',
          title: 'y',
          kind: CarNodeKind.audiobook,
          progress: 0,
        ).progress,
        0.0,
      );
      expect(
        CarBrowseNode(
          id: 'x',
          title: 'y',
          kind: CarNodeKind.audiobook,
          progress: 1,
        ).progress,
        1.0,
      );
    });

    test('progress above 1 is rejected', () {
      expect(
        () => CarBrowseNode(
          id: 'x',
          title: 'y',
          kind: CarNodeKind.audiobook,
          progress: 2,
        ),
        throwsArgumentError,
      );
    });

    test('negative progress is rejected', () {
      expect(
        () => CarBrowseNode(
          id: 'x',
          title: 'y',
          kind: CarNodeKind.audiobook,
          progress: -0.5,
        ),
        throwsArgumentError,
      );
    });

    test('a blank id is rejected', () {
      expect(
        () => CarBrowseNode(id: '', title: 'y', kind: CarNodeKind.container),
        throwsArgumentError,
      );
    });

    test('a blank title is rejected', () {
      expect(
        () => CarBrowseNode(id: 'x', title: '', kind: CarNodeKind.container),
        throwsArgumentError,
      );
    });
  });
}
