import 'package:flureadium/flureadium.dart';
import 'package:flureadium_example/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/publication_latch.dart';
import 'helpers/pump_until.dart';

/// The remote manifest's own `metadata.identifier`. The remote publication and
/// the bundled fixture are both titled "Moby-Dick", so the identifier is the
/// only thing that tells them apart.
const _webPubIdentifier = 'urn:isbn:9780000000001';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Fetches readium.org over the public internet, which GitHub-hosted Android
  // emulators cannot reach. The tag is what CI selects on, so the requirement
  // lives in the test that has it instead of in a list of file names. It sits
  // on the test rather than a group because flutter_test's `group` drops
  // `tags`.
  testWidgets('opens the remote WebPub manifest, not the publication already '
      'on screen', (tester) async {
    app.main();
    // pumpAndSettle would never settle: CircularProgressIndicator keeps
    // animating while the EPUB auto-open runs (and fails on web). Use pump
    // with a fixed duration instead.
    await tester.pump(const Duration(seconds: 2));
    // The app auto-opens the bundled EPUB in initState, so let that open land
    // before sampling the counter. Otherwise a slow fixture open lands after
    // the tap and satisfies the wait below on the wrong publication. Inside
    // all_tests.dart the counter is already past zero and this returns at once.
    await pumpUntil(
      tester,
      () => openGeneration(tester) > 0,
      timeout: const Duration(seconds: 30),
    );

    final generationBefore = openGeneration(tester);
    await tester.tap(find.text('Open WebPub'));

    // The counter rises only inside _resetPublicationLatches, which a failed
    // open never reaches — so unlike "a reader widget exists", this cannot be
    // satisfied by the publication the app opened at launch. The error latch
    // is the other exit: a failed open records it, and stopping on it gets the
    // assertion below its message instead of a 15-second wait for a bump that
    // is never coming.
    await pumpUntil(
      tester,
      () =>
          openGeneration(tester) > generationBefore ||
          openError(tester).isNotEmpty,
      timeout: const Duration(seconds: 15),
    );

    expect(
      openError(tester),
      isEmpty,
      reason: 'the WebPub open reported an error',
    );
    expect(
      openGeneration(tester),
      greaterThan(generationBefore),
      reason: 'no open completed after the Open WebPub tap',
    );
    expect(
      publicationIdentifier(tester),
      _webPubIdentifier,
      reason:
          'the reader is showing a different publication — the bundled fixture '
          'reports http://www.gutenberg.org/2701',
    );
    expect(find.byType(ReadiumReaderWidget), findsOneWidget);
  }, tags: 'network');
}
