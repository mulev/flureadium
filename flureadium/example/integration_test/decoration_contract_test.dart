import 'package:flureadium/flureadium.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/locator_latch.dart';
import 'helpers/pump_until.dart';
import 'helpers/reader_status.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('EPUB decoration contract', () {
    // Same shape as epub_test.dart: every case opens its own EPUB, so no case
    // decorates a publication another suite left mounted.
    Future<void> showEpub(WidgetTester tester) => ensureAppShowing(
      tester,
      initialAsset: 'assets/pubs/moby_dick.epub',
      reopenButton: 'Open EPUB',
      openAfterColdBoot: true,
    );

    tearDown(() async {
      await Flureadium().closePublication();
    });

    // `currentReaderWidget` is written by the reader widget's lifecycle mixin
    // when the platform view is created
    // (`flureadium/lib/src/reader/reader_lifecycle_mixin.dart:15`), which lands
    // after the open-generation bump `ensureAppShowing` waits on. Reading it on
    // that same frame is what failed on Android: the registration was still
    // null. Wait for the registration and the first locator, then read it once.
    Future<ReadiumReaderWidgetInterface> registeredReader(
      WidgetTester tester,
    ) async {
      final arrived = await pumpUntil(
        tester,
        () =>
            FlureadiumPlatform.instance.currentReaderWidget != null &&
            readerStatus(tester) == 'ready' &&
            locatorHref(tester).isNotEmpty,
        timeout: const Duration(seconds: 30),
      );
      expect(
        arrived,
        isTrue,
        reason: 'no reader widget registered with a locator',
      );
      return FlureadiumPlatform.instance.currentReaderWidget!;
    }

    testWidgets('a decoration for the current locator is accepted', (
      tester,
    ) async {
      await showEpub(tester);

      final reader = await registeredReader(tester);

      final locator = await reader.getCurrentLocator();
      expect(locator, isNotNull, reason: 'reader reported no current locator');

      // The awaited call is the assertion: a native decode failure arrives here
      // as a PlatformException, and an unawaited call would let the test pass
      // while every decoration was dropped. Nothing is asserted with a finder
      // afterwards — the widget was mounted before the call, so such a check
      // cannot fail (docs/05-testing/all-tests.md:97-146).
      await reader.applyDecorations('highlights', [
        ReaderDecoration(
          id: 'integration-highlight',
          locator: locator!,
          style: ReaderDecorationStyle(
            style: DecorationStyle.highlight,
            tint: const Color(0xFFFFFF00),
          ),
        ),
      ]);
    });

    testWidgets('a malformed decoration surfaces a PlatformException', (
      tester,
    ) async {
      await showEpub(tester);

      final reader = await registeredReader(tester);

      // `type` is the media type both platforms validate: iOS rejects it in
      // MediaType(typeString) (Pods/ReadiumShared/.../Locator.swift:76-79),
      // Android in MediaType(type) inside Locator.fromJSON. An empty one is a
      // locator Dart can build but neither native side can decode.
      final broken = ReaderDecoration(
        id: 'broken-locator',
        locator: const Locator(href: 'chapter1.xhtml', type: ''),
        style: ReaderDecorationStyle(
          style: DecorationStyle.highlight,
          tint: const Color(0xFFFFFF00),
        ),
      );

      // The message, not the code: iOS answers `JSON mapping error` while
      // Android answers the thrown exception's class name from its generic
      // handler. What both guarantee is a PlatformException whose message names
      // the decoration it could not read.
      await expectLater(
        reader.applyDecorations('highlights', [broken]),
        throwsA(
          isA<PlatformException>().having(
            (e) => '${e.message}',
            'message',
            contains('broken-locator'),
          ),
        ),
      );
    });

    testWidgets('the Highlight button leaves the reader where it was', (
      tester,
    ) async {
      await showEpub(tester);

      // _addHighlight returns early while _locator is null (main.dart:657-658),
      // so tapping before the first locator event is a no-op. Wait for the
      // latch the example renders from that same field.
      final ready = await pumpUntil(
        tester,
        () => readerStatus(tester) == 'ready' && locatorHref(tester).isNotEmpty,
        timeout: const Duration(seconds: 30),
      );
      expect(ready, isTrue, reason: 'no locator arrived to decorate');
      final before = locatorHref(tester);

      await tester.tap(find.text('Highlight'));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      // Values, not finders — the shape the night-preferences case uses. The
      // button's future is dropped by `onPressed`, so a rejected call reaches
      // the test zone as an uncaught error; decorating must not reset the
      // reader or move the position.
      expect(readerStatus(tester), equals('ready'));
      expect(locatorHref(tester), equals(before));
    });
  });
}
