import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the keyed latch the example updates from onReaderStatusChanged.
///
/// The text is `reader-status: <name>`; empty until a status arrives.
String readerStatus(WidgetTester tester) =>
    (tester.widget<Text>(find.byKey(const Key('reader-status'))).data ?? '')
        .replaceFirst('reader-status: ', '');
