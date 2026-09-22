import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the keyed latch the example updates from onReaderStatusChanged.
///
/// The text is `reader-status: <name>`; empty until a status arrives.
String readerStatus(WidgetTester tester) =>
    (tester.widget<Text>(find.byKey(const Key('reader-status'))).data ?? '')
        .replaceFirst('reader-status: ', '');

/// Reads the ordered statuses the current publication has reported.
///
/// The text is `reader-status-history: closed>loading>ready`; empty until a
/// status arrives. Sampling [readerStatus] per frame cannot prove a load
/// happened — an open that starts and finishes between two pumps only ever
/// renders as `ready` — so a test that needs the load itself asserts on this.
List<String> readerStatusHistory(WidgetTester tester) {
  final raw =
      (tester
                  .widget<Text>(find.byKey(const Key('reader-status-history')))
                  .data ??
              '')
          .replaceFirst('reader-status-history: ', '');
  return raw.isEmpty ? const [] : raw.split('>');
}
