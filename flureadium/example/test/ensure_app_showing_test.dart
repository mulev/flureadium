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

  testWidgets(
    'ensureAppShowing reopens via the button when the app is already showing',
    (tester) async {
      // Reuse path: the app is up, so ensureAppShowing must tap the reopen
      // button and wait for the open-generation bump instead of cold booting.
      // openAfterColdBoot: true must not short-circuit this path.
      await tester.pumpWidget(const _ReopenStub());

      await ensureAppShowing(
        tester,
        initialAsset: 'unused-when-already-showing',
        reopenButton: 'Reopen',
        openAfterColdBoot: true,
      );

      expect(find.text('open-generation: 1'), findsOneWidget);
    },
  );
}

// Minimal stand-in for the example app's control bar: a reopen button that
// bumps the keyed open-generation counter ensureAppShowing polls on reuse.
class _ReopenStub extends StatefulWidget {
  const _ReopenStub();

  @override
  State<_ReopenStub> createState() => _ReopenStubState();
}

class _ReopenStubState extends State<_ReopenStub> {
  int _gen = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(key: const Key('open-generation'), 'open-generation: $_gen'),
          TextButton(
            onPressed: () => setState(() => _gen++),
            child: const Text('Reopen'),
          ),
        ],
      ),
    ),
  );
}
