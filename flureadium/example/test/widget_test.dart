import 'dart:convert';

import 'package:flureadium/flureadium.dart';
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

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

// The reader widget toggles the screen wakelock on mount/dispose via a
// wakelock_plus pigeon channel. Stub it so mounting a real reader in a widget
// test doesn't hit an unconnected platform channel. Pigeon replies are a
// single-element list wrapping the return value.
void _mockWakelock() {
  const codec = StandardMessageCodec();
  const prefix =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi';
  _messenger.setMockMessageHandler(
    '$prefix.toggle',
    (message) async => codec.encodeMessage(<Object?>[null]),
  );
  _messenger.setMockMessageHandler(
    '$prefix.isEnabled',
    (message) async => codec.encodeMessage(<Object?>[false]),
  );
}

void _mockEventChannel(String channelName) {
  _messenger.setMockMethodCallHandler(
    MethodChannel(channelName),
    (call) async => null,
  );
}

// Pushes a single event onto an EventChannel's broadcast stream, as if the
// native side had emitted it. Used to drive the app into the `ended` timebased
// state without a device.
Future<void> _emitEvent(String channelName, Object? payload) async {
  await _messenger.handlePlatformMessage(
    channelName,
    const StandardMethodCodec().encodeSuccessEnvelope(payload),
    (_) {},
  );
}

// The plugin decodes text-locator events with `Locator.fromJson(json.decode(
// event))`, so the payload is a JSON string, and `href` and `type` are both
// required for the decode to yield a locator.
Future<void> _emitTextLocator(String href, {double? progression}) => _emitEvent(
  'dev.mulev.flureadium/text-locator',
  json.encode({
    'href': href,
    'type': 'application/xhtml+xml',
    if (progression != null) 'locations': {'progression': progression},
  }),
);

// The app subscribes to reader-status, text-locator and error from
// ReadiumReaderWidget.onReady, which the native platform view fires once its
// channels are up. A widget test creates no platform view, so it plays that
// part itself.
void _reportReaderReady(WidgetTester tester) => tester
    .widget<ReadiumReaderWidget>(find.byType(ReadiumReaderWidget))
    .onReady!();

void _mockMainChannel({
  bool ttsCanSpeak = true,
  bool audioEnableThrows = false,
  bool openPublicationThrows = false,
}) {
  _messenger.setMockMethodCallHandler(
    const MethodChannel('dev.mulev.flureadium/main'),
    (call) async {
      if (call.method == 'ttsCanSpeak') return ttsCanSpeak;
      if (call.method == 'openPublication' ||
          call.method == 'loadPublication') {
        // Only openPublication fails: 'Load Only latches the title
        // loadPublication returned' needs this branch to keep answering.
        if (openPublicationThrows && call.method == 'openPublication') {
          // `details`, not `message`: ReadiumException.fromPlatformException
          // carries `details` and drops `message`, so a reason put only in
          // `message` reaches the app as 'unknown'.
          throw PlatformException(
            code: 'READIUM_ERROR',
            message: 'openPublication failed',
            details: 'Unable to resolve host',
          );
        }
        return _publicationJson;
      }
      if (call.method == 'audioEnable' && audioEnableThrows) {
        throw PlatformException(
          code: 'AUDIO_ERROR',
          message: "Couldn't create AudioNavigatorFactory",
        );
      }
      return null;
    },
  );
}

// Reads a keyed debug Text verbatim. The locator latches carry a raw value
// with no 'key: ' prefix, so they are read through this directly.
String _latchText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

// Reads a keyed 'key: value' debug Text and strips the 'key: ' prefix.
String _keyedValue(WidgetTester tester, String key) =>
    _latchText(tester, key).replaceFirst('$key: ', '');

// Opening a publication does real file I/O (_extractAsset), which only
// completes on the real event loop, so these must run inside tester.runAsync.
// Pumps a frame plus a real delay each tick until [done] holds or the bound is
// hit.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpUntilGeneration(WidgetTester tester, String target) =>
    _pumpUntil(tester, () => _keyedValue(tester, 'open-generation') == target);

