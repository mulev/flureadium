import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_until.dart';

Finder _controlBar() => find.byKey(const Key('control-bar'));

/// Puts the example app's control bar into [visible] state through its
/// always-visible toggle (`main.dart`, `Key('toggle-controls')`).
///
/// The bar is stacked over the reader and covers its centre — `main.dart` says
/// so where it builds it. So a gesture aimed at the reader's centre while the
/// bar is up lands on whichever reopen button sits under that point, and the
/// app switches publications instead of delivering the gesture. A long press
/// is enough: the release fires the button. That is not a hypothetical — it is
/// what made `epub_test.dart`'s long-press case open `hierarchical_toc.epub`
/// and then race a fresh native open against the assertion.
///
/// Any case that aims at the reader takes the bar down first, and any case
/// that taps a reopen button, `→` or `Go To Saved` needs it up, because those
/// live inside it. The app boots with it up.
///
/// Taking it down rather than aiming above it is deliberate. For a
/// fixed-layout publication the strip left above the bar is mostly the blank
/// area beside the page — measured on a 1080x2400 emulator, the page begins
/// 175 logical pixels down — so a gesture aimed at the middle of that strip
/// hits nothing at all. Rather than model any of that, take the bar away and
/// use the real centre, which a centred scaled page always covers.
///
/// Driven by the toggle rather than by a tap on the reader: in the tap suites a
/// tap is the signal under test, and using it as setup would make those cases
/// depend on the thing they are proving.
///
/// One state is not settable and is rejected rather than waited out. With no
/// publication open the app builds the bar unconditionally (`main.dart`,
/// `if (pub == null || _controlsVisible)`), so `visible: false` cannot be
/// honoured however many times the toggle is pressed. Asking for `visible:
/// true` there is fine — the bar is up, which is what the caller wanted — and
/// `tap_test.dart` does exactly that before its first cold boot.
Future<void> setChrome(WidgetTester tester, {required bool visible}) async {
  final toggle = find.byKey(const Key('toggle-controls'));
  // Before the first cold boot there is no app and so no chrome to set; the app
  // starts with the bar up, which is what a caller asking for `visible: true`
  // wants anyway.
  if (toggle.evaluate().isEmpty) return;
  if (!visible) {
    expect(
      find.byType(ReadiumReaderWidget),
      findsOneWidget,
      reason:
          'taking the control bar down needs an open publication: with none '
          'the app keeps the bar up whatever _controlsVisible says',
    );
  }
  if (_controlBar().evaluate().isNotEmpty == visible) return;
  await tester.tap(toggle);
  final settled = await pumpUntil(
    tester,
    () => _controlBar().evaluate().isNotEmpty == visible,
    timeout: const Duration(seconds: 5),
  );
  expect(
    settled,
    isTrue,
    reason: 'the control bar never became ${visible ? 'visible' : 'hidden'}',
  );
}
