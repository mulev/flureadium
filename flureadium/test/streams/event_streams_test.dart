import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium/flureadium.dart';

import '../mocks/mock_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFlureadiumPlatform mockPlatform;
  late Flureadium flureadium;

  setUp(() {
    mockPlatform = MockFlureadiumPlatform();
    FlureadiumPlatform.instance = mockPlatform;
    flureadium = Flureadium();
  });

  tearDown(() {
    mockPlatform.dispose();
  });

  group('onTextLocatorChanged', () {
    test('emits locator events', () async {
      final locator = Locator(
        href: 'chapter1.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(position: 1, progression: 0.5),
      );

      final completer = Completer<Locator>();
      final subscription = flureadium.onTextLocatorChanged.listen((loc) {
        if (!completer.isCompleted) {
          completer.complete(loc);
        }
      });

      mockPlatform.emitTextLocator(locator);

      final received = await completer.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw TimeoutException('No locator received'),
      );

      expect(received.href, equals('chapter1.xhtml'));
      expect(received.locations?.position, equals(1));

      await subscription.cancel();
    });

    test('emits multiple locator events', () async {
      final locators = <Locator>[];
      final subscription = flureadium.onTextLocatorChanged.listen(locators.add);

      mockPlatform.emitTextLocator(
        Locator(href: 'chapter1.xhtml', type: 'text/html'),
      );

      mockPlatform.emitTextLocator(
        Locator(href: 'chapter2.xhtml', type: 'text/html'),
      );

      mockPlatform.emitTextLocator(
        Locator(href: 'chapter3.xhtml', type: 'text/html'),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(locators.length, equals(3));
      expect(locators[0].href, equals('chapter1.xhtml'));
      expect(locators[1].href, equals('chapter2.xhtml'));
      expect(locators[2].href, equals('chapter3.xhtml'));

      await subscription.cancel();
    });

    test('stream can have multiple listeners', () async {
      final locators1 = <Locator>[];
      final locators2 = <Locator>[];

      final sub1 = flureadium.onTextLocatorChanged.listen(locators1.add);
      final sub2 = flureadium.onTextLocatorChanged.listen(locators2.add);

      mockPlatform.emitTextLocator(
        Locator(href: 'test.xhtml', type: 'text/html'),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(locators1.length, equals(1));
      expect(locators2.length, equals(1));

      await sub1.cancel();
      await sub2.cancel();
    });
  });

  group('onReaderStatusChanged', () {
    test('emits reader status events', () async {
      final statuses = <ReadiumReaderStatus>[];
      final subscription = flureadium.onReaderStatusChanged.listen(
        statuses.add,
      );

      mockPlatform.emitReaderStatus(ReadiumReaderStatus.loading);
      mockPlatform.emitReaderStatus(ReadiumReaderStatus.ready);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(statuses, contains(ReadiumReaderStatus.loading));
      expect(statuses, contains(ReadiumReaderStatus.ready));

      await subscription.cancel();
    });

    test('emits all status types', () async {
      final statuses = <ReadiumReaderStatus>[];
      final subscription = flureadium.onReaderStatusChanged.listen(
        statuses.add,
      );

      mockPlatform.emitReaderStatus(ReadiumReaderStatus.loading);
      mockPlatform.emitReaderStatus(ReadiumReaderStatus.ready);
      mockPlatform.emitReaderStatus(ReadiumReaderStatus.closed);
      mockPlatform.emitReaderStatus(ReadiumReaderStatus.error);
      mockPlatform.emitReaderStatus(
        ReadiumReaderStatus.reachedEndOfPublication,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(statuses.length, equals(5));

      await subscription.cancel();
    });
  });

  group('onTimebasedPlayerStateChanged', () {
    test('emits timebased state events', () async {
      final states = <ReadiumTimebasedState>[];
      final subscription = flureadium.onTimebasedPlayerStateChanged.listen(
        states.add,
      );

      mockPlatform.emitTimebasedState(
        ReadiumTimebasedState(
          state: TimebasedState.playing,
          currentOffset: const Duration(seconds: 30),
          currentDuration: const Duration(minutes: 5),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(states.length, equals(1));
      expect(states[0].state, equals(TimebasedState.playing));
      expect(states[0].currentOffset, equals(const Duration(seconds: 30)));

      await subscription.cancel();
    });

    test('emits state transitions', () async {
      final states = <ReadiumTimebasedState>[];
      final subscription = flureadium.onTimebasedPlayerStateChanged.listen(
        states.add,
      );

      mockPlatform.emitTimebasedState(
        ReadiumTimebasedState(state: TimebasedState.loading),
      );

      mockPlatform.emitTimebasedState(
        ReadiumTimebasedState(
          state: TimebasedState.playing,
          currentOffset: const Duration(seconds: 0),
        ),
      );

      mockPlatform.emitTimebasedState(
        ReadiumTimebasedState(
          state: TimebasedState.paused,
          currentOffset: const Duration(seconds: 45),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(states.length, equals(3));
      expect(states[0].state, equals(TimebasedState.loading));
      expect(states[1].state, equals(TimebasedState.playing));
      expect(states[2].state, equals(TimebasedState.paused));

      await subscription.cancel();
    });

    test('includes locator in state', () async {
      final states = <ReadiumTimebasedState>[];
      final subscription = flureadium.onTimebasedPlayerStateChanged.listen(
        states.add,
      );

      mockPlatform.emitTimebasedState(
        ReadiumTimebasedState(
          state: TimebasedState.playing,
          currentLocator: Locator(
            href: 'audio-track.mp3',
            type: 'audio/mpeg',
            locations: Locations(fragments: ['t=120']),
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(states[0].currentLocator, isNotNull);
      expect(states[0].currentLocator!.href, equals('audio-track.mp3'));

      await subscription.cancel();
    });
  });

  group('onErrorEvent', () {
    test('emits error events', () async {
      final errors = <ReadiumError>[];
      final subscription = flureadium.onErrorEvent.listen(errors.add);

      mockPlatform.emitError(
        ReadiumError('Test error message', code: 'ERR_001'),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(errors.length, equals(1));
      expect(errors[0].message, equals('Test error message'));
      expect(errors[0].code, equals('ERR_001'));

      await subscription.cancel();
    });

    test('emits multiple errors', () async {
      final errors = <ReadiumError>[];
      final subscription = flureadium.onErrorEvent.listen(errors.add);

      mockPlatform.emitError(ReadiumError('Error 1'));
      mockPlatform.emitError(ReadiumError('Error 2'));
      mockPlatform.emitError(ReadiumError('Error 3'));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(errors.length, equals(3));

      await subscription.cancel();
    });

    test('error includes data', () async {
      final errors = <ReadiumError>[];
      final subscription = flureadium.onErrorEvent.listen(errors.add);

      mockPlatform.emitError(
        ReadiumError(
          'Error with data',
          code: 'DATA_ERR',
          data: {'context': 'chapter loading'},
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(errors[0].data, equals({'context': 'chapter loading'}));
      expect(errors[0].code, equals('DATA_ERR'));

      await subscription.cancel();
    });
  });

  group('Stream subscription management', () {
    test('subscription can be cancelled', () async {
      final locators = <Locator>[];
      final subscription = flureadium.onTextLocatorChanged.listen(locators.add);

      mockPlatform.emitTextLocator(
        Locator(href: 'before-cancel.xhtml', type: 'text/html'),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      mockPlatform.emitTextLocator(
        Locator(href: 'after-cancel.xhtml', type: 'text/html'),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(locators.length, equals(1));
      expect(locators[0].href, equals('before-cancel.xhtml'));
    });

    test('subscription can be paused and resumed', () async {
      final locators = <Locator>[];
      final subscription = flureadium.onTextLocatorChanged.listen(locators.add);

      mockPlatform.emitTextLocator(
        Locator(href: 'first.xhtml', type: 'text/html'),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      subscription.pause();

      mockPlatform.emitTextLocator(
        Locator(href: 'paused.xhtml', type: 'text/html'),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      subscription.resume();

      mockPlatform.emitTextLocator(
        Locator(href: 'resumed.xhtml', type: 'text/html'),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(locators.any((l) => l.href == 'first.xhtml'), isTrue);
      expect(locators.any((l) => l.href == 'resumed.xhtml'), isTrue);

      await subscription.cancel();
    });
  });
}
