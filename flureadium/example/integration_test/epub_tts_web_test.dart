@Tags(['web'])
library;

import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flureadium_example/main.dart' as app;

/// Web TTS integration tests.
///
/// Packed EPUB files cannot be served via HTTP URL (web limitation), so the
/// default auto-open of moby_dick.epub fails silently. Each test taps
/// "Open WebPub" first to load a remote manifest that the web navigator
/// can handle.
///
/// On web, [WidgetTester.pump] processes a single Flutter frame per call.
/// JS operations (manifest fetch, navigator load) need the browser event
/// loop to run between frames. We pump many short frames instead of one
/// long frame so the browser can service JS promises between iterations.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group(
    'EPUB TTS — Web',
    () {
      tearDown(() async {
        final flureadium = Flureadium();
        await flureadium.stop();
        await flureadium.closePublication();
      });

      testWidgets(
        'ttsCanSpeak returns true — TTS On enables without snackbar',
        (tester) async {
          app.main();
          await tester.pump(const Duration(seconds: 2));
          await tester.tap(find.text('Open WebPub'));
          // Pump many frames so the browser event loop can process JS promises
          // (manifest fetch, navigator init, setNav callback).
          for (int i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 500));
          }
          await tester.tap(find.text('TTS On'));
          for (int i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 500));
          }
          expect(find.text('TTS Off'), findsOneWidget);
        },
      );

      testWidgets('ttsGetAvailableVoices — voice counter shown after enable', (
        tester,
      ) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.text('Open WebPub'));
        for (int i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.tap(find.text('TTS On'));
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.textContaining('Voice'), findsOneWidget);
      });

      testWidgets('tts enable then stop does not throw', (tester) async {
        app.main();
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.text('Open WebPub'));
        for (int i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.tap(find.text('TTS On'));
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.tap(find.text('TTS Off'));
        for (int i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.text('TTS On'), findsOneWidget);
      });
    },
    skip:
        'Web-reader TTS is WIP (navigator init relies on unfinished onErrorEvent/applyDecorations); un-skip when web TTS lands.',
  );
}
