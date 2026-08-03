import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/helpers/audiobook_track.dart';

/// Mirrors the example app's current-track indicator: a keyed [Text] whose
/// content is `'track: <position> <href>'`. Driving it from a [ValueNotifier]
/// lets a test schedule label changes with [Timer]s, which widget-test
/// `pump(duration)` fires off the fake clock.
Widget _harness(ValueNotifier<String> label) => Directionality(
  textDirection: TextDirection.ltr,
  child: ValueListenableBuilder<String>(
    valueListenable: label,
    builder: (context, value, child) =>
        Text(value, key: const Key('current-track')),
  ),
);

Future<ValueNotifier<String>> _pumpLabel(
  WidgetTester tester,
  String initial,
) async {
  final label = ValueNotifier<String>(initial);
  addTearDown(label.dispose);
  await tester.pumpWidget(_harness(label));
  return label;
}

void main() {
  testWidgets('currentTrackHref reads the unpopulated label as empty', (
    tester,
  ) async {
    await _pumpLabel(tester, 'track: - ');

    expect(currentTrackHref(tester), '');
  });

  testWidgets('currentTrackHref returns the href', (tester) async {
    await _pumpLabel(tester, 'track: - a.mp3');

    expect(currentTrackHref(tester), 'a.mp3');
  });

  testWidgets('currentTrackHref excludes a populated position', (tester) async {
    await _pumpLabel(tester, 'track: 1234 a.mp3');

    expect(currentTrackHref(tester), 'a.mp3');
  });

  // Only the position token is \S+; the capture takes the rest of the line, so
  // an href with spaces survives intact. Pins that against anyone "tightening"
  // the capture to (\S+).
  testWidgets('currentTrackHref keeps spaces inside the href', (tester) async {
    await _pumpLabel(tester, 'track: 1234 chapter one.mp3');

    expect(currentTrackHref(tester), 'chapter one.mp3');
  });

  // Closes the last branch in currentTrackHref: a label that does not match
  // the expected shape at all. If main.dart ever changes the format, the
  // helper must read as "no track yet" so awaitTrackHref fails with its
  // diagnostic rather than letting a caller compare against a stale value.
  testWidgets('currentTrackHref returns empty when the format drifts', (
    tester,
  ) async {
    await _pumpLabel(tester, 'now playing a.mp3');

    expect(currentTrackHref(tester), '');
  });

  // Closes the remaining branch: Text.data is null for a Text.rich label.
  // The example app builds a plain Text today, so this pins the behaviour
  // if that ever changes — read as "no track", never throw.
  testWidgets('currentTrackHref returns empty for a rich-text label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text.rich(
          TextSpan(text: 'track: - a.mp3'),
          key: Key('current-track'),
        ),
      ),
    );

    expect(currentTrackHref(tester), '');
  });

  testWidgets('awaitTrackHref returns the href once the label populates', (
    tester,
  ) async {
    final label = await _pumpLabel(tester, 'track: - ');
    Timer(
      const Duration(milliseconds: 600),
      () => label.value = 'track: - a.mp3',
    );

    expect(await awaitTrackHref(tester), 'a.mp3');
  });

  // The discriminating case for a stale baseline: the label already holds a
  // real href left over from a previous test, so `isNotEmpty` alone latches
  // the wrong track. Anchoring on the fixture's own href waits past it.
  testWidgets('awaitTrackHref waits past a stale href for the expected one', (
    tester,
  ) async {
    final label = await _pumpLabel(tester, 'track: - stale.mp3');
    Timer(
      const Duration(milliseconds: 600),
      () => label.value = 'track: - wanted.mp3',
    );

    expect(await awaitTrackHref(tester, expected: 'wanted.mp3'), 'wanted.mp3');
  });

  testWidgets('awaitTrackHref reports what it saw when expected never comes', (
    tester,
  ) async {
    await _pumpLabel(tester, 'track: - stale.mp3');

    await expectLater(
      () => awaitTrackHref(
        tester,
        expected: 'wanted.mp3',
        timeout: const Duration(seconds: 1),
      ),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          allOf(contains('wanted.mp3'), contains('stale.mp3')),
        ),
      ),
    );
  });

  testWidgets('awaitTrackHref fails when the label never populates', (
    tester,
  ) async {
    await _pumpLabel(tester, 'track: - ');

    await expectLater(
      () => awaitTrackHref(tester, timeout: const Duration(seconds: 1)),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          contains('never delivered a track href'),
        ),
      ),
    );
  });

  testWidgets('awaitTrackHrefChange ignores a transient empty label', (
    tester,
  ) async {
    final label = await _pumpLabel(tester, 'track: - a.mp3');
    Timer(const Duration(milliseconds: 300), () => label.value = 'track: - ');
    Timer(
      const Duration(milliseconds: 900),
      () => label.value = 'track: - b.mp3',
    );

    expect(await awaitTrackHrefChange(tester, 'a.mp3'), 'b.mp3');
  });

  testWidgets('awaitTrackHrefChange fails when the href never changes', (
    tester,
  ) async {
    await _pumpLabel(tester, 'track: - a.mp3');

    await expectLater(
      () => awaitTrackHrefChange(
        tester,
        'a.mp3',
        timeout: const Duration(seconds: 1),
      ),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          contains('never changed from "a.mp3"'),
        ),
      ),
    );
  });
}
