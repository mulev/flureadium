import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/extract_asset.dart';
import 'helpers/locator_latch.dart';
import 'helpers/pump_until.dart';

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

      final delivered = await pumpUntil(
        tester,
        () => locatorHref(tester).isNotEmpty,
        timeout: const Duration(seconds: 15),
      );
      expect(delivered, isTrue, reason: 'no starting page locator');
      final first = locatorHref(tester);

      await tester.tap(find.text('→'));
      await _nextPage(tester, from: first);

      await tester.tap(find.text('←'));
      final returned = await pumpUntil(
        tester,
        () => locatorHref(tester) == first,
        timeout: const Duration(seconds: 15),
      );
      expect(returned, isTrue, reason: 'the page never returned to "$first"');
    });

    testWidgets('revisiting pages loads from cache without errors', (
      tester,
    ) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_comic.cbz',
        reopenButton: 'Open CBZ',
      );

      final delivered = await pumpUntil(
        tester,
        () => locatorHref(tester).isNotEmpty,
        timeout: const Duration(seconds: 15),
      );
      expect(delivered, isTrue, reason: 'no starting page locator');
      final first = locatorHref(tester);

      await tester.tap(find.text('→'));
      final second = await _nextPage(tester, from: first);
      await tester.tap(find.text('→'));
      final third = await _nextPage(tester, from: second);

      // Back to pages already rendered — the iOS cache-hit path.
      await tester.tap(find.text('←'));
      final backToSecond = await pumpUntil(
        tester,
        () => locatorHref(tester) == second,
        timeout: const Duration(seconds: 15),
      );
      expect(backToSecond, isTrue, reason: 'no cache hit for "$second"');

      await tester.tap(find.text('←'));
      final backToFirst = await pumpUntil(
        tester,
        () => locatorHref(tester) == first,
        timeout: const Duration(seconds: 15),
      );
      expect(backToFirst, isTrue, reason: 'no cache hit for "$first"');

      expect(
        third,
        isNot(equals(first)),
        reason: 'the forward taps never left page one',
      );
      expect(
        _errorLatch(tester),
        isEmpty,
        reason: 'an error surfaced during the revisit',
      );
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

    // Regression for flureadium-37h: opening a publication into a live reader
    // must rebuild the native view. Before the fix the platform view stayed
    // bound to the EPUB that openPublication had already closed, so every
    // navigation call hit a released navigator and the reader never reported
    // a CBZ page.
    testWidgets('opening a CBZ into a live EPUB reader rebuilds the view', (
      tester,
    ) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/moby_dick.epub',
        reopenButton: 'Open EPUB',
        openAfterColdBoot: true,
      );

      expect(find.byType(ReadiumReaderWidget), findsOneWidget);

      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/moby_dick.epub',
        reopenButton: 'Open CBZ',
      );

      expect(
        (await _waitForCbzReaderReady(tester, href: '001.jpg')).href,
        '001.jpg',
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

/// Waits for the locator latch to leave [from] and returns the href that
/// replaced it. Fails the test if the page never moved.
Future<String> _nextPage(WidgetTester tester, {required String from}) async {
  final moved = await pumpUntil(
    tester,
    () => locatorHref(tester) != from,
    timeout: const Duration(seconds: 15),
  );
  expect(moved, isTrue, reason: 'the page never left "$from"');
  return locatorHref(tester);
}

/// Reads the keyed error latch the example fills from onErrorEvent — the
/// channel `ReaderCoroutineFailure` reports image-navigator failures on.
/// The text is `audio-error: <message>`; empty until an error surfaces.
String _errorLatch(WidgetTester tester) =>
    (tester.widget<Text>(find.byKey(const Key('audio-error'))).data ?? '')
        .replaceFirst('audio-error: ', '');
