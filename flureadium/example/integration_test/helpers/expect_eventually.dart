import 'package:flutter_test/flutter_test.dart';

import 'pump_until.dart';

/// Pumps until [condition] holds, failing with [reason] when it never does.
///
/// [pumpUntil] reports a timeout in its return value, so every wait has to
/// assert that value or a never-satisfied condition passes silently.
///
/// The default ceiling is a hang guard, not a budget: this returns as soon as
/// [condition] holds, so a wait that takes 2 s costs 2 s. It is sized for a
/// host running both platform legs at once — `run_integration_tests.sh
/// --parallel` puts an emulator and a simulator on the same CPU, and the 15 s
/// it replaces lost that race on 2026-09-29, failing `epub_navigation_test`'s
/// fifth skip on a tree whose only changes were test-side.
Future<void> expectEventually(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final satisfied = await pumpUntil(tester, condition, timeout: timeout);
  expect(satisfied, isTrue, reason: reason);
}
