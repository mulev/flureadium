import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/helpers/pump_until.dart';

void main() {
  testWidgets('returns true when the condition holds on the first tick', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var checks = 0;
    final result = await pumpUntil(
      tester,
      () {
        checks++;
        return true;
      },
      timeout: const Duration(seconds: 10),
      interval: const Duration(milliseconds: 250),
    );

    expect(result, isTrue);
    expect(checks, 1, reason: 'satisfied on the first tick, no extra pumps');
  });

  testWidgets('returns true when the condition becomes true partway', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var ticks = 0;
    final result = await pumpUntil(
      tester,
      () {
        ticks++;
        return ticks >= 3;
      },
      timeout: const Duration(seconds: 10),
      interval: const Duration(milliseconds: 250),
    );

    expect(result, isTrue);
    expect(ticks, 3, reason: 'stops on the tick the condition first holds');
  });

  testWidgets('returns false after timeout ~/ interval pumps when never true', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var checks = 0;
    final result = await pumpUntil(
      tester,
      () {
        checks++;
        return false;
      },
      timeout: const Duration(seconds: 1),
      interval: const Duration(milliseconds: 250),
    );

    expect(result, isFalse);
    // 4 in-loop checks (1s / 250ms) plus the final post-loop check.
    expect(checks, (1000 ~/ 250) + 1);
  });

  testWidgets('honours a custom interval and timeout', (tester) async {
    await tester.pumpWidget(const SizedBox());
    var checks = 0;
    final result = await pumpUntil(
      tester,
      () {
        checks++;
        return false;
      },
      timeout: const Duration(seconds: 2),
      interval: const Duration(milliseconds: 500),
    );

    expect(result, isFalse);
    // 4 in-loop checks (2s / 500ms) plus the final post-loop check.
    expect(checks, (2000 ~/ 500) + 1);
  });
}
