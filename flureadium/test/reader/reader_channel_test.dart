import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium/flureadium.dart';
import 'package:flureadium/reader_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'test-reader-channel';
  late ReadiumReaderChannel channel;
  final List<MethodCall> log = [];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (
          call,
        ) async {
          log.add(call);
          return null;
        });
    channel = ReadiumReaderChannel(channelName, onPageChanged: (_) {});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), null);
  });

  group('applyDecorations', () {
    test('encodes empty decoration list without throwing', () async {
      await channel.applyDecorations('highlights', []);

      expect(log, hasLength(1));
      expect(log.first.method, equals('applyDecorations'));
    });

    test('encodes non-empty decoration list without throwing', () async {
      final decoration = ReaderDecoration(
        id: 'test-id',
        locator: Locator(href: 'chapter1.xhtml', type: 'application/xhtml+xml'),
        style: ReaderDecorationStyle(
          style: DecorationStyle.highlight,
          tint: const Color(0xFFFFFF00),
        ),
      );

      await channel.applyDecorations('highlights', [decoration]);

      expect(log, hasLength(1));
      expect(log.first.method, equals('applyDecorations'));
    });

    test('passes a List (not MappedListIterable) to the codec', () async {
      final decorations = [
        ReaderDecoration(
          id: 'id-1',
          locator: Locator(
            href: 'chapter1.xhtml',
            type: 'application/xhtml+xml',
          ),
          style: ReaderDecorationStyle(
            style: DecorationStyle.highlight,
            tint: const Color(0xFFFFFF00),
          ),
        ),
        ReaderDecoration(
          id: 'id-2',
          locator: Locator(
            href: 'chapter2.xhtml',
            type: 'application/xhtml+xml',
          ),
          style: ReaderDecorationStyle(
            style: DecorationStyle.underline,
            tint: const Color(0xFF0000FF),
          ),
        ),
      ];

      await channel.applyDecorations('highlights', decorations);

      final args = log.first.arguments as List;
      final decorationList = args[1];
      expect(decorationList, isA<List>());
      expect(decorationList, hasLength(2));
    });

    test('passes the group id as first argument', () async {
      await channel.applyDecorations('my-group', []);

      final args = log.first.arguments as List;
      expect(args[0], equals('my-group'));
    });

    test('each decoration map contains required fields', () async {
      final locator = Locator(
        href: 'chapter1.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(position: 1, totalProgression: 0.5),
        text: LocatorText(highlight: 'some text'),
      );
      final decoration = ReaderDecoration(
        id: 'highlight-xyz',
        locator: locator,
        style: ReaderDecorationStyle(
          style: DecorationStyle.highlight,
          tint: const Color(0xFFFFFF00),
        ),
      );

      await channel.applyDecorations('highlights', [decoration]);

      final args = log.first.arguments as List;
      final decorationList = args[1] as List;
      final decoMap = decorationList[0] as Map;
      final styleMap = decoMap['style'] as Map;

      expect(decoMap['id'], equals('highlight-xyz'));
      expect((decoMap['locator'] as Map)['href'], equals('chapter1.xhtml'));
      expect(styleMap['style'], equals('highlight'));
      expect(styleMap['tint'], equals('#ffff00'));
    });
  });

  group('goLeft', () {
    test('forwards animated: true by default', () async {
      await channel.goLeft();

      expect(log, hasLength(1));
      expect(log.first.method, equals('goLeft'));
      expect(log.first.arguments, isTrue);
    });

    test('forwards animated: false when explicitly passed', () async {
      await channel.goLeft(animated: false);

      expect(log, hasLength(1));
      expect(log.first.method, equals('goLeft'));
      expect(log.first.arguments, isFalse);
    });
  });

  group('goRight', () {
    test('forwards animated: true by default', () async {
      await channel.goRight();

      expect(log, hasLength(1));
      expect(log.first.method, equals('goRight'));
      expect(log.first.arguments, isTrue);
    });

    test('forwards animated: false when explicitly passed', () async {
      await channel.goRight(animated: false);

      expect(log, hasLength(1));
      expect(log.first.method, equals('goRight'));
      expect(log.first.arguments, isFalse);
    });
  });

  group('native callbacks', () {
    test('forwards external link callback from native method call', () async {
      String? seen;
      channel = ReadiumReaderChannel(
        channelName,
        onPageChanged: (_) {},
        onExternalLinkActivated: (url) => seen = url,
      );

      await channel.onMethodCall(
        const MethodCall('onExternalLinkActivated', 'https://example.com'),
      );

      expect(seen, 'https://example.com');
    });

    test('forwards tap position from native method call', () async {
      Offset? seen;
      channel = ReadiumReaderChannel(
        channelName,
        onPageChanged: (_) {},
        onTap: (position) => seen = position,
      );

      await channel.onMethodCall(
        const MethodCall('onTap', {'x': 12.5, 'y': 30.0}),
      );

      expect(seen, const Offset(12.5, 30.0));
    });

    test('decodes an integer tap payload', () async {
      Offset? seen;
      channel = ReadiumReaderChannel(
        channelName,
        onPageChanged: (_) {},
        onTap: (position) => seen = position,
      );

      await channel.onMethodCall(const MethodCall('onTap', {'x': 10, 'y': 20}));

      expect(seen, const Offset(10, 20));
    });

    test('swallows a malformed tap payload but keeps handling taps', () async {
      Offset? seen;
      channel = ReadiumReaderChannel(
        channelName,
        onPageChanged: (_) {},
        onTap: (position) => seen = position,
      );

      await expectLater(
        channel.onMethodCall(const MethodCall('onTap', {'x': 'left'})),
        completes,
      );
      expect(seen, isNull);

      // The second call is what makes this test mean something: without it,
      // deleting the whole `case 'onTap'` branch still passes, because the
      // `default:` arm's UnimplementedError lands in the same catch.
      await channel.onMethodCall(const MethodCall('onTap', {'x': 1, 'y': 2}));
      expect(seen, const Offset(1, 2));
    });
  });
}
