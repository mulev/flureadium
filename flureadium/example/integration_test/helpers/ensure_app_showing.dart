import 'package:flureadium/flureadium.dart';
import 'package:flureadium_example/main.dart' as app;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_until.dart';

int _openGeneration(WidgetTester tester) =>
    int.tryParse(
      (tester.widget<Text>(find.byKey(const Key('open-generation'))).data ?? '')
          .replaceFirst('open-generation: ', ''),
    ) ??
    0;

bool _readerMounted(WidgetTester tester) =>
    find.byType(ReadiumReaderWidget).evaluate().isNotEmpty;

/// Whether the example app is already on screen: either its reader view is
/// mounted, or (after a tearDown that closed the publication) its control bar
/// with the reopen button is showing. Derived from the widget tree, so no
/// module-global flag leaks across files or suite re-runs.
bool appAlreadyShowing(WidgetTester tester, String reopenButton) =>
    _readerMounted(tester) || find.text(reopenButton).evaluate().isNotEmpty;

/// Ensures the example app is on screen showing the wanted publication.
///
/// The first call in a suite cold-boots the app via [initialAsset]. Later calls
/// reuse the already-running app and switch publications by tapping
/// [reopenButton], waiting on the open-generation bump — the uniform "loaded"
/// signal every open exposes after the `_openPublicationAsset` change. Lets a
/// test group boot once and reuse the app between tests instead of paying a
/// fresh boot per test.
Future<void> ensureAppShowing(
  WidgetTester tester, {
  required String initialAsset,
  required String reopenButton,
}) async {
  if (!appAlreadyShowing(tester, reopenButton)) {
    app.main(initialAsset: initialAsset);
    await pumpUntil(
      tester,
      () => _readerMounted(tester),
      timeout: const Duration(seconds: 30),
    );
    return;
  }
  final gen = _openGeneration(tester);
  await tester.tap(find.text(reopenButton));
  await pumpUntil(
    tester,
    () => _openGeneration(tester) > gen,
    timeout: const Duration(seconds: 15),
  );
}
