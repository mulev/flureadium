import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/extract_asset.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('CBZ', () {
    // No tearDown close: the next test's ensureAppShowing switches publications
    // via the Open button, mirroring the app. That was flureadium-i0s's answer
    // to a crash on closing under a mounted reader, and it only moved the crash
    // out of teardown. The same fault came back through the image navigator as
    // flureadium-pbc. The container guard fixes it properly now, so the last
    // test in this group runs that flow deliberately.

    testWidgets('app auto-opens CBZ and shows reader widget', (tester) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_comic.cbz',
        reopenButton: 'Open CBZ',
      );

      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('navigate left and right in CBZ reader', (tester) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_comic.cbz',
        reopenButton: 'Open CBZ',
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
        initialAsset: 'assets/pubs/sample_comic.cbz',
        reopenButton: 'Open CBZ',
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

    testWidgets(
      'Flureadium.goToLocator navigates CBZ reader (Bug 1 regression)',
      (tester) async {
        await ensureAppShowing(
          tester,
          initialAsset: 'assets/pubs/sample_comic.cbz',
          reopenButton: 'Open CBZ',
        );

        expect(find.byType(ReadiumReaderWidget), findsOneWidget);

        const locator = Locator(
          href: '003.jpg',
          type: 'image/jpeg',
          locations: Locations(position: 3, progression: 0.4),
        );
        final navigated = await Flureadium().goToLocator(locator);
        await tester.pump(const Duration(seconds: 1));

        expect(navigated, isTrue);
        expect(
          (await _waitForCbzReaderReady(tester, href: '003.jpg')).href,
          '003.jpg',
        );
      },
    );

    testWidgets(
      'extractPageThumbnail returns JPEG bytes for a valid CBZ page',
      (tester) async {
        await ensureAppShowing(
          tester,
          initialAsset: 'assets/pubs/sample_comic.cbz',
          reopenButton: 'Open CBZ',
        );

        final bytes = await Flureadium().extractPageThumbnail(
          '001.jpg',
          80,
          70,
        );

        expect(bytes, isNotNull);
        expect(bytes!.length, greaterThan(2));
        // JPEG magic bytes (SOI marker)
        expect(bytes[0], 0xFF);
        expect(bytes[1], 0xD8);
      },
    );

    testWidgets('extractPageThumbnail returns null for bogus href', (
      tester,
    ) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_comic.cbz',
        reopenButton: 'Open CBZ',
      );

      final bytes = await Flureadium().extractPageThumbnail(
        '/does/not/exist.jpg',
        80,
        70,
      );

      expect(bytes, isNull);
    });

    testWidgets('extractPageThumbnail returns null after closePublication', (
      tester,
    ) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_comic.cbz',
        reopenButton: 'Open CBZ',
      );

      await Flureadium().closePublication();
      final bytes = await Flureadium().extractPageThumbnail('001.jpg', 80, 70);

      expect(bytes, isNull);
    });

    // Regression test for the Dart-side href normalisation asymmetry fixed by
    // flureadium-djg. Before the fix, Publication.fromJson injected a leading
    // slash ('/001.jpg') while the Locator stream emitted the bare href
    // ('001.jpg'), so this assertion would have read '/001.jpg' == '001.jpg'
    // and failed.
    testWidgets('readingOrder hrefs match Locator stream format', (
      tester,
    ) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_comic.cbz',
        reopenButton: 'Open CBZ',
      );
      final locator = await _waitForCbzReaderReady(tester);

      final path = await extractAsset('assets/pubs/sample_comic.cbz');
      final pub = await Flureadium().loadPublication(path);

      expect(pub.readingOrder.first.href, equals(locator.href));
    });

    // Regression test for flureadium-pbc, and for flureadium-i0s before it,
    // which was the same fault reached through the EPUB WebView instead of the
    // image navigator. Closing a publication closes the zip container while
    // reads are still running against it. readium 3.1.2 catches ZipException
    // and IOException in FileZipContainer.Entry.read() but not the
    // IllegalStateException that ZipFile.ensureOpen throws, so that one escapes
    // the Try the method declares.
    //
    // Where it escaped to decided how bad it was. In the image navigator it
    // reached a coroutine with no Job in its context, so no handler could catch
    // it and Android killed the app. Through this path it lands in
    // dispatchGuarded instead and comes back as a PlatformException. Same
    // throw, same container, and this one can be forced rather than waited for.
    //
    // Each read captures the publication and then goes to the container, so
    // enough of them in flight guarantees some are mid-read when the close
    // lands. Without the guard those throw. With it they answer null, and the
    // Android logcat carries `Read after the container closed`.
    testWidgets('reads outliving closePublication fail soft, not fatal', (
      tester,
    ) async {
      // Three rounds. One round caught the unguarded build in one CI run out of
      // two, which is not good enough for a regression test that has to fail on
      // a build someone broke six months from now.
      for (var round = 0; round < 3; round++) {
        await ensureAppShowing(
          tester,
          initialAsset: 'assets/pubs/sample_comic.cbz',
          reopenButton: 'Open CBZ',
        );

        // Not awaited, and sized to outlast the close: full-height thumbnails
        // at top quality, so each read is followed by a decode and a re-encode.
        final reads = [
          for (var i = 0; i < 16; i++)
            Flureadium().extractPageThumbnail(
              '00${(i % 5) + 1}.jpg',
              2000,
              100,
            ),
        ];

        await Flureadium().closePublication();

        for (final read in reads) {
          // The assertion is that awaiting does not throw. Either answer is
          // legitimate: a read that beat the close returns bytes, one that lost
          // returns null.
          final bytes = await read;
          if (bytes != null) {
            expect(bytes, isNotEmpty);
          }
        }
      }

      // Leaves the app open for whatever runs next, and shows the plugin still
      // works against a freshly opened publication.
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_comic.cbz',
        reopenButton: 'Open CBZ',
      );
      expect(
        await Flureadium().extractPageThumbnail('001.jpg', 80, 70),
        isNotNull,
      );
    });
  });
}

Future<Locator> _waitForCbzReaderReady(
  WidgetTester tester, {
  String? href,
}) async {
  // 60 ticks × 250ms keeps the original 15s ceiling at finer granularity.
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 250));

    if (find.byType(ReadiumReaderWidget).evaluate().isEmpty) {
      continue;
    }

    final reader = FlureadiumPlatform.instance.currentReaderWidget;
    final locator = reader == null ? null : await reader.getCurrentLocator();
    if (locator != null && (href == null || locator.href == href)) {
      return locator;
    }
  }

  fail(
    href == null
        ? 'CBZ reader did not report an initial locator.'
        : 'CBZ reader did not navigate to $href.',
  );
}
