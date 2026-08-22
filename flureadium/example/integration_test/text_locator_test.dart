import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/locator_latch.dart';
import 'helpers/pump_until.dart';

/// The text-locator event stream, end to end.
///
/// Nothing else in the suite asserts this stream delivers at all. The two
/// tests that look like they do — EPUB's 'Go To Saved' and 'apply decoration
/// to current locator' — both route through main.dart handlers that return
/// early on a null locator, so they pass unchanged when the stream is dead.
/// The one swap assertion that exists (CBZ's view-rebuild regression) reads
/// the locator back through `getCurrentLocator`, which answers from the
/// navigator and stays correct even when nothing is being pushed.
///
/// Grouped by contract rather than by fixture: each test needs a different
/// publication kind, but they all pin the same channel.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('text-locator stream', () {
    tearDownAll(() async {
      await Flureadium().closePublication();
    });

    testWidgets('a page turn is pushed to Dart', (tester) async {
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/moby_dick.epub',
        reopenButton: 'Open EPUB',
        openAfterColdBoot: true,
      );

      await tester.tap(find.text('→'));
      final delivered = await pumpUntil(
        tester,
        () => locatorHref(tester).isNotEmpty,
        timeout: const Duration(seconds: 15),
      );

      expect(
        delivered,
        isTrue,
        reason: 'no locator reached Dart; the latch was still empty',
      );
      expect(
        locatorHref(tester),
        endsWith('.xhtml'),
        reason: 'the href must name a resource of the open EPUB',
      );
    });

    // flureadium-5wu broke exactly this on the sibling reader-status channel:
    // a swapped-out view end-streamed a channel the replacement had already
    // taken over, and every later event was lost for the rest of the session.
    testWidgets('it follows a publication swap', (tester) async {
      final epubHref = await _latchAnEpubLocator(tester);

      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/moby_dick.epub',
        reopenButton: 'Open CBZ',
      );

      // Waiting on the CBZ extension, not on "non-empty": the EPUB href
      // already in the latch cannot satisfy it, so only a locator reported by
      // the swapped-in publication can end the wait.
      final delivered = await pumpUntil(
        tester,
        () => locatorHref(tester).endsWith('.jpg'),
        timeout: const Duration(seconds: 15),
      );

      expect(
        delivered,
        isTrue,
        reason:
            'no CBZ locator arrived after the swap; the latch still reads '
            '"${locatorHref(tester)}"',
      );
      expect(locatorHref(tester), isNot(epubHref));
    });

    testWidgets('a swap to audio clears the previous book\'s locator', (
      tester,
    ) async {
      // An audiobook is the one publication kind that reports no pages, which
      // is what makes the clear observable: after a swap to a paged
      // publication the incoming reader refills the latch within a poll tick,
      // so a cleared latch and a stale one look identical. Here nothing
      // refills it, so it is empty only if the open path cleared it.
      //
      // Opening does not build a player — that happens in audioEnable, which
      // Audio Play drives — so this stays off the hardware-audio path and out
      // of the @native bucket.
      await _latchAnEpubLocator(tester);

      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/moby_dick.epub',
        reopenButton: 'Open AudioBook',
      );
      // Long enough that a locator still in flight from the EPUB would land.
      await tester.pump(const Duration(seconds: 2));

      expect(
        locatorHref(tester),
        isEmpty,
        reason:
            'the closed EPUB\'s locator is still latched as the audiobook\'s '
            'position; Go To Saved would navigate the audiobook to it',
      );
    });

    testWidgets('a fresh subscriber learns the current position', (
      tester,
    ) async {
      await _latchAnEpubLocator(tester);

      // Long enough that a locator still in flight from the page turn would
      // land, so `before` cannot be beaten by an event the tap did not cause.
      await tester.pump(const Duration(seconds: 2));
      final before = locatorEvents(tester);

      // 'Resubscribe Locator' clears the latch and re-runs the app's
      // cancel-then-listen path — the same 0→1 transition
      // ReadiumReaderWidget.onReady performs, which is where an image
      // publication's only locator for the page is already gone by. Nothing
      // navigates after this tap, so a new delivery can only come from the
      // subscribe-time read of the navigator.
      //
      // The count, not the latch: the app does clear _locator, but the answer
      // lands inside the same frame budget under
      // LiveTestWidgetsFlutterBinding, so an empty latch is not observable and
      // the value alone cannot tell "answered on subscribe" from "never
      // cleared". A count that must rise can be satisfied by neither. The
      // clear itself is asserted in example/test/widget_test.dart, where the
      // mocked channel answers nothing.
      await tester.tap(find.text('Resubscribe Locator'));

      final answered = await pumpUntil(
        tester,
        () => locatorEvents(tester) > before,
        timeout: const Duration(seconds: 15),
      );

      expect(
        answered,
        isTrue,
        reason:
            'the stream stayed silent for a subscriber that arrived after the '
            'reader already had a position',
      );
      expect(locatorHref(tester), endsWith('.xhtml'));
    });
  });
}

/// Opens the EPUB and turns a page, so the latch holds a locator to swap away
/// from. Returns that href.
Future<String> _latchAnEpubLocator(WidgetTester tester) async {
  await ensureAppShowing(
    tester,
    initialAsset: 'assets/pubs/moby_dick.epub',
    reopenButton: 'Open EPUB',
    openAfterColdBoot: true,
  );

  await tester.tap(find.text('→'));
  await pumpUntil(
    tester,
    () => locatorHref(tester).isNotEmpty,
    timeout: const Duration(seconds: 15),
  );

  final href = locatorHref(tester);
  expect(href, isNotEmpty, reason: 'no EPUB locator to swap away from');
  return href;
}
