import 'package:flureadium/flureadium.dart';
import 'package:flureadium_example/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

import 'publication_latch.dart';
import 'pump_until.dart';

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
///
/// Set [openAfterColdBoot] when a group's tests open several publications
/// through different [reopenButton]s. The cold-boot path then taps the button
/// too, so whichever test runs first gets the publication it asked for instead
/// of the one [initialAsset] happened to boot.
Future<void> ensureAppShowing(
  WidgetTester tester, {
  required String initialAsset,
  required String reopenButton,
  bool openAfterColdBoot = false,
}) async {
  if (!appAlreadyShowing(tester, reopenButton)) {
    app.main(initialAsset: initialAsset);
    await pumpUntil(
      tester,
      () => _readerMounted(tester),
      timeout: const Duration(seconds: 30),
    );
    if (!openAfterColdBoot) return;
  }
  final gen = openGeneration(tester);
  await tester.tap(find.text(reopenButton));
  await pumpUntil(
    tester,
    () => openGeneration(tester) > gen,
    timeout: const Duration(seconds: 15),
  );
}
