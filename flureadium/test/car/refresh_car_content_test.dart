import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium/flureadium.dart';

import '../mocks/mock_platform.dart';

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

  group('refreshCarContent', () {
    test('delegates to the platform exactly once', () {
      flureadium.refreshCarContent();

      expect(mockPlatform.callCount('refreshCarContent'), 1);
    });
  });
}
