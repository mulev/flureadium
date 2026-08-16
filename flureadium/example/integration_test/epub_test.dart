import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flureadium_example/main.dart' as app;

import 'helpers/locator_latch.dart';
import 'helpers/pump_until.dart';
import 'helpers/reader_status.dart';

Future<void> _waitForReader(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () => find.byType(ReadiumReaderWidget).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 15),
  );
}

/// Pumps until [condition] holds, failing with [reason] when it never does.
///
/// [pumpUntil] reports a timeout in its return value, so every wait has to
/// assert that value or a never-satisfied condition passes silently.
Future<void> _expectEventually(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final satisfied = await pumpUntil(tester, condition, timeout: timeout);
  expect(satisfied, isTrue, reason: reason);
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

      // _waitForReader only asks whether a reader is mounted, and for the
      // non-default groups the previous publication's reader still is, carrying
      // its 'ready'. Wait for the open to reset the status or the first sample
      // below would end the test before the load it exists to watch.
      final loading = await pumpUntil(
        tester,
        () => readerStatus(tester) != 'ready',
        timeout: const Duration(seconds: 15),
      );
      expect(loading, isTrue, reason: 'the open never reset the reader status');

      // Sampled on every pump: covered exactly while the reader is loading.
      // 'error' and 'closed' are terminal, so the cover is gone there too.
      final becameReady = await pumpUntil(tester, () {
        final status = readerStatus(tester);
        expect(
          cover.evaluate().isNotEmpty,
          status.isEmpty || status == 'loading',
          reason: 'reader status was "$status"',
        );
        return status == 'ready';
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

      await _expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to navigate from',
      );
      final start = locatorHref(tester);

      // Forward first: on the opening resource a back-tap may legitimately
      // have nowhere to go, so only forward-then-back has a provable trip.
      await tester.tap(find.text('→'));
      await _expectEventually(
        tester,
        () => locatorHref(tester) != start,
        reason: 'the locator never left "$start" after →',
      );

      await tester.tap(find.text('←'));
      await _expectEventually(
        tester,
        () => locatorHref(tester) == start,
        reason: 'the locator never returned to "$start"',
      );
    });

    testWidgets('DartSkip+ advances the reader', (tester) async {
      app.main();
      await _waitForReader(tester);
      if (openButtonLabel() != 'default') {
        await tester.tap(find.text(openButtonLabel()));
        await _waitForReader(tester);
      }

      await _expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to skip from',
      );
      final before = locatorHref(tester);

      await tester.tap(find.text('DartSkip+'));
      await _expectEventually(
        tester,
        () => locatorHref(tester) != before,
        reason: 'DartSkip+ did not move the reader from "$before"',
      );
    });

    testWidgets('DartSkip- returns the reader', (tester) async {
      app.main();
      await _waitForReader(tester);
      if (openButtonLabel() != 'default') {
        await tester.tap(find.text(openButtonLabel()));
        await _waitForReader(tester);
      }

      await _expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to skip from',
      );
      final start = locatorHref(tester);

      // Both fixtures open on their first TOC entry, so a backward skip has
      // nowhere to land until a forward skip puts something behind us.
      await tester.tap(find.text('DartSkip+'));
      await _expectEventually(
        tester,
        () => locatorHref(tester) != start,
        reason: 'nothing to skip back from',
      );

      await tester.tap(find.text('DartSkip-'));
      await _expectEventually(
        tester,
        () => locatorHref(tester) == start,
        reason: 'DartSkip- did not return the reader to "$start"',
      );
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

    testWidgets('long press leaves the reader ready and error-free', (
      tester,
    ) async {
      app.main();
      await _waitForReader(tester);

      await _expectEventually(
        tester,
        () => readerStatus(tester) == 'ready',
        reason: 'reader never reported ready',
        timeout: const Duration(seconds: 30),
      );

      await tester.longPressAt(
        tester.getCenter(find.byType(ReadiumReaderWidget)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Key('audio-error') carries every onErrorEvent message, not just audio.
      final error =
          (tester.widget<Text>(find.byKey(const Key('audio-error'))).data ?? '')
              .replaceFirst('audio-error: ', '');
      expect(readerStatus(tester), equals('ready'));
      expect(error, isEmpty, reason: 'the long press surfaced "$error"');
    });

    testWidgets('Go To Saved returns to the saved position', (tester) async {
      app.main();
      await _waitForReader(tester);

      await _expectEventually(
        tester,
        () => savedLocatorHref(tester).isNotEmpty,
        reason: 'nothing was ever saved',
      );
      final saved = savedLocatorHref(tester);

      await tester.tap(find.text('→'));
      await _expectEventually(
        tester,
        () => locatorHref(tester) != saved,
        reason: 'could not navigate away from "$saved"',
      );

      await tester.tap(find.text('Go To Saved'));
      await _expectEventually(
        tester,
        () => locatorHref(tester) == saved,
        reason: 'Go To Saved did not return to "$saved"',
      );
    });

    // The night theme itself cannot be verified from Dart: setEPUBPreferences
    // returns Future<void> and no channel reports the active theme back
    // (flureadium-8om). This case asserts the contract that is observable and
    // has regressed before — applying preferences must not reset the reader or
    // lose the position.
    testWidgets('applying night preferences keeps status and position', (
      tester,
    ) async {
      app.main();
      await _waitForReader(tester);

      await _expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no locator before applying preferences',
      );
      final before = locatorHref(tester);

      await tester.tap(find.text('Night'));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(readerStatus(tester), equals('ready'));
      expect(locatorHref(tester), equals(before));
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

    testWidgets('Load Only loads a publication without opening a reader', (
      tester,
    ) async {
      app.main();
      await _waitForReader(tester);

      // load must not mount a reader, and that is only observable from a
      // state where none is mounted — so close the auto-opened one first.
      await tester.tap(find.text('Close'));
      await pumpUntil(
        tester,
        () => find.byType(ReadiumReaderWidget).evaluate().isEmpty,
        timeout: const Duration(seconds: 15),
      );

      String loadedTitle() {
        final text =
            tester.widget<Text>(find.byKey(const Key('loaded-title'))).data ??
            '';
        return text.replaceFirst('loaded-title: ', '');
      }

      await tester.tap(find.text('Load Only'));
      await _expectEventually(
        tester,
        () => loadedTitle().isNotEmpty,
        reason: 'loadPublication never reported a title',
      );
      expect(find.byType(ReadiumReaderWidget), findsNothing);
    });
  });

  // Navigation smoke tests run with both fixtures to catch regressions.
  // The hierarchical fixture has Part I → [Ch1, Ch2, Ch3] and
  // Part II → Section 1 → [Ch4, Ch5], verifying that flattenToc-based skip
  // navigation works with multi-level TOC structures.
  _navigationTests('moby_dick', () => 'default');
  _navigationTests('hierarchical_toc', () => 'Open Hierarchical');
}
