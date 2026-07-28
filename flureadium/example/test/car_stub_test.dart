import 'package:flureadium/flureadium.dart';
import 'package:flureadium_example/car_stub.dart';
import 'package:flutter_test/flutter_test.dart';

/// Automated Dart coverage for the STAGE-1 car provider. The native CarPlay
/// rendering is covered by the iOS XCTest suite; here we prove the stub the
/// `carMain` entrypoint registers answers browse/search the way the transport
/// expects.
void main() {
  late StubCarContentProvider provider;

  setUp(() => provider = StubCarContentProvider());

  test('root tabs are Continue, Library, Search', () async {
    final tabs = await provider.rootTabs();
    expect(tabs.map((t) => t.id).toList(), ['continue', 'library', 'search']);
  });

  test('library children include a container and a playable book', () async {
    final nodes = await provider.children('library');
    expect(nodes.any((n) => n.kind == CarNodeKind.container), isTrue);
    expect(nodes.any((n) => n.isPlayable), isTrue);
  });

  test('continue surfaces the now-playing book with progress', () async {
    final node = (await provider.children('continue')).single;
    expect(node.isNowPlaying, isTrue);
    expect(node.progress, closeTo(0.62, 0.0001));
  });

  test('a container node pushes to a playable child', () async {
    final children = await provider.children('genre:sci-fi');
    expect(children, isNotEmpty);
    expect(children.every((n) => n.isPlayable), isTrue);
  });

  test('unknown node id yields no children', () async {
    expect(await provider.children('nope'), isEmpty);
  });

  test('search tab surfaces the Siri assistant marker row', () async {
    final nodes = await provider.children('search');
    expect(nodes.single.kind, CarNodeKind.siri);
  });

  test('search returns matches', () async {
    expect(await provider.search('dune'), isNotEmpty);
  });

  test('status strings are all non-empty', () {
    expect(StubCarContentProvider.strings.emptyRootTitle, isNotEmpty);
    expect(StubCarContentProvider.strings.emptyRootSubtitle, isNotEmpty);
    expect(StubCarContentProvider.strings.voiceUnavailable, isNotEmpty);
    expect(StubCarContentProvider.strings.offline, isNotEmpty);
  });
}
