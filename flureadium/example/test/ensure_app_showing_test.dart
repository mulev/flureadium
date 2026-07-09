import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/helpers/ensure_app_showing.dart';

void main() {
  testWidgets('appAlreadyShowing is false on an empty tree', (tester) async {
    await tester.pumpWidget(const SizedBox());
    expect(appAlreadyShowing(tester, 'Open EPUB'), isFalse);
  });

  testWidgets('appAlreadyShowing is true when the reopen button is present', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Open EPUB'))),
    );
    expect(appAlreadyShowing(tester, 'Open EPUB'), isTrue);
  });
}
