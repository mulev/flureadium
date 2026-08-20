import 'dart:io';

import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/locator_latch.dart';
import 'helpers/pump_until.dart';
import 'helpers/reader_status.dart';
import 'helpers/tap_latch.dart';

/// Proves the native tap chain end to end: a real tap on the platform view,
/// through Readium's own filtered tap callback, back into `onTap`.
///
/// Reflowable EPUB on Android only, and not by preference. Two separate limits
/// put everything else in the `user | tap` row of `validators.conf`, and
/// both were measured on this suite rather than assumed:
///
/// **iOS cannot be driven at all.** `UiKitView` builds a `RenderUiKitView`
/// whose `handleEvent` only enters the gesture arena and then releases a *real*
/// `UITouch` to the embedded view (`rendering/platform_view.dart:453-460`,
/// `:548-550`). `WidgetTester` never synthesizes one, so no iOS tap case can be
/// written short of a separate XCUITest target.
///
/// **Fixed layout on Android is not driven by a synthesized touch.** Over an
/// `AndroidViewSurface` a synthesized tap does become a real `MotionEvent`
/// (`services/platform_views.dart:916-918`) and the native view receives it:
/// `EdgeTapInterceptView.dispatchTouchEvent` logs the `ACTION_DOWN` for both a
/// reflowable and a fixed-layout publication. A reflowable page then reports
/// the tap; a fixed-layout page never does — five taps three seconds apart on
/// `fixed_layout.epub` produced nothing, while `adb shell input tap` at the
/// same point reported immediately. The event reaches the view and is dropped
/// above it, somewhere in the fixed-layout script path, so that case is handed
/// over with the iOS ones instead of being asserted here.
///
/// Three explanations were tested and eliminated before accepting that: tap
/// position (the reader's centre is inside the page — screenshotted before any
/// tap, the page spans raw y 460–1905 of 2400, and a manual tap at that exact
/// centre reports), reader readiness (gating on a delivered locator, as
/// `showFixture` still does, changed nothing), and tap duration (holding the
/// press 120ms against `adb`'s ~100ms changed nothing, so the hold was
/// reverted).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _tapTests();
}

const _epub = 'assets/pubs/moby_dick.epub';
const _tapTargets = 'assets/pubs/tap_targets.epub';

/// Pumps until [condition] holds, failing with [reason] on timeout.
///
/// [pumpUntil] reports a timeout in its return value, so every wait has to
/// assert that value or a never-satisfied condition passes silently.
Future<void> _expectEventually(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final satisfied = await pumpUntil(tester, condition, timeout: timeout);
  expect(satisfied, isTrue, reason: reason);
}

