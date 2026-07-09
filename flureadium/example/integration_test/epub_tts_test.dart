@Tags(['native'])
library;

import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flureadium_example/main.dart' as app;

import 'helpers/pump_until.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // pumpAndSettle can hang when a PlatformView (WebView) keeps scheduling
  // frames. Poll for the reader widget instead. 15s ceiling matches original.
  Future<void> waitForReader(WidgetTester tester) => pumpUntil(
    tester,
    () => find.byType(ReadiumReaderWidget).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 15),
  );

  // Polls for a text label to appear, keeping each call's own ceiling.
  Future<void> waitForText(
    WidgetTester tester,
    String label, {
    required Duration timeout,
  }) => pumpUntil(
    tester,
    () => find.text(label).evaluate().isNotEmpty,
    timeout: timeout,
  );

  group('EPUB TTS', () {
    tearDown(() async {
      final flureadium = Flureadium();
      await flureadium.stop();
      await flureadium.closePublication();
    });

    testWidgets('ttsGetSystemVoices returns voices before TTS is enabled', (
      tester,
    ) async {
      app.main();
      await waitForReader(tester);
      // Call ttsGetSystemVoices before enabling TTS — should work without a navigator.
      final flureadium = Flureadium();
      final voices = await flureadium.ttsGetSystemVoices();
      expect(voices, isNotEmpty);
      expect(voices.first.identifier, isNotEmpty);
      expect(voices.first.language, isNotEmpty);
    });

    testWidgets('TTS enable makes sentence nav buttons appear', (tester) async {
      app.main();
      await waitForReader(tester);
      await tester.tap(find.text('TTS On'));
      // Poll every tick — iOS TTS starts in ~5s; Android emulator can take ~30s.
      // Ceiling kept at 60s to match the original safe upper bound.
      await waitForText(
        tester,
        'Prev Sentence',
        timeout: const Duration(seconds: 60),
      );
      expect(find.text('Prev Sentence'), findsOneWidget);
      expect(find.text('Next Sentence'), findsOneWidget);
      // Let in-flight native play() settle before tearDown cancels the coroutine.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('ttsCanSpeak returns true — TTS On enables without snackbar', (
      tester,
    ) async {
      app.main();
      await waitForReader(tester);
      await tester.tap(find.text('TTS On'));
      // Poll for readiness — TTS On flips to 'TTS Off' once enabled. Break early
      // instead of blindly sleeping the 60s worst-case ceiling.
      await waitForText(
        tester,
        'TTS Off',
        timeout: const Duration(seconds: 60),
      );
      expect(find.text('TTS Off'), findsOneWidget);
    });

    testWidgets('tts pause then resume restores playing state', (tester) async {
      app.main();
      await waitForReader(tester);
      await tester.tap(find.text('TTS On'));
      // Poll for 'Pause TTS' — requires _ttsPlaybackState == playing, which
      // arrives via the onTimebasedPlayerStateChanged stream after play().
      await waitForText(
        tester,
        'Pause TTS',
        timeout: const Duration(seconds: 60),
      );
      expect(find.text('Pause TTS'), findsOneWidget);
      await tester.tap(find.text('Pause TTS'));
      await waitForText(
        tester,
        'Resume TTS',
        timeout: const Duration(seconds: 5),
      );
      expect(find.text('Resume TTS'), findsOneWidget);
      await tester.tap(find.text('Resume TTS'));
      await waitForText(
        tester,
        'Pause TTS',
        timeout: const Duration(seconds: 5),
      );
      expect(find.text('Pause TTS'), findsOneWidget);
      // Let in-flight native resume/play() settle before tearDown cancels the coroutine.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('tts next sentence does not crash', (tester) async {
      app.main();
      await waitForReader(tester);
      await tester.tap(find.text('TTS On'));
      // Poll for the sentence nav button — it appears once TTS is enabled.
      // Break early instead of blindly sleeping the 60s worst-case ceiling.
      await waitForText(
        tester,
        'Next Sentence',
        timeout: const Duration(seconds: 60),
      );
      await tester.tap(find.text('Next Sentence'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('TTS Off'), findsOneWidget);
    });

    testWidgets('tts previous sentence does not crash', (tester) async {
      app.main();
      await waitForReader(tester);
      await tester.tap(find.text('TTS On'));
      // Poll for the sentence nav button — it appears once TTS is enabled.
      // Break early instead of blindly sleeping the 60s worst-case ceiling.
      await waitForText(
        tester,
        'Prev Sentence',
        timeout: const Duration(seconds: 60),
      );
      await tester.tap(find.text('Prev Sentence'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('TTS Off'), findsOneWidget);
    });

    testWidgets('tts voice cycling does not crash', (tester) async {
      app.main();
      await waitForReader(tester);
      await tester.tap(find.text('TTS On'));
      // Poll for the Voice button. It renders only after ttsGetAvailableVoices()
      // resolves — which lags the 'TTS Off' flip by play() + a voices fetch that
      // is slow on the Android emulator. Waiting on 'TTS Off' would break too
      // early; wait on the button this test actually needs. 60s ceiling retained.
      await pumpUntil(
        tester,
        () => find.textContaining('Voice').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );
      final voiceButton = find.textContaining('Voice');
      expect(voiceButton, findsOneWidget);
      await tester.tap(voiceButton);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('TTS Off'), findsOneWidget);
    });

    testWidgets('tts disable and re-enable does not crash', (tester) async {
      app.main();
      await waitForReader(tester);
      // Enable TTS
      await tester.tap(find.text('TTS On'));
      await waitForText(
        tester,
        'Prev Sentence',
        timeout: const Duration(seconds: 60),
      );
      expect(find.text('TTS Off'), findsOneWidget);

      // Advance one sentence
      await tester.tap(find.text('Next Sentence'));
      await tester.pump(const Duration(seconds: 2));

      // Disable TTS
      await tester.tap(find.text('TTS Off'));
      await waitForText(tester, 'TTS On', timeout: const Duration(seconds: 5));
      expect(find.text('TTS On'), findsOneWidget);

      // Re-enable TTS (should use saved locator)
      await tester.tap(find.text('TTS On'));
      await waitForText(
        tester,
        'Prev Sentence',
        timeout: const Duration(seconds: 60),
      );
      expect(find.text('TTS Off'), findsOneWidget);
      expect(find.text('Prev Sentence'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets(
      'tts disable, navigate to next page, re-enable does not crash',
      (tester) async {
        app.main();
        await waitForReader(tester);
        // Enable TTS
        await tester.tap(find.text('TTS On'));
        await waitForText(
          tester,
          'Prev Sentence',
          timeout: const Duration(seconds: 60),
        );
        expect(find.text('TTS Off'), findsOneWidget);

        // Advance one sentence so TTS has a locator to save
        await tester.tap(find.text('Next Sentence'));
        await tester.pump(const Duration(seconds: 2));

        // Disable TTS
        await tester.tap(find.text('TTS Off'));
        await waitForText(
          tester,
          'TTS On',
          timeout: const Duration(seconds: 5),
        );
        expect(find.text('TTS On'), findsOneWidget);

        // Navigate to next page — this changes the reader locator,
        // triggering the navigation-aware re-enable path (fromLocator: null).
        await tester.tap(find.text('→'));
        // Wait for page turn to complete and locator to update.
        await tester.pump(const Duration(seconds: 3));

        // Re-enable TTS — should start from current (navigated-to) position.
        // The native suppression logic prevents backward scrolling to the
        // utterance's CSS selector on the previous page.
        await tester.tap(find.text('TTS On'));
        await waitForText(
          tester,
          'Prev Sentence',
          timeout: const Duration(seconds: 60),
        );
        expect(find.text('TTS Off'), findsOneWidget);
        expect(find.text('Prev Sentence'), findsOneWidget);

        // Let in-flight native play() settle before tearDown.
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets('tts off hides sentence nav buttons', (tester) async {
      app.main();
      await waitForReader(tester);
      await tester.tap(find.text('TTS On'));
      // Poll for the sentence nav button — it appears once TTS is enabled.
      // Break early instead of blindly sleeping the 60s worst-case ceiling.
      await waitForText(
        tester,
        'Prev Sentence',
        timeout: const Duration(seconds: 60),
      );
      expect(find.text('Prev Sentence'), findsOneWidget);
      await tester.tap(find.text('TTS Off'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Prev Sentence'), findsNothing);
      expect(find.text('TTS On'), findsOneWidget);
    });
  });
}
