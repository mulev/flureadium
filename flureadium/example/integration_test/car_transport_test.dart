import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flureadium/flureadium.dart';

/// A stand-in host provider with a tiny fixed library, so the transport can be
/// driven end-to-end at the Dart level without a real head unit.
class _StubProvider extends CarContentProvider {
  final List<String> played = [];

  @override
  Future<List<CarTab>> rootTabs() async => [
    CarTab(id: 'continue', title: 'Continue'),
    CarTab(id: 'library', title: 'Library'),
  ];

  @override
  Future<List<CarBrowseNode>> children(String nodeId) async => [
    CarBrowseNode(
      id: 'book:1',
      title: 'The Odyssey',
      subtitle: 'Homer',
      kind: CarNodeKind.audiobook,
      isPlayable: true,
      progress: 0.25,
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
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
  const carChannel = MethodChannel('dev.mulev.flureadium/car');

  // Simulates a native car request arriving on the channel and returns the
  // decoded Dart response — the same path a head unit drives at runtime.
  Future<Object?> nativeCall(String method, [Object? args]) async {
    final response = await binding.defaultBinaryMessenger.handlePlatformMessage(
      carChannel.name,
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
    return response == null ? null : codec.decodeEnvelope(response);
  }

  late _StubProvider provider;

  setUp(() {
    provider = _StubProvider();
    Flureadium().registerCarContentProvider(
      provider,
      strings: CarContentStrings(
        emptyRootTitle: 'Nothing to play yet',
        emptyRootSubtitle: 'Add books to see them here.',
        voiceUnavailable: 'This voice is not installed.',
        offline: 'This book needs a connection.',
      ),
    );
  });

  tearDown(() => Flureadium().unregisterCarContentProvider());

  testWidgets('rootTabs round-trips through the registered provider', (
    tester,
  ) async {
    final tabs = (await nativeCall('rootTabs')) as List;
    expect(tabs.map((t) => (t as Map)['id']), ['continue', 'library']);
  });

  testWidgets('children round-trips a playable node with progress', (
    tester,
  ) async {
    final nodes = (await nativeCall('children', {'nodeId': 'library'})) as List;
    final first = (nodes.single as Map).cast<String, Object?>();
    expect(first['id'], 'book:1');
    expect(first['isPlayable'], isTrue);
    expect(first['progress'], 0.25);
  });

  testWidgets('search reaches the provider with the query', (tester) async {
    final results = (await nativeCall('search', {'query': 'weir'})) as List;
    expect((results.single as Map)['id'], 'book:weir');
  });

  testWidgets('play routes the node id to the provider', (tester) async {
    await nativeCall('play', {'nodeId': 'book:42'});
    expect(provider.played, ['book:42']);
  });

  testWidgets('strings return the registered localized copy', (tester) async {
    final strings = (await nativeCall('strings') as Map)
        .cast<String, Object?>();
    expect(strings['emptyRootTitle'], 'Nothing to play yet');
  });
}
