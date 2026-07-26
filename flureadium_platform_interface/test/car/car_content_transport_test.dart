import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flureadium_platform_interface/src/car/car_content_transport.dart';
import 'package:flureadium_platform_interface/method_channel_flureadium.dart';

/// Records the calls the transport routes to it.
class _RecordingProvider extends CarContentProvider {
  final List<String> childrenOf = [];
  final List<String> searched = [];
  final List<String> played = [];

  @override
  Future<List<CarTab>> rootTabs() async => [
    CarTab(id: 'continue', title: 'Continue'),
  ];

  @override
  Future<List<CarBrowseNode>> children(String nodeId) async {
    childrenOf.add(nodeId);
    return [
      CarBrowseNode(
        id: 'book:1',
        title: 'The Odyssey',
        kind: CarNodeKind.audiobook,
        isPlayable: true,
      ),
    ];
  }

  @override
  Future<List<CarBrowseNode>> search(String query) async {
    searched.add(query);
    return [
      CarBrowseNode(
        id: 'book:weir',
        title: 'Project Hail Mary',
        kind: CarNodeKind.audiobook,
      ),
    ];
  }

  @override
  Future<void> play(String nodeId) async => played.add(nodeId);

  @override
  Future<List<CarBrowseNode>> nowPlayingChapters() async => [
    CarBrowseNode(id: 'ch:1', title: 'Chapter 1', kind: CarNodeKind.chapter),
  ];
}

CarContentStrings _strings() => CarContentStrings(
  emptyRootTitle: 'Nothing to play yet',
  emptyRootSubtitle: 'Add books to see them here.',
  voiceUnavailable: 'This voice is not installed.',
  offline: 'This book needs a connection.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
  const channel = MethodChannel('test.flureadium/car');
  late CarContentTransport transport;
  late _RecordingProvider provider;

  Future<Object?> invoke(String method, [Object? args]) async {
    final response = await TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
    return response == null ? null : codec.decodeEnvelope(response);
  }

  setUp(() {
    provider = _RecordingProvider();
    transport = CarContentTransport(channel: channel);
  });

  tearDown(() {
    transport.unregister();
    channel.setMethodCallHandler(null);
  });

  group('with a registered provider', () {
    setUp(() => transport.register(provider, strings: _strings()));

    test(
      'children(root) invokes the provider and encodes nodes back',
      () async {
        final result = await invoke('children', {'nodeId': 'root'}) as List;

        expect(provider.childrenOf, ['root']);
        final first = (result.single as Map).cast<String, Object?>();
        expect(first['id'], 'book:1');
        expect(first['isPlayable'], isTrue);
      },
    );

    test('rootTabs encodes the tabs back', () async {
      final result = await invoke('rootTabs') as List;
      final first = (result.single as Map).cast<String, Object?>();
      expect(first['id'], 'continue');
    });

    test('search reaches the provider with the query', () async {
      final result = await invoke('search', {'query': 'weir'}) as List;
      expect(provider.searched, ['weir']);
      expect((result.single as Map)['id'], 'book:weir');
    });

    test('play reaches the provider with the node id', () async {
      final result = await invoke('play', {'nodeId': 'book:42'});
      expect(provider.played, ['book:42']);
      expect(result, isNull);
    });

    test('nowPlayingChapters encodes the chapter nodes back', () async {
      final result = await invoke('nowPlayingChapters') as List;
      expect((result.single as Map)['kind'], 'chapter');
    });

    test('strings returns the registered localized copy', () async {
      final result = (await invoke('strings') as Map).cast<String, Object?>();
      expect(result['emptyRootTitle'], 'Nothing to play yet');
    });
  });

  group('with no provider registered (cold app-not-ready)', () {
    test('children returns an empty list and never throws', () async {
      final result = await invoke('children', {'nodeId': 'root'});
      expect(result, isEmpty);
    });

    test('play returns null and never throws', () async {
      final result = await invoke('play', {'nodeId': 'book:42'});
      expect(result, isNull);
    });

    test('strings returns null when none registered', () async {
      final result = await invoke('strings');
      expect(result, isNull);
    });
  });

  group('MethodChannelFlureadium wiring (eager cold-start install)', () {
    const defaultChannel = MethodChannel('dev.mulev.flureadium/car');

    Future<Object?> invokeDefault(String method, [Object? args]) async {
      final response = await TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            defaultChannel.name,
            codec.encodeMethodCall(MethodCall(method, args)),
            (_) {},
          );
      return response == null ? null : codec.decodeEnvelope(response);
    }

    test('installs the car channel handler before any registration', () async {
      // Constructing the platform must install the handler on the real car
      // channel so a cold-launched car process gets typed empty results
      // rather than a MissingPluginException.
      MethodChannelFlureadium();

      final result = await invokeDefault('children', {'nodeId': 'root'});

      expect(result, isEmpty);
      defaultChannel.setMethodCallHandler(null);
    });
  });
}
