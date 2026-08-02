import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';

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

      final path = await _extractAsset('assets/pubs/sample_comic.cbz');
      final pub = await Flureadium().loadPublication(path);

      expect(pub.readingOrder.first.href, equals(locator.href));
    });

    // Regression test for flureadium-pbc, and for flureadium-i0s before it,
    // which was the same crash reached through the EPUB WebView instead of the
    // image navigator. Closing a publication closes the zip container; a page
    // read already running against it throws `java.lang.IllegalStateException:
    // zip file closed` from a readium coroutine that has no parent and so no
    // handler, and Android kills the process. Nothing is catchable from Dart:
    // the app is simply gone, and every remaining test in the run flushes as a
    // pass in the same millisecond.
    //
    // The window is roughly 150ms wide, so a single attempt is a coin toss.
    // These four sweep the delay between starting the read and closing under
    // it, and each targets an unvisited page so the navigator has to go to the
    // container rather than serving a cached bitmap.
    //
    // Reaching the assertion at the end is the result. On Android the guard
    // logs `Read after the container closed` when it catches one, which is
    // visible in the logcat the CI job uploads.
    testWidgets(
      'closing a publication during a page load keeps the app alive',
      (tester) async {
        const attempts = [
          (href: '005.jpg', position: 5, delayMs: 0),
          (href: '004.jpg', position: 4, delayMs: 20),
          (href: '003.jpg', position: 3, delayMs: 60),
          (href: '002.jpg', position: 2, delayMs: 120),
        ];

        for (final attempt in attempts) {
          await ensureAppShowing(
            tester,
            initialAsset: 'assets/pubs/sample_comic.cbz',
            reopenButton: 'Open CBZ',
          );

          // Deliberately not awaited. The read has to still be in flight when
          // the container closes underneath it.
          final navigating = Flureadium().goToLocator(
            Locator(
              href: attempt.href,
              type: 'image/jpeg',
              locations: Locations(position: attempt.position),
            ),
          );

          if (attempt.delayMs > 0) {
            await tester.pump(Duration(milliseconds: attempt.delayMs));
          }

          await Flureadium().closePublication();

          // Either outcome is fine: the navigation may land before the close or
          // fail against a closed publication. What must not happen is a crash.
          await navigating.catchError((Object _) => false);
          await tester.pump(const Duration(milliseconds: 250));
        }

        // Only reachable in a live process, and it also leaves the app open for
        // whatever runs next.
        await ensureAppShowing(
          tester,
          initialAsset: 'assets/pubs/sample_comic.cbz',
          reopenButton: 'Open CBZ',
        );
        expect(
          await Flureadium().extractPageThumbnail('001.jpg', 80, 70),
          isNotNull,
        );
      },
    );
  });
}

Future<String> _extractAsset(String assetPath) async {
  final bytes = await rootBundle.load(assetPath);
  final filename = assetPath.split('/').last;
  final tmp = File(
    '${Directory.systemTemp.path}/${DateTime.now().millisecondsSinceEpoch}_$filename',
  );
  await tmp.writeAsBytes(bytes.buffer.asUint8List());
  return tmp.path;
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
