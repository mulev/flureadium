import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flureadium_platform_interface/method_channel_flureadium.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelFlureadium', () {
    late MethodChannelFlureadium platform;
    late List<MethodCall> methodCalls;

    setUp(() {
      platform = MethodChannelFlureadium();
      methodCalls = [];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            methodCalls.add(call);
            return _mockResponse(call);
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, null);
    });

    group('Publication Management', () {
      test('loadPublication sends correct method and arguments', () async {
        await platform.loadPublication('file:///test.epub');

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('loadPublication'));
        expect(methodCalls.last.arguments, equals(['file:///test.epub']));
      });

      test('openPublication sends correct method and arguments', () async {
        await platform.openPublication('https://example.com/book.epub');

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('openPublication'));
        expect(
          methodCalls.last.arguments,
          equals(['https://example.com/book.epub']),
        );
      });

      test('closePublication sends correct method', () async {
        await platform.closePublication();

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('closePublication'));
      });

      test('setCustomHeaders sends correct arguments', () async {
        final headers = {'Authorization': 'Bearer token123'};

        await platform.setCustomHeaders(headers);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('setCustomHeaders'));
        expect(methodCalls.last.arguments['httpHeaders'], equals(headers));
      });

      test('getLinkContent sends JSON-encoded link', () async {
        final link = Link(
          href: 'chapter1.xhtml',
          type: 'application/xhtml+xml',
        );

        await platform.getLinkContent(link);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('getLinkContent'));
        expect(methodCalls.last.arguments[0], isA<String>());

        final decodedArg = json.decode(methodCalls.last.arguments[0] as String);
        expect(decodedArg['href'], equals('chapter1.xhtml'));
      });
    });

    group('Navigation', () {
      test('goToLocator sends locator JSON', () async {
        final locator = Locator(
          href: 'chapter2.xhtml',
          type: 'application/xhtml+xml',
          locations: Locations(position: 5, progression: 0.5),
        );

        await platform.goToLocator(locator);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('goToLocator'));

        final args = methodCalls.last.arguments as List;
        expect(args[0], isA<Map>());
        expect((args[0] as Map)['href'], equals('chapter2.xhtml'));
      });
    });

    group('TTS API', () {
      test('ttsEnable sends preferences map', () async {
        final prefs = TTSPreferences(
          speed: 1.5,
          pitch: 1.0,
          voiceIdentifier: 'voice-123',
        );

        await platform.ttsEnable(prefs);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('ttsEnable'));
        expect(methodCalls.last.arguments['speed'], equals(1.5));
        expect(methodCalls.last.arguments['pitch'], equals(1.0));
        expect(
          methodCalls.last.arguments['voiceIdentifier'],
          equals('voice-123'),
        );
      });

      test('ttsEnable sends null when no preferences', () async {
        await platform.ttsEnable(null);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('ttsEnable'));
        expect(methodCalls.last.arguments, isNull);
      });

      test('ttsGetAvailableVoices returns list of voices', () async {
        final voices = await platform.ttsGetAvailableVoices();

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('ttsGetAvailableVoices'));
        expect(voices, isA<List<ReaderTTSVoice>>());
      });

      test(
        'ttsGetAvailableVoices filters null entries from native response',
        () async {
          // iOS can return null when jsonString is nil for a voice; whereType<String>()
          // must filter those out rather than throwing a cast error.
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(platform.methodChannel, (call) async {
                methodCalls.add(call);
                if (call.method == 'ttsGetAvailableVoices') {
                  return [
                    json.encode({
                      'identifier': 'voice-1',
                      'name': 'Samantha',
                      'language': 'en-US',
                      'networkRequired': false,
                      'gender': 'female',
                      'quality': 'high',
                    }),
                    null,
                  ];
                }
                return _mockResponse(call);
              });

          final voices = await platform.ttsGetAvailableVoices();

          expect(voices.length, equals(1));
          expect(voices.first.identifier, equals('voice-1'));
        },
      );

      test('ttsSetVoice sends voice identifier and language', () async {
        await platform.ttsSetVoice('com.apple.voice.Samantha', 'en-US');

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('ttsSetVoice'));
        expect(
          methodCalls.last.arguments,
          equals(['com.apple.voice.Samantha', 'en-US']),
        );
      });

      test('ttsSetVoice sends null language when not specified', () async {
        await platform.ttsSetVoice('voice-id', null);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.arguments, equals(['voice-id', null]));
      });

      test('ttsSetPreferences sends preferences map', () async {
        final prefs = TTSPreferences(
          speed: 2.0,
          controlPanelInfoType: ControlPanelInfoType.chapterTitle,
        );

        await platform.ttsSetPreferences(prefs);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('ttsSetPreferences'));
        expect(methodCalls.last.arguments['speed'], equals(2.0));
      });

      test(
        'ttsSetPreferences sends preferences with null voiceIdentifier',
        () async {
          final prefs = TTSPreferences(speed: 1.5);

          await platform.ttsSetPreferences(prefs);

          expect(methodCalls.length, equals(1));
          expect(methodCalls.last.method, equals('ttsSetPreferences'));
          expect(methodCalls.last.arguments['speed'], equals(1.5));
          expect(methodCalls.last.arguments['voiceIdentifier'], isNull);
        },
      );

      test('ttsCanSpeak returns bool result from native', () async {
        final result = await platform.ttsCanSpeak();
        expect(methodCalls.last.method, equals('ttsCanSpeak'));
        expect(result, isA<bool>());
      });

      test('ttsRequestInstallVoice sends correct method', () async {
        await platform.ttsRequestInstallVoice();
        expect(methodCalls.last.method, equals('ttsRequestInstallVoice'));
      });

      test('setDecorationStyle sends decoration styles', () async {
        final utteranceStyle = ReaderDecorationStyle(
          style: DecorationStyle.highlight,
          tint: const Color(0xFFFFFF00),
        );

        await platform.setDecorationStyle(utteranceStyle, null);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('setDecorationStyle'));
      });
    });

    group('Playback API', () {
      test('play sends locator when provided', () async {
        final locator = Locator(
          href: 'audio.mp3',
          type: 'audio/mpeg',
          locations: Locations(fragments: ['t=120']),
        );

        await platform.play(locator);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('play'));
        expect(methodCalls.last.arguments[0], isNotNull);
      });

      test('play sends null when no locator', () async {
        await platform.play(null);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('play'));
        expect(methodCalls.last.arguments, equals([null]));
      });

      test('stop sends correct method', () async {
        await platform.stop();

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('stop'));
      });

      test('pause sends correct method', () async {
        await platform.pause();

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('pause'));
      });

      test('resume sends correct method', () async {
        await platform.resume();

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('resume'));
      });

      test('next sends correct method', () async {
        await platform.next();

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('next'));
      });

      test('previous sends correct method', () async {
        await platform.previous();

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('previous'));
      });
    });

    group('Audio API', () {
      test('audioEnable sends preferences and locator', () async {
        final prefs = AudioPreferences(
          volume: 0.8,
          speed: 1.25,
          seekInterval: 30.0,
        );
        final locator = Locator(href: 'track01.mp3', type: 'audio/mpeg');

        await platform.audioEnable(prefs: prefs, fromLocator: locator);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('audioEnable'));
        expect(methodCalls.last.arguments[0]['volume'], equals(0.8));
        expect(methodCalls.last.arguments[1]['href'], equals('track01.mp3'));
      });

      test('audioEnable sends nulls when no parameters', () async {
        await platform.audioEnable();

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('audioEnable'));
        expect(methodCalls.last.arguments, equals([null, null]));
      });

      test('audioSetPreferences sends preferences map', () async {
        final prefs = AudioPreferences(speed: 1.5, volume: 1.0);

        await platform.audioSetPreferences(prefs);

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('audioSetPreferences'));
        expect(methodCalls.last.arguments['speed'], equals(1.5));
      });

      test('audioSeekBy sends offset in seconds', () async {
        await platform.audioSeekBy(const Duration(seconds: 30));

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.method, equals('audioSeekBy'));
        expect(methodCalls.last.arguments, equals(30));
      });

      test('audioSeekBy handles negative offset', () async {
        await platform.audioSeekBy(const Duration(seconds: -15));

        expect(methodCalls.length, equals(1));
        expect(methodCalls.last.arguments, equals(-15));
      });
    });

    group('Widget Delegation', () {
      test('goLeft delegates to currentReaderWidget', () async {
        final mockWidget = MockReaderWidget();
        platform.currentReaderWidget = mockWidget;

        await platform.goLeft();

        expect(mockWidget.goLeftCalled, isTrue);
      });

      test('goRight delegates to currentReaderWidget', () async {
        final mockWidget = MockReaderWidget();
        platform.currentReaderWidget = mockWidget;

        await platform.goRight();

        expect(mockWidget.goRightCalled, isTrue);
      });

      test('skipToNext delegates to currentReaderWidget', () async {
        final mockWidget = MockReaderWidget();
        platform.currentReaderWidget = mockWidget;

        await platform.skipToNext();

        expect(mockWidget.skipToNextCalled, isTrue);
      });

      test('skipToPrevious delegates to currentReaderWidget', () async {
        final mockWidget = MockReaderWidget();
        platform.currentReaderWidget = mockWidget;

        await platform.skipToPrevious();

        expect(mockWidget.skipToPreviousCalled, isTrue);
      });

      test('setEPUBPreferences delegates to currentReaderWidget', () async {
        final mockWidget = MockReaderWidget();
        platform.currentReaderWidget = mockWidget;

        final prefs = EPUBPreferences(
          fontFamily: 'Georgia',
          fontSize: 120,
          fontWeight: 400.0,
          verticalScroll: false,
          backgroundColor: null,
          textColor: null,
        );

        await platform.setEPUBPreferences(prefs);

        expect(mockWidget.setEPUBPreferencesCalled, isTrue);
        expect(platform.defaultPreferences, equals(prefs));
      });

      test('applyDecorations delegates to currentReaderWidget', () async {
        final mockWidget = MockReaderWidget();
        platform.currentReaderWidget = mockWidget;

        await platform.applyDecorations('highlights', []);

        expect(mockWidget.applyDecorationsCalled, isTrue);
      });

      test('navigation methods handle null widget gracefully', () async {
        platform.currentReaderWidget = null;

        await platform.goLeft();
        await platform.goRight();
        await platform.skipToNext();
        await platform.skipToPrevious();

        expect(methodCalls, isEmpty);
      });
    });
  });
}

