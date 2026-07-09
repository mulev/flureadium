import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';

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

      expect(find.byType(ReadiumReaderWidget), findsOneWidget);

      await tester.tap(find.text('→'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('←'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('revisiting pages loads from cache without errors', (
      tester,
    ) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_visual.divina',
        reopenButton: 'Open DIVINA',
      );

      expect(find.byType(ReadiumReaderWidget), findsOneWidget);

      // Navigate forward two pages
      await tester.tap(find.text('→'));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('→'));
      await tester.pump(const Duration(seconds: 2));

      // Navigate back to previously visited pages (cache hit path on iOS)
      await tester.tap(find.text('←'));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('←'));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });
  });
}
