import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium/flureadium.dart';

import '../mocks/mock_platform.dart';

class _NoopProvider extends CarContentProvider {
  @override
  Future<List<CarTab>> rootTabs() async => const [];
  @override
  Future<List<CarBrowseNode>> children(String nodeId) async => const [];
  @override
  Future<List<CarBrowseNode>> search(String query) async => const [];
  @override
  Future<void> play(String nodeId) async {}
  @override
  Future<List<CarBrowseNode>> nowPlayingChapters() async => const [];
  @override
  Future<void> addBookmark() async {}
  @override
  Future<void> cycleSpeed() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Flureadium flureadium;
  late MockFlureadiumPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockFlureadiumPlatform();
    FlureadiumPlatform.instance = mockPlatform;
    flureadium = Flureadium();
  });

  tearDown(() => mockPlatform.dispose());

  group('registerCarContentProvider', () {
    test('forwards the provider and strings to the platform', () {
      final provider = _NoopProvider();
      final strings = CarContentStrings(
        emptyRootTitle: 'Nothing to play yet',
        emptyRootSubtitle: 'Add books to see them here.',
        voiceUnavailable: 'This voice is not installed.',
        offline: 'This book needs a connection.',
      );

      flureadium.registerCarContentProvider(provider, strings: strings);

      expect(mockPlatform.wasCalled('registerCarContentProvider'), isTrue);
      expect(mockPlatform.registeredCarProvider, same(provider));
      expect(mockPlatform.registeredCarStrings, same(strings));
    });

    test('unregisterCarContentProvider clears the platform hook', () {
      final provider = _NoopProvider();
      flureadium.registerCarContentProvider(
        provider,
        strings: CarContentStrings(
          emptyRootTitle: 'a',
          emptyRootSubtitle: 'b',
          voiceUnavailable: 'c',
          offline: 'd',
        ),
      );

      flureadium.unregisterCarContentProvider();

      expect(mockPlatform.wasCalled('unregisterCarContentProvider'), isTrue);
      expect(mockPlatform.registeredCarProvider, isNull);
      expect(mockPlatform.registeredCarStrings, isNull);
    });
  });
}
