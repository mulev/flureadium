import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/expect_eventually.dart';
import 'helpers/locator_latch.dart';
import 'helpers/reader_status.dart';
import 'helpers/set_chrome.dart';

/// Proves a PDF opens, reports a page position, and advances it on request.
///
/// Two things were measured while writing this suite rather than assumed, and
/// both shaped the file:
///
/// **Android PDF is not driven by a synthesized touch either.** Six taps at the
/// reader's centre reported nothing through `onTap`: one with a 60 s wait, then
/// five three seconds apart, all with the chrome down and the reader reporting
/// `ready` and a delivered locator before each. The pointer does reach Flutter
/// — `reader_widget.dart`'s `Listener` logged `onPointerDown`/`onPointerUp` at
/// the tapped offset on every attempt — and AndroidPdfViewer's
/// `onSingleTapConfirmed` reports unconditionally (`PdfNavigator.kt:134-138`),
/// so the event is lost between the two, not by either. There is therefore no
/// tap case here; PDF stays in the `user | tap` row of `validators.conf` with
/// the iOS cases, now for a measured reason.
///
/// **The page position comes from the pulled locator, not the pushed latch.**
/// The text-locator stream delivers a PDF locator whose `progression` is `0.0`
/// on every page, so `locator_progression` reads the same value on page 1 and
/// page 3 and cannot witness a page turn. The locator pulled from the reader
/// carries `locations.position` — 2 on open of the three-page fixture, 3 after
/// `goRight` — which is what the movement cases below assert.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('PDF', () {
    // No tearDown close: the next test's ensureAppShowing switches
    // publications through the Open button, mirroring the app. Closing the
    // container under a still-mounted reader is not an app flow
    // (flureadium-i0s).

    Future<void> showPdf(WidgetTester tester) async {
      // The reopen button lives in the bar, and so do the latches below.
      await setChrome(tester, visible: true);
      // No `openAfterColdBoot`: this group opens one publication, so the
      // cold-boot path already lands on the PDF — same as `cbz_test.dart`.
      await ensureAppShowing(
        tester,
        initialAsset: 'assets/pubs/sample_pages.pdf',
        reopenButton: 'Open PDF',
      );
      await expectEventually(
        tester,
        () => readerStatus(tester) == 'ready',
        reason: 'the PDF reader never reported ready',
        timeout: const Duration(seconds: 30),
      );
    }

    testWidgets('the PDF opens and the reader reports ready', (tester) async {
      await showPdf(tester);

      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
      expect(readerStatus(tester), 'ready');
    });

    testWidgets('a locator arrives naming the PDF resource', (tester) async {
      await showPdf(tester);

      await expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no locator arrived for the PDF',
      );
      expect(locatorHref(tester), contains('.pdf'));
    });

    testWidgets('goRight moves the reported position to a later page', (
      tester,
    ) async {
      await showPdf(tester);
      final start = await _waitForPosition(tester);

      await tester.tap(find.text('→'));

      await _waitForPosition(tester, above: start);
    });

    testWidgets('the position stays put when nothing asks it to move', (
      tester,
    ) async {
      await showPdf(tester);
      final start = await _waitForPosition(tester);

      // A deliberate real-time wait with no condition to break on: the point
      // is that three seconds of nothing changes nothing. Without this
      // control, the case above passes just as well against a position that
      // drifts on its own.
      await tester.pump(const Duration(seconds: 3));

      expect(await _position(), start);
    });
  });
}

/// The page number the reader currently reports, or null before it reports one.
Future<int?> _position() async {
  final reader = FlureadiumPlatform.instance.currentReaderWidget;
  return (await reader?.getCurrentLocator())?.locations?.position;
}

/// Pumps until the reader reports a page number greater than [above], and
/// returns it. Page numbers are 1-based, so the default accepts the first one.
///
/// A hand-rolled poll rather than `expectEventually`, because [_position] is an
/// async pull and that helper's condition is synchronous — `cbz_test.dart`'s
/// `_waitForCbzReaderReady` is the precedent, and this ticks at the same 250 ms.
/// 120 ticks keeps a 30 s ceiling, which is what a cold PDF open needs.
Future<int> _waitForPosition(WidgetTester tester, {int above = 0}) async {
  for (var tick = 0; tick < 120; tick++) {
    await tester.pump(const Duration(milliseconds: 250));
    final position = await _position();
    if (position != null && position > above) return position;
  }

  fail('the PDF reader never reported a page past $above');
}
