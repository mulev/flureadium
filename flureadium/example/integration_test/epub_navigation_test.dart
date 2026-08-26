// EPUB skip-navigation behaviour, run against three fixtures with different
// nav-document shapes. Separate from `epub_test.dart` because that file covers
// opening, status and locator reporting; these cases all drive the chapter
// buttons.
import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/expect_eventually.dart';
import 'helpers/locator_latch.dart';
import 'helpers/reader_status.dart';

void _navigationTests(String assetLabel, String asset, String reopenButton) {
  group('navigation ($assetLabel)', () {
    // Every test opens this group's own book: `openAfterColdBoot` taps the
    // reopen button on the cold-boot arm too, so the first test to run gets
    // this fixture instead of whatever a previous suite left mounted.
    Future<void> showFixture(WidgetTester tester) => ensureAppShowing(
      tester,
      initialAsset: asset,
      reopenButton: reopenButton,
      openAfterColdBoot: true,
    );

    tearDown(() async {
      await Flureadium().closePublication();
    });

    testWidgets('opens and shows reader widget', (tester) async {
      await showFixture(tester);
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('the load cover tracks reader status', (tester) async {
      await showFixture(tester);

      final cover = find.byKey(const Key('reader-loading-cover'));

      // ensureAppShowing returns on the open-generation bump, which lands in
      // the same setState that clears _readerStatus — so this wait is a guard,
      // not a delay: were a 'ready' still latched, the sampling loop below
      // would return on it and never watch the load it exists to watch.
      await expectEventually(
        tester,
        () => readerStatus(tester) != 'ready',
        reason: 'the open never reset the reader status',
      );

      // Sampled on every pump: covered exactly while the reader is loading.
      // 'error' and 'closed' are terminal, so the cover is gone there too.
      await expectEventually(
        tester,
        () {
          final status = readerStatus(tester);
          expect(
            cover.evaluate().isNotEmpty,
            status.isEmpty || status == 'loading',
            reason: 'reader status was "$status"',
          );
          return status == 'ready';
        },
        reason: 'reader never reported ready',
        timeout: const Duration(seconds: 30),
      );
    });

    testWidgets('navigate left and right', (tester) async {
      await showFixture(tester);

      await expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to navigate from',
      );
      final start = locatorHref(tester);

      // Forward first: on the opening resource a back-tap may legitimately
      // have nowhere to go, so only forward-then-back has a provable trip.
      await tester.tap(find.text('→'));
      await expectEventually(
        tester,
        () => locatorHref(tester) != start,
        reason: 'the locator never left "$start" after →',
      );

      await tester.tap(find.text('←'));
      await expectEventually(
        tester,
        () => locatorHref(tester) == start,
        reason: 'the locator never returned to "$start"',
      );
    });

    testWidgets('DartSkip+ advances the reader', (tester) async {
      await showFixture(tester);

      await expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to skip from',
      );
      final before = locatorHref(tester);

      await tester.tap(find.text('DartSkip+'));
      await expectEventually(
        tester,
        () => locatorHref(tester) != before,
        reason: 'DartSkip+ did not move the reader from "$before"',
      );
    });

    testWidgets('every DartSkip+ moves the reader', (tester) async {
      await showFixture(tester);

      await expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to skip from',
      );

      // Asserts the position, not the TOC index: a book whose nav document
      // anchors several entries inside one rendered page advances its index on
      // every tap while the reader stays exactly where it was. Progression
      // rides along with the href because a resource holding several entries
      // moves within itself, which the href alone cannot show.
      String position() =>
          '${locatorHref(tester)}@${locatorProgression(tester)}';

      var previous = position();
      for (var skip = 1; skip <= 3; skip++) {
        await tester.tap(find.text('DartSkip+'));
        await expectEventually(
          tester,
          () => position() != previous,
          reason: 'skip $skip did not move the reader from "$previous"',
        );
        previous = position();
      }
    });

    testWidgets('DartSkip- returns the reader', (tester) async {
      await showFixture(tester);

      await expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to skip from',
      );
      final start = locatorHref(tester);

      // Both fixtures open on their first TOC entry, so a backward skip has
      // nowhere to land until a forward skip puts something behind us.
      await tester.tap(find.text('DartSkip+'));
      await expectEventually(
        tester,
        () => locatorHref(tester) != start,
        reason: 'nothing to skip back from',
      );

      await tester.tap(find.text('DartSkip-'));
      await expectEventually(
        tester,
        () => locatorHref(tester) == start,
        reason: 'DartSkip- did not return the reader to "$start"',
      );
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Navigation smoke tests run with both fixtures to catch regressions.
  // The hierarchical fixture has Part I → [Ch1, Ch2, Ch3] and
  // Part II → Section 1 → [Ch4, Ch5], verifying that flattenToc-based skip
  // navigation works with multi-level TOC structures.
  _navigationTests('moby_dick', 'assets/pubs/moby_dick.epub', 'Open EPUB');
  _navigationTests(
    'hierarchical_toc',
    'assets/pubs/hierarchical_toc.epub',
    'Open Hierarchical',
  );
  // The front-matter fixture anchors six nav entries inside one rendered page
  // ahead of Chapter 1, the shape that made a chapter tap land on the page it
  // was already showing.
  _navigationTests(
    'frontmatter_toc',
    'assets/pubs/frontmatter_toc.epub',
    'Open Frontmatter',
  );
}
