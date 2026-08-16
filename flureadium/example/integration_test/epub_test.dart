import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flureadium_example/main.dart' as app;

import 'helpers/pump_until.dart';
import 'helpers/reader_status.dart';

Future<void> _waitForReader(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () => find.byType(ReadiumReaderWidget).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 15),
  );
}

void _navigationTests(String assetLabel, String Function() openButtonLabel) {
  group('navigation ($assetLabel)', () {
    setUp(() async {});

    tearDown(() async {
      await Flureadium().closePublication();
    });

    testWidgets('opens and shows reader widget', (tester) async {
      app.main();
      await _waitForReader(tester);
      if (openButtonLabel() != 'default') {
        await tester.tap(find.text(openButtonLabel()));
        await _waitForReader(tester);
      }
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('the load cover tracks reader status', (tester) async {
      app.main();
      await _waitForReader(tester);
      if (openButtonLabel() != 'default') {
        await tester.tap(find.text(openButtonLabel()));
        await _waitForReader(tester);
      }

      final cover = find.byKey(const Key('reader-loading-cover'));

      // Sampled on every pump: covered exactly while the reader is not ready.
      final becameReady = await pumpUntil(tester, () {
        final ready = readerStatus(tester) == 'ready';
        expect(cover.evaluate().isNotEmpty, !ready);
        return ready;
      }, timeout: const Duration(seconds: 30));

      expect(becameReady, isTrue, reason: 'reader never reported ready');
    });

    testWidgets('navigate left and right', (tester) async {
      app.main();
      await _waitForReader(tester);
      if (openButtonLabel() != 'default') {
        await tester.tap(find.text(openButtonLabel()));
        await _waitForReader(tester);
      }
      await tester.tap(find.text('←'));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('→'));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('DartSkip+ does not crash', (tester) async {
      app.main();
      await _waitForReader(tester);
      if (openButtonLabel() != 'default') {
        await tester.tap(find.text(openButtonLabel()));
        await _waitForReader(tester);
      }
      await tester.tap(find.text('DartSkip+'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('DartSkip- does not crash', (tester) async {
      app.main();
      await _waitForReader(tester);
      if (openButtonLabel() != 'default') {
        await tester.tap(find.text(openButtonLabel()));
        await _waitForReader(tester);
      }
      await tester.tap(find.text('DartSkip-'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('EPUB', () {
    tearDown(() async {
      await Flureadium().closePublication();
    });

    testWidgets('app auto-opens EPUB and shows reader widget', (tester) async {
      app.main();
      // pumpAndSettle can hang when a PlatformView (WebView) keeps scheduling
      // frames. Poll for the reader widget with bounded pump loops instead.
      await _waitForReader(tester);
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('long press on reader does not crash', (tester) async {
      app.main();
      await _waitForReader(tester);

      final reader = find.byType(ReadiumReaderWidget);
      expect(reader, findsOneWidget);

      await tester.longPressAt(tester.getCenter(reader));
      await tester.pump(const Duration(seconds: 1));

      expect(reader, findsOneWidget);
    });

    testWidgets('Go To Saved does not crash', (tester) async {
      app.main();
      await _waitForReader(tester);
      await tester.tap(find.text('Go To Saved'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('apply night theme preferences', (tester) async {
      app.main();
      await _waitForReader(tester);
      await tester.tap(find.text('Night'));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('apply decoration to current locator', (tester) async {
      app.main();
      await _waitForReader(tester);
      await tester.tap(find.text('Highlight'));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    // Regression: the plugin owns the single "error" channel, so a Dart
    // subscription to onErrorEvent must survive a reader-view dispose. Before
    // the ownership refactor, closing a reader view end-streamed the
    // subscription (and clobbered any plugin-scope error sink).
    testWidgets('onErrorEvent subscription survives reader-view dispose', (
      tester,
    ) async {
      var streamClosed = false;
      final sub = Flureadium().onErrorEvent.listen(
        (_) {},
        onDone: () => streamClosed = true,
      );

      app.main();
      await _waitForReader(tester);

      // Dispose the reader — the old bug end-streamed the subscription here.
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(seconds: 3));

      expect(
        streamClosed,
        isFalse,
        reason: 'onErrorEvent must not be end-streamed by a view dispose',
      );

      await sub.cancel();
    });

    testWidgets('close publication removes reader widget', (tester) async {
      app.main();
      await _waitForReader(tester);
      await tester.tap(find.text('Close'));
      // After close, _publication is null and CircularProgressIndicator keeps
      // animating — pumpAndSettle would never settle. Poll instead: the widget
      // goes away when the native close completes, which is not a fixed cost.
      await pumpUntil(
        tester,
        () => find.byType(ReadiumReaderWidget).evaluate().isEmpty,
        timeout: const Duration(seconds: 15),
      );
      expect(find.byType(ReadiumReaderWidget), findsNothing);
    });

    testWidgets('Load Only does not crash', (tester) async {
      app.main();
      await _waitForReader(tester);
      await tester.tap(find.text('Load Only'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      // no crash = pass
    });
  });

  // Navigation smoke tests run with both fixtures to catch regressions.
  // The hierarchical fixture has Part I → [Ch1, Ch2, Ch3] and
  // Part II → Section 1 → [Ch4, Ch5], verifying that flattenToc-based skip
  // navigation works with multi-level TOC structures.
  _navigationTests('moby_dick', () => 'default');
  _navigationTests('hierarchical_toc', () => 'Open Hierarchical');
}
