import 'package:flutter/foundation.dart';
import 'package:flureadium/flureadium.dart';

/// A fake [CarContentProvider] for the STAGE-1 CarPlay / Android Auto validation
/// (see the car bridge ADR). It serves a few hand-written nodes — no real
/// library — so the example can prove the headless car engine boots cold and the
/// `dev.mulev.flureadium/car` channel round-trips. The real Fablum provider,
/// backed by `BookRepository`, arrives in Phase 5.
class StubCarContentProvider extends CarContentProvider {
  /// The host-owned, already-localized status copy the car renderer shows when
  /// the root is empty. The example is a demo host, so its copy is plain English.
  static final CarContentStrings strings = CarContentStrings(
    emptyRootTitle: 'Nothing to play yet',
    emptyRootSubtitle: 'Add books to see them here',
    voiceUnavailable: 'This voice is not installed',
    offline: 'This book needs a connection',
  );

  @override
  Future<List<CarTab>> rootTabs() async => [
    CarTab(id: 'continue', title: 'Continue', iconName: 'play.circle'),
    CarTab(id: 'library', title: 'Library', iconName: 'books.vertical'),
    CarTab(id: 'search', title: 'Search', iconName: 'magnifyingglass'),
  ];

  @override
  Future<List<CarBrowseNode>> children(String nodeId) async {
    switch (nodeId) {
      case 'continue':
        return [
          CarBrowseNode(
            id: 'book:hail-mary',
            title: 'Project Hail Mary',
            subtitle: 'Andy Weir · 62%',
            kind: CarNodeKind.audiobook,
            isPlayable: true,
            progress: 0.62,
            isNowPlaying: true,
          ),
        ];
      case 'library':
        return [
          CarBrowseNode(
            id: 'genre:sci-fi',
            title: 'Science Fiction',
            kind: CarNodeKind.container,
          ),
          CarBrowseNode(
            id: 'book:dune',
            title: 'Dune',
            subtitle: 'Frank Herbert',
            kind: CarNodeKind.audiobook,
            isPlayable: true,
          ),
        ];
      case 'genre:sci-fi':
        return [
          CarBrowseNode(
            id: 'book:hail-mary',
            title: 'Project Hail Mary',
            subtitle: 'Andy Weir',
            kind: CarNodeKind.audiobook,
            isPlayable: true,
            progress: 0.62,
          ),
        ];
      case 'search':
        return [
          CarBrowseNode(
            id: 'siri',
            title: 'Search with Siri',
            kind: CarNodeKind.siri,
          ),
        ];
      default:
        return const [];
    }
  }

  @override
  Future<List<CarBrowseNode>> search(String query) async => [
    CarBrowseNode(
      id: 'book:dune',
      title: 'Dune',
      subtitle: 'Frank Herbert',
      kind: CarNodeKind.audiobook,
      isPlayable: true,
    ),
  ];

  @override
  Future<void> play(String nodeId) async {
    // STAGE-1 proves the tap→Dart round-trip; real playback is Phase 6.
    debugPrint('[carMain] play round-trip for node: $nodeId');
  }

  @override
  Future<List<CarBrowseNode>> nowPlayingChapters() async => [
    CarBrowseNode(
      id: 'ch:1',
      title: 'Chapter 1',
      kind: CarNodeKind.chapter,
      isPlayable: true,
    ),
  ];

  @override
  Future<void> addBookmark() async {
    // STAGE-1 proves the tap→Dart round-trip; real bookmarking is app-side.
    debugPrint('[carMain] addBookmark round-trip');
  }

  @override
  Future<void> cycleSpeed() async {
    // STAGE-1 proves the tap→Dart round-trip; real speed control is app-side.
    debugPrint('[carMain] cycleSpeed round-trip');
  }
}