void _tapTests() {
  group('tap', () {
    Finder reader() => find.byType(ReadiumReaderWidget);

    Finder controlBar() => find.byKey(const Key('control-bar'));

    /// Puts the example app's control bar into [visible] state through its
    /// always-visible toggle (`main.dart:800`).
    ///
    /// Every tap case needs the bar down first. The bar is stacked over the
    /// reader and covers its centre, and for a fixed-layout publication the
    /// strip left above it is mostly the blank area beside the page — measured
    /// on a 1080x2400 emulator, the page begins 175 logical pixels down, so a
    /// tap aimed at the middle of that strip hits nothing at all. Rather than
    /// model any of that, take the bar away and tap the real centre, which a
    /// centred scaled page always covers.
    ///
    /// Driven by the toggle rather than by a tap on the reader: a tap is the
    /// signal under test, so using it as setup would make every case depend on
    /// the thing it is trying to prove.
    Future<void> setChrome(WidgetTester tester, {required bool visible}) async {
      final toggle = find.byKey(const Key('toggle-controls'));
      // Before the first cold boot there is no app and so no chrome to set;
      // the app starts with the bar up, which is what a caller asking for
      // `visible: true` wants anyway.
      if (toggle.evaluate().isEmpty) return;
      if (controlBar().evaluate().isNotEmpty == visible) return;
      await tester.tap(toggle);
      await _expectEventually(
        tester,
        () => controlBar().evaluate().isNotEmpty == visible,
        reason:
            'the control bar never became ${visible ? 'visible' : 'hidden'}',
        timeout: const Duration(seconds: 5),
      );
    }

    Future<void> showFixture(
      WidgetTester tester, {
      required String asset,
      required String reopenButton,
    }) async {
      // The reopen buttons live inside the bar, so it has to be up to switch
      // publications — and down again before anything taps the reader.
      await setChrome(tester, visible: true);
      await ensureAppShowing(
        tester,
        initialAsset: asset,
        reopenButton: reopenButton,
        openAfterColdBoot: true,
      );
      await _expectEventually(
        tester,
        () => readerStatus(tester) == 'ready',
        reason: 'the reader never reported ready for $asset',
        timeout: const Duration(seconds: 30),
      );
      // `ready` is the plugin's own status and does not prove the WebView's
      // JavaScript side is listening yet, so tapping on it alone races the
      // gesture layer. A delivered locator does prove it, because that is
      // where locators come from. (This gate was first added while chasing the
      // fixed-layout failure below; it did not change that outcome, and it is
      // kept because tapping before the JS layer listens is a real race.)
      await _expectEventually(
        tester,
        () => locatorEvents(tester) > 0,
        reason: 'no locator arrived for $asset, so its JS layer is not alive',
        timeout: const Duration(seconds: 30),
      );
      await setChrome(tester, visible: false);
    }

    /// Taps the centre of the exposed reader, first taking the chrome down: a
    /// reported tap toggles it back up, so a case that taps twice would aim its
    /// second tap at the buttons.
    Future<void> tapContent(WidgetTester tester) async {
      await setChrome(tester, visible: false);
      await tester.tapAt(tester.getCenter(reader()));
    }

    /// Taps content and returns once exactly one tap has been reported, then
    /// holds for a further second: a second report would mean a double
    /// `InputListener` registration, which is the bug the epic's identity-keyed
    /// rebind exists to prevent.
    Future<void> expectOneTap(WidgetTester tester) async {
      final before = tapEvents(tester);
      await tapContent(tester);
      await _expectEventually(
        tester,
        () => tapEvents(tester) > before,
        reason: 'no tap arrived from native',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        tapEvents(tester),
        before + 1,
        reason: 'one tap was reported ${tapEvents(tester) - before} times',
      );
    }

    tearDown(() async {
      await Flureadium().closePublication();
    });

    /// Guarded by construction: `all_tests.dart` is imported and run on the
    /// iOS simulator too, where a synthesized tap cannot reach Readium at all,
    /// so every case here has to be skipped off Android. The skip sits on each
    /// test because `flutter_test`'s `group` drops it, and going through this
    /// wrapper is what keeps the next case added guarded without remembering.
    void tapTest(String description, WidgetTesterCallback body) =>
        testWidgets(description, body, skip: !Platform.isAndroid);

    tapTest('a centre tap reports one tap, with a position', (tester) async {
      await showFixture(tester, asset: _epub, reopenButton: 'Open EPUB');

      final size = tester.getSize(reader());
      await expectOneTap(tester);

      final position = lastTap(tester);
      expect(position, isNotNull, reason: 'tap-events rose without a position');
      expect(position!.dx, inInclusiveRange(0, size.width));
      expect(position.dy, inInclusiveRange(0, size.height));
    });

    tapTest('a hyperlink tap navigates and reports nothing', (tester) async {
      await showFixture(
        tester,
        asset: _tapTargets,
        reopenButton: 'Open Tap Targets',
      );
      // `locator_href` is inside the control bar (`main.dart:914`), so reading
      // it needs the chrome up, while tapping needs it down. Only `tap-events`
      // and `last-tap` sit outside that gate.
      await setChrome(tester, visible: true);
      await _expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to navigate from',
      );

      final start = locatorHref(tester);
      final before = tapEvents(tester);
      await tapContent(tester);
      await setChrome(tester, visible: true);

      // page1.xhtml is one anchor filling the viewport, so the centre of the
      // reader is the link. Readium handles it internally and, by contract,
      // does not report the tap.
      await _expectEventually(
        tester,
        () => locatorHref(tester).contains('page2'),
        reason: 'the link never navigated away from "$start"',
      );
      expect(
        tapEvents(tester),
        before,
        reason: 'a hyperlink tap was reported as an unhandled tap',
      );
    });

    tapTest('the same fixture reports a tap on a plain page', (tester) async {
      await showFixture(
        tester,
        asset: _tapTargets,
        reopenButton: 'Open Tap Targets',
      );
      await setChrome(tester, visible: true);
      await _expectEventually(
        tester,
        () => locatorHref(tester).isNotEmpty,
        reason: 'no starting locator to navigate from',
      );

      // Follow the link off page 1 first: without this control, the case above
      // passes just as well when no tap ever reaches native.
      await tapContent(tester);
      await setChrome(tester, visible: true);
      await _expectEventually(
        tester,
        () => locatorHref(tester).contains('page2'),
        reason: 'the link never navigated, so this is not the plain page',
      );

      await expectOneTap(tester);
    });

    tapTest('a publication swap keeps the tap alive', (tester) async {
      await showFixture(tester, asset: _epub, reopenButton: 'Open EPUB');
      await expectOneTap(tester);

      // Reopening rebuilds the native reader and rebinds the listener; the
      // counter clears with the rest of the publication latches, so a tap that
      // survives the swap has to raise it from zero again.
      await showFixture(tester, asset: _epub, reopenButton: 'Open EPUB');
      expect(
        tapEvents(tester),
        0,
        reason: 'the reopen never reset the tap latch',
      );

      await expectOneTap(tester);
    });
  });
}
