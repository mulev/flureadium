// EPUB skip-navigation behaviour, run against four fixtures with different
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
import 'helpers/pump_until.dart';
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

  // Navigation smoke tests run with every fixture to catch regressions.
  // The hierarchical fixture has Part I → [Ch1, Ch2, Ch3] and
  // Part II → Section 1 → [Ch4, Ch5], verifying that skip navigation works
  // with multi-level TOC structures.
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
  // The back-link fixture reproduces the ebookmaker shape: every chapter opens
  // with a back-to-contents link above its own heading, and the nav document
  // points at an id carried on the div wrapping that heading.
  _navigationTests(
    'backlink_chapter',
    'assets/pubs/backlink_chapter.epub',
    'Open Backlink Chapter',
  );
  _backlinkFragmentTests();
  _hierarchicalPartTests();
}

/// The one case that belongs to `backlink_chapter.epub` alone: the fixture is
/// the only one whose chapters put content above their own heading, so it is
/// the only one whose `toc=` fragment can come back empty. Kept out of
/// [_navigationTests] because the other three fixtures have no heading id to
/// assert on.
void _backlinkFragmentTests() {
  group('navigation (backlink_chapter) toc fragment', () {
    Future<void> showFixture(WidgetTester tester) => ensureAppShowing(
      tester,
      initialAsset: 'assets/pubs/backlink_chapter.epub',
      reopenButton: 'Open Backlink Chapter',
      openAfterColdBoot: true,
    );

    tearDown(() async {
      await Flureadium().closePublication();
    });

    testWidgets('a chapter landing names the chapter heading', (tester) async {
      await showFixture(tester);

      // The reader opens on the cover, which has no TOC entry, so the first
      // skip resolves from "no current entry" — the state the reported book
      // was in. One skip lands on chapter one.
      await expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to skip from',
      );

      await tester.tap(find.text('DartSkip+'));

      // `pumpUntil` rather than `expectEventually`: the latter builds its
      // reason eagerly, so it would report the fragment as it stood before the
      // skip. Asserting the settled value afterwards puts the id the reader
      // actually named into the failure message.
      await pumpUntil(tester, () => locatorTocFragment(tester) == 'h1');
      expect(
        locatorTocFragment(tester),
        'h1',
        reason:
            'the locator must name the id the nav document points at, carried '
            'on the div wrapping the chapter heading; an empty value means the '
            'page script fell through to the body fallback',
      );
    });
  });
}

/// The case that belongs to `hierarchical_toc.epub` alone: its nav document
/// groups chapters under `Part I`, `Part II` and `Section 1`, each of which is
/// a spine document of its own, so a skip crosses three nesting levels on the
/// way through the book. Kept out of [_navigationTests] because the other
/// three fixtures have no nesting to cross, and because reaching the first
/// boundary takes more taps than the shared group makes.
void _hierarchicalPartTests() {
  group('navigation (hierarchical_toc) nesting', () {
    Future<void> showFixture(WidgetTester tester) => ensureAppShowing(
      tester,
      initialAsset: 'assets/pubs/hierarchical_toc.epub',
      reopenButton: 'Open Hierarchical',
      openAfterColdBoot: true,
    );

    tearDown(() async {
      await Flureadium().closePublication();
    });

    testWidgets('every skip crosses the nesting intact', (tester) async {
      await showFixture(tester);

      await expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to skip from',
      );

      // Position, not TOC index — same reason as the shared group: an entry
      // sharing a rendered page advances the index without moving the reader.
      String position() =>
          '${locatorHref(tester)}@${locatorProgression(tester)}';

      // Five skips rather than the shared group's three: the contents are
      // Part I -> [Ch1, Ch2, Ch3], Part II -> Section 1 -> [Ch4, Ch5], so the
      // reader does not cross a part boundary until the fifth tap: the book
      // opens on cover.xhtml, spine[0], which no contents entry names, so the
      // first tap lands on Part I. Every one
      // of those eight entries is its own spine document, which is what makes
      // this the guard that filtering the contents by reachability leaves a
      // well-formed hierarchical book alone.
      var previous = position();
      for (var skip = 1; skip <= 5; skip++) {
        await tester.tap(find.text('DartSkip+'));
        await expectEventually(
          tester,
          () => position() != previous,
          reason: 'skip $skip did not move the reader from "$previous"',
        );
        previous = position();
      }
    });
  });
}
