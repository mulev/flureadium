import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/pump_until.dart';

/// Hosting an audio-only publication, up to the point where playback starts.
///
/// Separate from `audiobook_test.dart` because of what it does *not* need: no
/// player is built until `audioEnable`, which only Audio Play drives. That
/// keeps these two off the hardware-audio path, so they run in Android CI —
/// where the rest of the audiobook suite is excluded, and where the readiness
/// contract below would otherwise have no coverage at all.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Reads the keyed latch the example updates from onReaderStatusChanged.
  // The text is 'reader-status: <name>'; empty until a status arrives.
  String readerStatus(WidgetTester tester) =>
      (tester.widget<Text>(find.byKey(const Key('reader-status'))).data ?? '')
          .replaceFirst('reader-status: ', '');

  Future<void> showAudiobook(WidgetTester tester) => ensureAppShowing(
    tester,
    initialAsset: 'assets/pubs/38533.audiobook',
    reopenButton: 'Open AudioBook',
    openAfterColdBoot: true,
  );

  group('audio-only host', () {
    tearDownAll(() async {
      await Flureadium().stop();
    });

    testWidgets('opens an audiobook and shows the reader widget', (
      tester,
    ) async {
      await showAudiobook(tester);
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('reports reader status ready', (tester) async {
      // The host's only readiness signal for an audio publication: there is no
      // navigator to report a first page. Android has answered this since
      // flureadium-3wd; iOS answers it since audio-only publications stopped
      // being routed into the EPUB navigator (flureadium-5wu).
      await showAudiobook(tester);

      final ready = await pumpUntil(
        tester,
        () => readerStatus(tester) == 'ready',
        timeout: const Duration(seconds: 15),
      );

      expect(
        ready,
        isTrue,
        reason: 'reader status was "${readerStatus(tester)}"',
      );
    });
  });
}