dynamic _mockResponse(MethodCall call) {
  switch (call.method) {
    case 'loadPublication':
    case 'openPublication':
      return json.encode({
        'metadata': {'title': 'Test Book'},
        'links': [],
        'readingOrder': [],
      });
    case 'goToLocator':
      return true;
    case 'ttsGetAvailableVoices':
      return <String>[
        json.encode({
          'identifier': 'voice-1',
          'name': 'Samantha',
          'language': 'en-US',
          'networkRequired': false,
          'gender': 'female',
          'quality': 'high',
        }),
      ];
    case 'ttsCanSpeak':
      return true;
    case 'ttsRequestInstallVoice':
      return null;
    case 'getLinkContent':
      return '<html><body>Content</body></html>';
    default:
      return null;
  }
}

class MockReaderWidget implements ReadiumReaderWidgetInterface {
  bool goLeftCalled = false;
  bool goRightCalled = false;
  bool skipToNextCalled = false;
  bool skipToPreviousCalled = false;
  bool setEPUBPreferencesCalled = false;
  bool applyDecorationsCalled = false;

  @override
  Future<void> go(
    Locator locator, {
    required bool isAudioBookWithText,
    bool animated = true,
  }) async {}

  @override
  Future<void> goLeft({bool animated = true}) async {
    goLeftCalled = true;
  }

  @override
  Future<void> goRight({bool animated = true}) async {
    goRightCalled = true;
  }

  @override
  Future<void> skipToNext({bool animated = true}) async {
    skipToNextCalled = true;
  }

  @override
  Future<void> skipToPrevious({bool animated = true}) async {
    skipToPreviousCalled = true;
  }

  @override
  Future<Locator?> getCurrentLocator() async => null;

  @override
  Future<Locator?> getLocatorFragments(Locator locator) async => null;

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    setEPUBPreferencesCalled = true;
  }

  bool setPDFPreferencesCalled = false;

  @override
  Future<void> setPDFPreferences(PDFPreferences preferences) async {
    setPDFPreferencesCalled = true;
  }

  bool setNavigationConfigCalled = false;

  @override
  Future<void> setNavigationConfig(ReaderNavigationConfig config) async {
    setNavigationConfigCalled = true;
  }

  @override
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) async {
    applyDecorationsCalled = true;
  }
}
