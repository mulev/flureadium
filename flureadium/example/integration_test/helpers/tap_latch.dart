import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the example app's `tap-events` latch — how many taps the native
/// navigator has reported since this publication opened.
///
/// A count rather than a flag, for the same reason as `locator-events`: a bool
/// cannot tell "fired once" from "fired twice", and a double registration is
/// exactly what the tap wiring has to be proven free of. `int.parse` rather
/// than `tryParse` so a renamed or unmounted latch fails loudly instead of
/// reading 0 — which would leave "the tap never reached native" and "the latch
/// is gone" indistinguishable.
int tapEvents(WidgetTester tester) => int.parse(
  (tester.widget<Text>(find.byKey(const Key('tap-events'))).data ?? '')
      .replaceFirst('tap-events: ', ''),
);

/// Reads the position carried by the last reported tap, or null before the
/// first tap of this publication.
///
/// The app renders the coordinates as text rather than latching a bool, so a
/// units mismatch between the two platforms shows up in the latch instead of
/// passing silently.
Offset? lastTap(WidgetTester tester) {
  final raw = tester.widget<Text>(find.byKey(const Key('last-tap'))).data ?? '';
  if (raw.isEmpty) return null;
  final parts = raw.split(',');
  return Offset(double.parse(parts[0]), double.parse(parts[1]));
}
