@Tags(['native'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flureadium/flureadium.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/pump_until.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Boots (or reuses) the app on the TTS EPUB before each test. Reuse reopens
  // via 'Open EPUB', which resets TTS/audio state so tests stay isolated.
  Future<void> showEpub(WidgetTester tester) => ensureAppShowing(
    tester,
    initialAsset: 'assets/pubs/moby_dick.epub',
    reopenButton: 'Open EPUB',
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

  // Every test here needs a real TTS engine, so every one carries the `native`
  // tag CI excludes. The tag sits on each test because flutter_test's `group`
  // drops `tags`, and the library-level `@Tags` above is ignored once an
  // aggregator imports this file rather than running it — which is what CI
  // does. Going through the wrapper keeps a new test tagged by construction.
  void ttsTest(String description, WidgetTesterCallback body) =>
      testWidgets(description, body, tags: 'native');

  group('EPUB TTS', () {
    tearDown(() async {
      // Stop TTS playback but leave the publication open. The next test's
      // ensureAppShowing reopens via the Open button, switching publications the
      // way the app does. Closing the container here under a still-mounted reader
      // is not an app flow and races the Android WebView (flureadium-i0s).
      await Flureadium().stop();
    });

    ttsTest('ttsGetSystemVoices returns voices before TTS is enabled', (
      tester,
    ) async {
      await showEpub(tester);
      // Call ttsGetSystemVoices before enabling TTS — should work without a navigator.
      final flureadium = Flureadium();
      final voices = await flureadium.ttsGetSystemVoices();
      expect(voices, isNotEmpty);
      expect(voices.first.identifier, isNotEmpty);
      expect(voices.first.language, isNotEmpty);
    });

    ttsTest('TTS enable makes sentence nav buttons appear', (tester) async {
      await showEpub(tester);
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

    ttsTest('ttsCanSpeak returns true — TTS On enables without snackbar', (
      tester,
    ) async {
      await showEpub(tester);
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

    ttsTest('tts pause then resume restores playing state', (tester) async {
      await showEpub(tester);
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

    ttsTest('tts next sentence does not crash', (tester) async {
      await showEpub(tester);
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

    ttsTest('tts previous sentence does not crash', (tester) async {
      await showEpub(tester);
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

    ttsTest('tts voice cycling does not crash', (tester) async {
      await showEpub(tester);
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

    ttsTest('tts disable and re-enable does not crash', (tester) async {
      await showEpub(tester);
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

    ttsTest('tts disable, navigate to next page, re-enable does not crash', (
      tester,
    ) async {
      await showEpub(tester);
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
      await waitForText(tester, 'TTS On', timeout: const Duration(seconds: 5));
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
    });

    ttsTest('tts off hides sentence nav buttons', (tester) async {
      await showEpub(tester);
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
      // The button clears only once `stop()` resolves (main.dart:550-562), and
      // that call is racing the `play()` still in flight from the enable above —
      // waitForText returns at the setState that precedes it. Both serialize on
      // the Android main thread, so a fixed sleep here is a coin flip. Poll.
      await pumpUntil(
        tester,
        () => find.text('Prev Sentence').evaluate().isEmpty,
        timeout: const Duration(seconds: 30),
      );
      expect(find.text('Prev Sentence'), findsNothing);
      expect(find.text('TTS On'), findsOneWidget);
    });
  });
}
