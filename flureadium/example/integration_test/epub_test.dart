import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/locator_latch.dart';
import 'helpers/expect_eventually.dart';
import 'helpers/pump_until.dart';
import 'helpers/reader_status.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('EPUB', () {
    // As in epub_navigation_test.dart: every test opens its own EPUB, so no case
    // asserts against a publication another suite left mounted.
    Future<void> showEpub(WidgetTester tester) => ensureAppShowing(
      tester,
      initialAsset: 'assets/pubs/moby_dick.epub',
      reopenButton: 'Open EPUB',
      openAfterColdBoot: true,
    );

    tearDown(() async {
      await Flureadium().closePublication();
    });

    testWidgets('opens the EPUB and shows the reader widget', (tester) async {
      await showEpub(tester);
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('long press leaves the reader ready and error-free', (
      tester,
    ) async {
      await showEpub(tester);

      await expectEventually(
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
      await showEpub(tester);

      await expectEventually(
        tester,
        () => savedLocatorHref(tester).isNotEmpty,
        reason: 'nothing was ever saved',
      );
      final saved = savedLocatorHref(tester);

      await tester.tap(find.text('→'));
      await expectEventually(
        tester,
        () => locatorHref(tester) != saved,
        reason: 'could not navigate away from "$saved"',
      );

      await tester.tap(find.text('Go To Saved'));
      await expectEventually(
        tester,
        () => locatorHref(tester) == saved,
        reason: 'Go To Saved did not return to "$saved"',
      );
    });

    // Two taps, not one: `_savedLocator` is the first locator of the open, so
    // by the time a test can tap, the reader may already be further down the
    // same resource — making the first tap a legitimate scroll. The second tap
    // asks the reader to restore the position it is provably already on, which
    // is the input the 1% progression skip guards. Nothing may move there.
    testWidgets('Go To Saved twice keeps the reported progression', (
      tester,
    ) async {
      await showEpub(tester);

      await expectEventually(
        tester,
        () => savedLocatorHref(tester).isNotEmpty,
        reason: 'nothing was ever saved',
      );
      final saved = savedLocatorHref(tester);

      await tester.tap(find.text('Go To Saved'));
      await expectEventually(
        tester,
        () => locatorHref(tester) == saved,
        reason: 'Go To Saved did not reach "$saved"',
      );
      final before = locatorProgression(tester);
      final eventsBefore = locatorEvents(tester);

      await tester.tap(find.text('Go To Saved'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(locatorHref(tester), saved);
      expect(
        locatorEvents(tester),
        greaterThan(eventsBefore),
        reason:
            'no locator was reported after the second tap, so this case '
            'would pass on a dead stream',
      );

      // Conditional because a resource may report no progression at all; the
      // locator-events assertion above is what keeps that from turning this
      // case vacuous.
      final after = locatorProgression(tester);
      if (before != null && after != null) {
        expect(
          (after - before).abs(),
          lessThan(0.01),
          reason: 'restoring the current position moved it: $before -> $after',
        );
      }
    });

    // The night theme itself cannot be verified from Dart: setEPUBPreferences
    // returns Future<void> and no channel reports the active theme back
    // (flureadium-8om). This case asserts the contract that is observable and
    // has regressed before — applying preferences must not reset the reader or
    // lose the position.
    testWidgets('applying night preferences keeps status and position', (
      tester,
    ) async {
      await showEpub(tester);

      await expectEventually(
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

      await showEpub(tester);

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
      await showEpub(tester);
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
      await showEpub(tester);

      // load must not mount a reader, and that is only observable from a
      // state where none is mounted — so close the reader opened above first.
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
      await expectEventually(
        tester,
        () => loadedTitle().isNotEmpty,
        reason: 'loadPublication never reported a title',
      );
      expect(find.byType(ReadiumReaderWidget), findsNothing);
    });
  });
}
