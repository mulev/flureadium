import 'dart:io';

import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/pump_until.dart';
import 'helpers/reader_status.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Error handling', () {
    late Flureadium flureadium;

    setUp(() {
      flureadium = Flureadium();
    });

    tearDown(() async {
      await flureadium.closePublication();
    });

    testWidgets('opening a corrupted file throws ReadiumException', (
      tester,
    ) async {
      // Write garbage bytes to a temp file disguised as an EPUB.
      final tmp = File(
        '${Directory.systemTemp.path}/'
        '${DateTime.now().millisecondsSinceEpoch}_corrupted.epub',
      );
      await tmp.writeAsBytes([0x00, 0x01, 0x02, 0x03]);

      // openPublication must surface a ReadiumException rather than
      // crashing with a codec error (IllegalArgumentException).
      expect(
        () => flureadium.openPublication(tmp.path),
        throwsA(isA<ReadiumException>()),
      );
    });

    testWidgets('opening a non-existent file throws ReadiumException', (
      tester,
    ) async {
      final bogusPath =
          '${Directory.systemTemp.path}/nonexistent_${DateTime.now().millisecondsSinceEpoch}.epub';

      expect(
        () => flureadium.openPublication(bogusPath),
        throwsA(isA<ReadiumException>()),
      );
    });
  });

  group('Reader failure', () {
    testWidgets(
      'a failed native enable reports instead of killing the app',
      (tester) async {
        await ensureAppShowing(
          tester,
          initialAsset: 'assets/pubs/moby_dick.epub',
          reopenButton: 'Open EPUB',
        );

        // Closing natively leaves _publication pointing at the same Dart object,
        // so the remount is what asks native to enable a publication it has
        // already closed.
        await tester.tap(find.text('Close Native Only'));
        // Not pumpAndSettle: the load cover's spinner is on screen from the
        // moment the status leaves 'ready', and an indeterminate
        // CircularProgressIndicator schedules frames forever. Wait for the
        // close to land instead.
        final closed = await pumpUntil(
          tester,
          () => readerStatus(tester) == 'closed',
          timeout: const Duration(seconds: 15),
        );
        expect(
          closed,
          isTrue,
          reason: 'reader status was "${readerStatus(tester)}"',
        );
        await tester.tap(find.text('Remount Reader'));

        await pumpUntil(
          tester,
          () => readerStatus(tester) == 'error',
          timeout: const Duration(seconds: 15),
        );

        // Making this assertion at all is half the proof: the failure used to
        // take the process down, and every later test reported "did not
        // complete".
        expect(
          readerStatus(tester),
          'error',
          reason: 'reader status was "${readerStatus(tester)}"',
        );

        // Restore a working reader for the groups that follow. Opening hands the
        // widget a different Publication instance, so didUpdateWidget rebuilds
        // the native view by itself — a second remount tap would only throw away
        // the view that just came up.
        await tester.tap(find.text('Open EPUB'));
        await pumpUntil(
          tester,
          () => readerStatus(tester) == 'ready',
          timeout: const Duration(seconds: 30),
        );
        expect(
          readerStatus(tester),
          'ready',
          reason: 'the reader must come back for the groups that follow',
        );
        // Skipped on iOS because the failure this forces is Android-specific:
        // with no publication open, ReadiumReaderViewFactory.create falls through
        // to ReadiumReaderView, which builds an empty EPUB navigator instead of
        // throwing, so the status would go to ready. Not an iOS bug.
      },
      skip: Platform.isIOS,
    );
  });
}
