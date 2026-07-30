import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flureadium_platform_interface/method_channel_flureadium.dart';

/// Minimal concrete subclass to verify [FlureadiumPlatform] default impls.
class _BarePlatform extends FlureadiumPlatform {
  @override
  Future<String?> getLinkContent(Link link) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('refreshCarContent contract', () {
    test('default implementation throws UnimplementedError', () {
      final platform = _BarePlatform();
      expect(platform.refreshCarContent, throwsA(isA<UnimplementedError>()));
    });
  });

  group('MethodChannelFlureadium.refreshCarContent', () {
    late MethodChannelFlureadium platform;
    late List<MethodCall> methodCalls;

    setUp(() {
      platform = MethodChannelFlureadium();
      methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            methodCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, null);
    });

    test('invokes the native refreshCarContent method once', () async {
      platform.refreshCarContent();
      // Fire-and-forget: let the unawaited invocation reach the mock handler.
      await pumpEventQueue();

      expect(methodCalls, hasLength(1));
      expect(methodCalls.single.method, 'refreshCarContent');
    });
  });
}
