import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flureadium/src/web/web_stream_handlers.dart';

void main() {
  group('WebStreamHandlers', () {
    group('text locator stream', () {
      test('broadcasts text locator updates', () async {
        final testLocator = Locator(href: 'chapter1.html', type: 'text/html');

        // Listen to stream
        final streamFuture = WebStreamHandlers.onTextLocatorChanged.first;

        // Add update
        WebStreamHandlers.addTextLocatorUpdate(testLocator);

        // Verify received
        final received = await streamFuture;
        expect(received.href, equals('chapter1.html'));
      });

      test('broadcasts multiple text locator updates', () async {
        final locators = <Locator>[];
        final subscription = WebStreamHandlers.onTextLocatorChanged.listen((
          locator,
        ) {
          locators.add(locator);
        });

        // Add multiple updates
        WebStreamHandlers.addTextLocatorUpdate(
          Locator(href: 'chapter1.html', type: 'text/html'),
        );
        WebStreamHandlers.addTextLocatorUpdate(
          Locator(href: 'chapter2.html', type: 'text/html'),
        );
        WebStreamHandlers.addTextLocatorUpdate(
          Locator(href: 'chapter3.html', type: 'text/html'),
        );

        await pumpEventQueue();

        expect(locators, hasLength(3));
        expect(locators[0].href, equals('chapter1.html'));
        expect(locators[1].href, equals('chapter2.html'));
        expect(locators[2].href, equals('chapter3.html'));

        await subscription.cancel();
      });

      test('supports multiple listeners', () async {
        final testLocator = Locator(href: 'test.html', type: 'text/html');

        final future1 = WebStreamHandlers.onTextLocatorChanged.first;
        final future2 = WebStreamHandlers.onTextLocatorChanged.first;

        WebStreamHandlers.addTextLocatorUpdate(testLocator);

        final [received1, received2] = await Future.wait([future1, future2]);
        expect(received1.href, equals('test.html'));
        expect(received2.href, equals('test.html'));
      });
    });

    group('timebased state stream', () {
      test('broadcasts timebased state updates', () async {
        final testState = ReadiumTimebasedState(
          state: TimebasedState.playing,
          currentOffset: const Duration(seconds: 10),
        );

        final streamFuture =
            WebStreamHandlers.onTimebasedPlayerStateChanged.first;

        WebStreamHandlers.addTimeBasedStateUpdate(testState);

        final received = await streamFuture;
        expect(received.state, equals(TimebasedState.playing));
        expect(received.currentOffset, equals(const Duration(seconds: 10)));
      });

      test('broadcasts multiple state updates', () async {
        final states = <ReadiumTimebasedState>[];
        final subscription = WebStreamHandlers.onTimebasedPlayerStateChanged
            .listen((state) {
              states.add(state);
            });

        WebStreamHandlers.addTimeBasedStateUpdate(
          ReadiumTimebasedState(state: TimebasedState.playing),
        );
        WebStreamHandlers.addTimeBasedStateUpdate(
          ReadiumTimebasedState(state: TimebasedState.paused),
        );

        await pumpEventQueue();

        expect(states, hasLength(2));
        expect(states[0].state, equals(TimebasedState.playing));
        expect(states[1].state, equals(TimebasedState.paused));

        await subscription.cancel();
      });
    });

    group('reader status stream', () {
      test('broadcasts reader status updates', () async {
        const testStatus = ReadiumReaderStatus.ready;

        final streamFuture = WebStreamHandlers.onReaderStatusChanged.first;

        WebStreamHandlers.addReaderStatusUpdate(testStatus);

        final received = await streamFuture;
        expect(received, equals(ReadiumReaderStatus.ready));
        expect(received.isReady, isTrue);
      });

      test('broadcasts multiple status updates', () async {
        final statuses = <ReadiumReaderStatus>[];
        final subscription = WebStreamHandlers.onReaderStatusChanged.listen((
          status,
        ) {
          statuses.add(status);
        });

        WebStreamHandlers.addReaderStatusUpdate(ReadiumReaderStatus.loading);
        WebStreamHandlers.addReaderStatusUpdate(ReadiumReaderStatus.ready);

        await pumpEventQueue();

        expect(statuses, hasLength(2));
        expect(statuses[0], equals(ReadiumReaderStatus.loading));
        expect(statuses[1], equals(ReadiumReaderStatus.ready));

        await subscription.cancel();
      });
    });

    group('concurrent streams', () {
      test('handles updates to multiple streams independently', () async {
        final locatorFuture = WebStreamHandlers.onTextLocatorChanged.first;
        final stateFuture =
            WebStreamHandlers.onTimebasedPlayerStateChanged.first;
        final statusFuture = WebStreamHandlers.onReaderStatusChanged.first;

        WebStreamHandlers.addTextLocatorUpdate(
          Locator(href: 'chapter1.html', type: 'text/html'),
        );
        WebStreamHandlers.addTimeBasedStateUpdate(
          ReadiumTimebasedState(state: TimebasedState.playing),
        );
        WebStreamHandlers.addReaderStatusUpdate(ReadiumReaderStatus.ready);

        final results = await Future.wait([
          locatorFuture,
          stateFuture,
          statusFuture,
        ]);

        expect((results[0] as Locator).href, equals('chapter1.html'));
        expect(
          (results[1] as ReadiumTimebasedState).state,
          equals(TimebasedState.playing),
        );
        expect(results[2], equals(ReadiumReaderStatus.ready));
      });
    });
  });
}
