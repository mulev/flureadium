import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

/// A minimal in-memory provider exercising the abstract contract in isolation.
class _FakeProvider extends CarContentProvider {
  final List<String> played = [];
  int bookmarks = 0;
  int speedCycles = 0;

  @override
  Future<List<CarTab>> rootTabs() async => [
    CarTab(id: 'continue', title: 'Continue'),
    CarTab(id: 'library', title: 'Library'),
  ];

  @override
  Future<List<CarBrowseNode>> children(String nodeId) async => [
    CarBrowseNode(
      id: '$nodeId/book:1',
      title: 'The Odyssey',
      kind: CarNodeKind.audiobook,
      isPlayable: true,
    ),
  ];

  @override
  Future<List<CarBrowseNode>> search(String query) async => [
    CarBrowseNode(
      id: 'book:weir',
      title: 'Project Hail Mary',
      subtitle: query,
      kind: CarNodeKind.audiobook,
      isPlayable: true,
    ),
  ];

  @override
  Future<void> play(String nodeId) async => played.add(nodeId);

  @override
  Future<List<CarBrowseNode>> nowPlayingChapters() async => [
    CarBrowseNode(id: 'ch:1', title: 'Chapter 1', kind: CarNodeKind.chapter),
  ];

  @override
  Future<void> addBookmark() async => bookmarks++;

  @override
  Future<void> cycleSpeed() async => speedCycles++;
}

void main() {
  group('CarContentProvider', () {
    late _FakeProvider provider;

    setUp(() => provider = _FakeProvider());

    test('rootTabs returns the host tabs', () async {
      final tabs = await provider.rootTabs();
      expect(tabs.map((t) => t.id), ['continue', 'library']);
    });

    test('children returns nodes scoped to the requested id', () async {
      final nodes = await provider.children('library');
      expect(nodes.single.id, 'library/book:1');
      expect(nodes.single.isPlayable, isTrue);
    });

    test('search reaches the provider with the query', () async {
      final results = await provider.search('weir');
      expect(results.single.subtitle, 'weir');
    });

    test('play records the selected node id', () async {
      await provider.play('book:42');
      expect(provider.played, ['book:42']);
    });

    test('nowPlayingChapters returns chapter nodes', () async {
      final chapters = await provider.nowPlayingChapters();
      expect(chapters.single.kind, CarNodeKind.chapter);
    });

    test('addBookmark reaches the provider', () async {
      await provider.addBookmark();
      expect(provider.bookmarks, 1);
    });

    test('cycleSpeed reaches the provider', () async {
      await provider.cycleSpeed();
      expect(provider.speedCycles, 1);
    });
  });
}
