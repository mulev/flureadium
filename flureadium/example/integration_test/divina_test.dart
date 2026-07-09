import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flureadium_example/main.dart' as app;

import 'helpers/pump_until.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('DIVINA', () {
    tearDown(() async {
      final flureadium = Flureadium();
      await flureadium.closePublication();
    });

    testWidgets('app auto-opens DIVINA and shows reader widget', (
      tester,
    ) async {
      app.main(initialAsset: 'assets/pubs/sample_visual.divina');
      await pumpUntil(
        tester,
        () => find.byType(ReadiumReaderWidget).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15),
      );

      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('navigate left and right in DIVINA reader', (tester) async {
      app.main(initialAsset: 'assets/pubs/sample_visual.divina');
      await pumpUntil(
        tester,
        () => find.byType(ReadiumReaderWidget).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15),
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
      app.main(initialAsset: 'assets/pubs/sample_visual.divina');
      await pumpUntil(
        tester,
        () => find.byType(ReadiumReaderWidget).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15),
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
