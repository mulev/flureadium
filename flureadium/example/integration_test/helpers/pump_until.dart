import 'package:flutter_test/flutter_test.dart';

/// Pumps [tester] every [interval] until [condition] returns true or the
/// cumulative wall-clock reaches [timeout], then returns whether the
/// condition held. Pump-then-check mirrors the hand-rolled loops it
/// replaces, so each caller keeps the same wall-clock ceiling — only the
/// tick granularity shrinks (1s -> 250ms), so an early-satisfied condition
/// wastes at most one 250ms tick instead of a full second.
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 60),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final iterations = timeout.inMilliseconds ~/ interval.inMilliseconds;
  for (var i = 0; i < iterations; i++) {
    await tester.pump(interval);
    if (condition()) return true;
  }
  return condition();
}