// Cold-boots the app and waits for the initState open to land. The
// open-generation bump is the signal, because it moves only after
// openPublication returns.
Future<void> _bootApp(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(const ExampleApp());
    await _pumpUntilGeneration(tester, '1');
  });
}

// Taps an 'Open ...' button and waits for open-generation to reach [generation].
Future<void> _tapOpen(
  WidgetTester tester,
  String button,
  String generation,
) async {
  await tester.runAsync(() async {
    await tester.tap(find.text(button));
    await _pumpUntilGeneration(tester, generation);
  });
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

  testWidgets('the controls toggle stays tappable under a tall control bar', (
    tester,
  ) async {
    // The control bar has no height cap, so on a short screen its Column is
    // taller than the viewport and overlaps the toggle at the top-left. A
    // 411x400 logical screen forces that overlap on any machine, rather than
    // copying CI's 682 dp screen, which only overlaps at today's button count.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(411, 400);
    addTearDown(tester.view.reset);

    final controlBar = find.byKey(const Key('control-bar'));

    await _bootApp(tester);

    expect(controlBar, findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle-controls')));
    await tester.pump();

    expect(
      controlBar,
      findsNothing,
      reason: 'the control bar took the tap aimed at its own toggle',
    );
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
    await _bootApp(tester);

    // Cold boot goes through _openPublicationAsset, so the counter is 1.
    expect(_keyedValue(tester, 'open-generation'), '1');
    expect(_keyedValue(tester, 'ended-seen'), 'false');

    await _tapOpen(tester, 'Open EPUB', '2');

    expect(_keyedValue(tester, 'open-generation'), '2');
  });

  testWidgets('generic open resets ended-seen', (tester) async {
    await _bootApp(tester);

    await _emitEvent(
      'dev.mulev.flureadium/timebased-state',
      json.encode({'state': 'ended'}),
    );
    await tester.pump();
    expect(_keyedValue(tester, 'ended-seen'), 'true');

    await _tapOpen(tester, 'Open EPUB', '2');

    expect(_keyedValue(tester, 'ended-seen'), 'false');
  });

  testWidgets('saved locator latches the first position, not the latest', (
    tester,
  ) async {
    await _bootApp(tester);
    _reportReaderReady(tester);

    await _emitTextLocator('chapter1.xhtml');
    await tester.pump();
    await _emitTextLocator('chapter2.xhtml');
    await tester.pump();

    expect(_latchText(tester, 'locator_href'), 'chapter2.xhtml');
    expect(_latchText(tester, 'saved_locator_href'), 'chapter1.xhtml');
  });

  testWidgets('the progression latch follows the last locator', (tester) async {
    await _bootApp(tester);
    _reportReaderReady(tester);

    // Empty before any delivery, like the two href latches beside it.
    expect(_latchText(tester, 'locator_progression'), '');

    await _emitTextLocator('chapter1.xhtml', progression: 0.25);
    await tester.pump();
    await _emitTextLocator('chapter2.xhtml', progression: 0.75);
    await tester.pump();

    // The last locator's progression, not the first — the saved-locator latch
    // beside it is the one that keeps the first.
    expect(_latchText(tester, 'locator_progression'), '0.75');
  });

  testWidgets('opening a publication clears the saved locator', (tester) async {
    await _bootApp(tester);
    _reportReaderReady(tester);

    await _emitTextLocator('chapter1.xhtml');
    await tester.pump();
    expect(_latchText(tester, 'saved_locator_href'), 'chapter1.xhtml');

    await _tapOpen(tester, 'Open EPUB', '2');

    expect(_latchText(tester, 'saved_locator_href'), '');
  });

  testWidgets('locator-events counts every delivery and resets on open', (
    tester,
  ) async {
    await _bootApp(tester);
    _reportReaderReady(tester);

    expect(_keyedValue(tester, 'locator-events'), '0');

    await _emitTextLocator('chapter1.xhtml');
    await tester.pump();
    await _emitTextLocator('chapter2.xhtml');
    await tester.pump();

    // Monotonic: two deliveries, two counts, even though the second one
    // overwrites the latch the first one wrote.
    expect(_keyedValue(tester, 'locator-events'), '2');

    await _tapOpen(tester, 'Open EPUB', '2');

    // The count is a fact about one publication, like every other latch
    // _resetPublicationLatches clears.
    expect(_keyedValue(tester, 'locator-events'), '0');
  });

  testWidgets('Resubscribe Locator clears the latched locator', (tester) async {
    await _bootApp(tester);
    _reportReaderReady(tester);

    await _emitTextLocator('chapter1.xhtml');
    await tester.pump();
    expect(_latchText(tester, 'locator_href'), 'chapter1.xhtml');
    final delivered = _keyedValue(tester, 'locator-events');

    await tester.tap(find.text('Resubscribe Locator'));
    await tester.pump();

    // The mocked channel answers nothing on subscribe, so the cleared state is
    // observable here — on a device the real stream refills it within the
    // frame, which is why the integration case asserts the count instead.
    expect(_latchText(tester, 'locator_href'), '');
    expect(_keyedValue(tester, 'locator-events'), delivered);
  });

  testWidgets('Load Only latches the title loadPublication returned', (
    tester,
  ) async {
    await _bootApp(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Load Only'));
      await _pumpUntil(
        tester,
        () => _keyedValue(tester, 'loaded-title').isNotEmpty,
      );
    });

    expect(_keyedValue(tester, 'loaded-title'), 'Test Book');
  });

  testWidgets('a failed open latches into open-error, and a good one clears it', (
    tester,
  ) async {
    // Boot clean. The cold-boot open in initState has no catch of any kind, so
    // a channel that throws at pumpWidget time raises an unhandled async error
    // and the test fails on the wrong thing.
    await _bootApp(tester);

    expect(_keyedValue(tester, 'open-error'), '');

    _mockMainChannel(openPublicationThrows: true);
    await tester.runAsync(() async {
      await tester.tap(find.text('Open EPUB'));
      await _pumpUntil(
        tester,
        () => _keyedValue(tester, 'open-error').isNotEmpty,
      );
    });

    // The label says which opener failed and the message says why. Both
    // matter: "something failed" is what the sixteen debugPrints already said,
    // and it is not enough to act on.
    expect(_keyedValue(tester, 'open-error'), startsWith('openEpub: '));
    expect(
      _keyedValue(tester, 'open-error'),
      contains('Unable to resolve host'),
    );
    // A failed open never reaches _resetPublicationLatches, so the counter must
    // not have moved.
    expect(_keyedValue(tester, 'open-generation'), '1');

    // _resetPublicationLatches is what wipes the latch, so a later good open
    // must leave it empty. Without that, the latch would strand a stale error
    // and any "open-error is empty" assertion would fail on a fault that was
    // already over.
    _mockMainChannel();
    await _tapOpen(tester, 'Open EPUB', '2');

    expect(_keyedValue(tester, 'open-error'), '');
  });

  testWidgets('a successful load-only clears a latched open error', (
    tester,
  ) async {
    // Load Only is the one wrapped path that never reaches
    // _resetPublicationLatches: it loads a publication without opening one, so
    // it sets loaded-title and nothing else. If the latch were cleared only by
    // that reset, a failed open followed by a good load would strand the error
    // and any later "open-error is empty" assertion would fail for a fault
    // that was already over.
    await _bootApp(tester);

    _mockMainChannel(openPublicationThrows: true);
    await tester.runAsync(() async {
      await tester.tap(find.text('Open EPUB'));
      await _pumpUntil(
        tester,
        () => _keyedValue(tester, 'open-error').isNotEmpty,
      );
    });
    expect(_keyedValue(tester, 'open-error'), startsWith('openEpub: '));

    _mockMainChannel();
    await tester.runAsync(() async {
      await tester.tap(find.text('Load Only'));
      await _pumpUntil(
        tester,
        () => _keyedValue(tester, 'loaded-title').isNotEmpty,
      );
    });

    // The load succeeded, so the record of the previous failure is gone — and
    // the publication counter did not move, because a load is not an open.
    expect(_keyedValue(tester, 'open-error'), '');
    expect(_keyedValue(tester, 'open-generation'), '1');
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
