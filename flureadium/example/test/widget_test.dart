import 'dart:convert';

import 'package:flureadium_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal publication JSON the mocked main channel returns from openPublication
// so a cold boot / reopen actually loads a publication in a widget test.
final _publicationJson = json.encode({
  'metadata': {'title': 'Test Book'},
  'links': <Object>[],
  'readingOrder': <Object>[],
});

// The reader widget toggles the screen wakelock on mount/dispose via a
// wakelock_plus pigeon channel. Stub it so mounting a real reader in a widget
// test doesn't hit an unconnected platform channel. Pigeon replies are a
// single-element list wrapping the return value.
void _mockWakelock() {
  const codec = StandardMessageCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const prefix =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi';
  messenger.setMockMessageHandler(
    '$prefix.toggle',
    (message) async => codec.encodeMessage(<Object?>[null]),
  );
  messenger.setMockMessageHandler(
    '$prefix.isEnabled',
    (message) async => codec.encodeMessage(<Object?>[false]),
  );
}

void _mockEventChannel(String channelName) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        MethodChannel(channelName),
        (call) async => null,
      );
}

// Pushes a single event onto an EventChannel's broadcast stream, as if the
// native side had emitted it. Used to drive the app into the `ended` timebased
// state without a device.
Future<void> _emitEvent(String channelName, Object? payload) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeSuccessEnvelope(payload),
        (_) {},
      );
}

void _mockMainChannel({
  bool ttsCanSpeak = true,
  bool audioEnableThrows = false,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.mulev.flureadium/main'),
        (call) async {
          if (call.method == 'ttsCanSpeak') return ttsCanSpeak;
          if (call.method == 'openPublication' ||
              call.method == 'loadPublication') {
            return _publicationJson;
          }
          if (call.method == 'audioEnable' && audioEnableThrows) {
            throw PlatformException(
              code: 'AUDIO_ERROR',
              message: 'Couldn\'t create AudioNavigatorFactory',
            );
          }
          return null;
        },
      );
}

// Reads a keyed 'key: value' debug Text and strips the 'key: ' prefix.
String _keyedValue(WidgetTester tester, String key) =>
    (tester.widget<Text>(find.byKey(Key(key))).data ?? '').replaceFirst(
      '$key: ',
      '',
    );

// Opening a publication does real file I/O (_extractAsset), which only
// completes on the real event loop, so it must run inside tester.runAsync.
// Pumps a frame plus a real delay each tick until open-generation reaches
// [target] or the bound is hit.
Future<void> _pumpUntilGeneration(WidgetTester tester, String target) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (_keyedValue(tester, 'open-generation') == target) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _mockEventChannel('dev.mulev.flureadium/reader-status');
    _mockEventChannel('dev.mulev.flureadium/text-locator');
    _mockEventChannel('dev.mulev.flureadium/error');
    _mockEventChannel('dev.mulev.flureadium/timebased-state');
    _mockMainChannel();
    _mockWakelock();
  });

  testWidgets('app renders MaterialApp with ReaderPage', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(ReaderPage), findsOneWidget);
  });

  testWidgets('tts_can_speak_false_shows_not_supported_snackbar', (
    tester,
  ) async {
    _mockMainChannel(ttsCanSpeak: false);
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.tap(find.text('TTS On'));
    await tester.pump();
    expect(
      find.text('TTS is not supported for this publication'),
      findsOneWidget,
    );
  });

  testWidgets('tts_speed_slider_not_visible_initially', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('tts_pause_button_not_visible_initially', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.text('Pause TTS'), findsNothing);
  });

  testWidgets('generic open bumps open-generation on every open', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const ExampleApp());
      await _pumpUntilGeneration(tester, '1');
    });

    // Cold boot goes through _openPublicationAsset, so the counter is 1.
    expect(_keyedValue(tester, 'open-generation'), '1');
    expect(_keyedValue(tester, 'ended-seen'), 'false');

    await tester.runAsync(() async {
      await tester.tap(find.text('Open EPUB'));
      await _pumpUntilGeneration(tester, '2');
    });

    expect(_keyedValue(tester, 'open-generation'), '2');
  });

  testWidgets('generic open resets ended-seen', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const ExampleApp());
      await _pumpUntilGeneration(tester, '1');
    });

    await _emitEvent(
      'dev.mulev.flureadium/timebased-state',
      json.encode({'state': 'ended'}),
    );
    await tester.pump();
    expect(_keyedValue(tester, 'ended-seen'), 'true');

    await tester.runAsync(() async {
      await tester.tap(find.text('Open EPUB'));
      await _pumpUntilGeneration(tester, '2');
    });

    expect(_keyedValue(tester, 'ended-seen'), 'false');
  });

  testWidgets('audio_enable_error_shows_snackbar', (tester) async {
    _mockMainChannel(audioEnableThrows: true);
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.tap(find.text('Audio Play'));
    await tester.pump();
    expect(find.textContaining('Audio playback unavailable'), findsOneWidget);
  });
}
