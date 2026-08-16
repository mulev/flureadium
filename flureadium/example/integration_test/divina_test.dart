import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/locator_latch.dart';
import 'helpers/pump_until.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('DIVINA', () {
    // No tearDown close: the next test's ensureAppShowing switches publications
    // via the Open button, mirroring the app. Closing the container under a
    // still-mounted reader is not an app flow (flureadium-i0s).

    testWidgets('app auto-opens DIVINA and shows reader widget', (
      tester,
    ) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_visual.divina',
        reopenButton: 'Open DIVINA',
      );

      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('navigate left and right in DIVINA reader', (tester) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_visual.divina',
        reopenButton: 'Open DIVINA',
      );

      final delivered = await pumpUntil(
        tester,
        () => locatorHref(tester).isNotEmpty,
        timeout: const Duration(seconds: 15),
      );
      expect(delivered, isTrue, reason: 'no starting page locator');
      final first = locatorHref(tester);

      await tester.tap(find.text('→'));
      await _nextPage(tester, from: first);

      await tester.tap(find.text('←'));
      final returned = await pumpUntil(
        tester,
        () => locatorHref(tester) == first,
        timeout: const Duration(seconds: 15),
      );
      expect(returned, isTrue, reason: 'the page never returned to "$first"');
    });

    testWidgets('revisiting pages loads from cache without errors', (
      tester,
    ) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_visual.divina',
        reopenButton: 'Open DIVINA',
      );

      final delivered = await pumpUntil(
        tester,
        () => locatorHref(tester).isNotEmpty,
        timeout: const Duration(seconds: 15),
      );
      expect(delivered, isTrue, reason: 'no starting page locator');
      final first = locatorHref(tester);

      await tester.tap(find.text('→'));
      final second = await _nextPage(tester, from: first);
      await tester.tap(find.text('→'));
      final third = await _nextPage(tester, from: second);

      // Back to pages already rendered — the iOS cache-hit path.
      await tester.tap(find.text('←'));
      final backToSecond = await pumpUntil(
        tester,
        () => locatorHref(tester) == second,
        timeout: const Duration(seconds: 15),
      );
      expect(backToSecond, isTrue, reason: 'no cache hit for "$second"');

      await tester.tap(find.text('←'));
      final backToFirst = await pumpUntil(
        tester,
        () => locatorHref(tester) == first,
        timeout: const Duration(seconds: 15),
      );
      expect(backToFirst, isTrue, reason: 'no cache hit for "$first"');

      expect(
        third,
        isNot(equals(first)),
        reason: 'the forward taps never left page one',
      );
      expect(
        _errorLatch(tester),
        isEmpty,
        reason: 'an error surfaced during the revisit',
      );
    });
  });
}

/// Waits for the locator latch to leave [from] and returns the href that
/// replaced it. Fails the test if the page never moved.
Future<String> _nextPage(WidgetTester tester, {required String from}) async {
  final moved = await pumpUntil(
    tester,
    () => locatorHref(tester) != from,
    timeout: const Duration(seconds: 15),
  );
  expect(moved, isTrue, reason: 'the page never left "$from"');
  return locatorHref(tester);
}

/// Reads the keyed error latch the example fills from onErrorEvent — the
/// channel `ReaderCoroutineFailure` reports image-navigator failures on.
/// The text is `audio-error: <message>`; empty until an error surfaces.
String _errorLatch(WidgetTester tester) =>
    (tester.widget<Text>(find.byKey(const Key('audio-error'))).data ?? '')
        .replaceFirst('audio-error: ', '');
