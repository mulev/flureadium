import 'dart:convert';

import 'package:flureadium_platform_interface/method_channel_flureadium.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal concrete subclass to verify [FlureadiumPlatform] default impls.
class _BarePlatform extends FlureadiumPlatform {
  @override
  Future<String?> getLinkContent(Link link) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('$MethodChannelFlureadium', () {
    late MethodChannelFlureadium methodChannelReadium;
    final testTextLocator = Locator(
      href: 'chapter1.html',
      type: 'text/xhtml',
      locations: Locations(cssSelector: '#loc1'),
      text: LocatorText(before: 'a', highlight: 'b', after: 'c'),
    );

    setUp(() {
      methodChannelReadium = MethodChannelFlureadium();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel(methodChannelReadium.textLocatorChannel.name),
            (methodCall) async {
              if (methodCall.method == 'listen') {
                await TestDefaultBinaryMessengerBinding
                    .instance
                    .defaultBinaryMessenger
                    .handlePlatformMessage(
                      methodChannelReadium.textLocatorChannel.name,
                      methodChannelReadium.textLocatorChannel.codec
                          .encodeSuccessEnvelope(
                            jsonEncode(testTextLocator.toJson()),
                          ),
                      (_) {},
                    );
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel(methodChannelReadium.textLocatorChannel.name),
            null,
          );
    });

    test(
      'onTextLocatorChanged emits the locator the platform pushed',
      () async {
        final result = await methodChannelReadium.onTextLocatorChanged.first;

        expect(result, testTextLocator);
      },
    );
  });

  group('$FlureadiumPlatform defaults', () {
    test('audiobookTrackDurations throws UnimplementedError', () {
      final platform = _BarePlatform();

      expect(
        platform.audiobookTrackDurations,
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
