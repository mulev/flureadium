import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_until.dart';

/// Reads the href out of the example app's keyed current-track indicator.
///
/// The label is `'track: <position> <href>'`. Position is never populated on
/// the audiobook path, so the href alone carries track identity. Returns ''
/// while the timebased state has not delivered a locator yet.
String currentTrackHref(WidgetTester tester) {
  final text =
      tester.widget<Text>(find.byKey(const Key('current-track'))).data ?? '';
  return RegExp(r'^track: \S+ (.*)$').firstMatch(text)?.group(1)?.trim() ?? '';
}

/// Waits until the indicator holds a real track href, then returns it.
///
/// `waitForPlaying` only gates on the local 'Audio Pause' flag, which flips
/// when `play()` returns; the locator arrives later over the timebased event
/// channel. Reading the label straight after can capture the empty
/// placeholder and make it a baseline (flureadium-c7x).
///
/// Pass [expected] to anchor the baseline to a known href from the publication
/// under test. The example app never clears its timebased state on open, and
/// on Android the native locator survives `stop()` and reopen, so the label
/// can still hold the *previous* test's track. That value is non-empty, so it
/// would satisfy an unanchored wait and become a baseline belonging to another
/// book.
Future<String> awaitTrackHref(
  WidgetTester tester, {
  String? expected,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final arrived = await pumpUntil(tester, () {
    final href = currentTrackHref(tester);
    return href.isNotEmpty && (expected == null || href == expected);
  }, timeout: timeout);
  final seen = currentTrackHref(tester);
  expect(
    arrived,
    isTrue,
    reason: expected == null
        ? 'timebased state never delivered a track href; if main.dart changed '
              'the current-track label format, currentTrackHref stops matching'
        : 'expected the track href "$expected" from the publication under '
              'test, but the label settled on "$seen" — a stale href here '
              'means the baseline came from a previous test',
  );
  return seen;
}

/// Waits until the href becomes a different, non-empty value, then returns it.
///
/// The non-empty clause carries the guarantee: the href can go transiently
/// empty while the player swaps tracks, and a bare `!= before` would accept
/// that placeholder as a track change.
Future<String> awaitTrackHrefChange(
  WidgetTester tester,
  String before, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final changed = await pumpUntil(tester, () {
    final href = currentTrackHref(tester);
    return href.isNotEmpty && href != before;
  }, timeout: timeout);
  expect(changed, isTrue, reason: 'track href never changed from "$before"');
  return currentTrackHref(tester);
}
