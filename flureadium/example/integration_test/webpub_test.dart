import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flureadium_example/main.dart' as app;

import 'helpers/pump_until.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Fetches readium.org over the public internet, which GitHub-hosted Android
  // emulators cannot reach. The tag is what CI selects on, so the requirement
  // lives in the test that has it instead of in a list of file names. It sits
  // on the test rather than a group because flutter_test's `group` drops
  // `tags`.
  testWidgets('opens remote WebPub manifest and shows reader widget', (
    tester,
  ) async {
    app.main();
    // pumpAndSettle would never settle: CircularProgressIndicator keeps
    // animating while the EPUB auto-open runs (and fails on web). Use pump
    // with a fixed duration instead.
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Open WebPub'));
    // Poll for the reader widget — remote manifest fetch typically completes
    // in 2-5s. Ceiling 15s (was 10s fixed) for slow/flaky networks.
    await pumpUntil(
      tester,
      () => find.byType(ReadiumReaderWidget).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
    );
    expect(find.byType(ReadiumReaderWidget), findsOneWidget);
  }, tags: 'network');
}
