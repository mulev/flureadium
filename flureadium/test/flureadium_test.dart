import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium/flureadium.dart';

import 'mocks/mock_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Flureadium flureadium;
  late MockFlureadiumPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockFlureadiumPlatform();
    FlureadiumPlatform.instance = mockPlatform;
    flureadium = Flureadium();
  });

  tearDown(() {
    mockPlatform.dispose();
  });

  group('Flureadium', () {
    group('Publication Management', () {
      test('loadPublication calls platform method', () async {
        final publication = await flureadium.loadPublication(
          'file:///test.epub',
        );

        expect(mockPlatform.wasCalled('loadPublication'), isTrue);
        expect(publication.metadata.title, equals('Test Book'));
      });

      test('openPublication calls platform method', () async {
        final publication = await flureadium.openPublication(
          'https://example.com/book.epub',
        );

        expect(mockPlatform.wasCalled('openPublication'), isTrue);
        expect(
          mockPlatform.lastCallArgs('openPublication')?['pubUrl'],
          equals('https://example.com/book.epub'),
        );
        expect(publication.metadata.title, equals('Test Book'));
      });

      test('closePublication calls platform method', () async {
        await flureadium.closePublication();

        expect(mockPlatform.wasCalled('closePublication'), isTrue);
      });

      test('setCustomHeaders calls platform method', () async {
        final headers = {'Authorization': 'Bearer token'};

        await flureadium.setCustomHeaders(headers);

        expect(mockPlatform.wasCalled('setCustomHeaders'), isTrue);
        expect(
          mockPlatform.lastCallArgs('setCustomHeaders')?['headers'],
          equals(headers),
        );
      });
    });

    group('Navigation', () {
      test('goLeft calls platform method', () async {
        await flureadium.goLeft();

        expect(mockPlatform.wasCalled('goLeft'), isTrue);
      });

      test('goRight calls platform method', () async {
        await flureadium.goRight();

        expect(mockPlatform.wasCalled('goRight'), isTrue);
      });

      test('skipToNext calls platform method', () async {
        await flureadium.skipToNext();

        expect(mockPlatform.wasCalled('skipToNext'), isTrue);
      });

      test('skipToPrevious calls platform method', () async {
        await flureadium.skipToPrevious();

        expect(mockPlatform.wasCalled('skipToPrevious'), isTrue);
      });

      test('goToLocator calls platform method with correct locator', () async {
        final locator = Locator(
          href: 'chapter2.xhtml',
          type: 'application/xhtml+xml',
          locations: Locations(position: 5),
        );

        final result = await flureadium.goToLocator(locator);

        expect(mockPlatform.wasCalled('goToLocator'), isTrue);
        expect(result, isTrue);
      });
    });

    group('Preferences', () {
      test('setDefaultPreferences calls platform method', () {
        final prefs = EPUBPreferences(
          fontFamily: 'Georgia',
          fontSize: 120,
          fontWeight: 400.0,
          verticalScroll: false,
          backgroundColor: const Color(0xFFFFFFFF),
          textColor: const Color(0xFF000000),
        );

        flureadium.setDefaultPreferences(prefs);

        expect(mockPlatform.wasCalled('setDefaultPreferences'), isTrue);
        expect(mockPlatform.defaultPreferences, equals(prefs));
      });

      test('setDefaultPdfPreferences calls platform method', () {
        final prefs = PDFPreferences(
          fit: PDFFit.width,
          scrollMode: PDFScrollMode.horizontal,
        );

        flureadium.setDefaultPdfPreferences(prefs);

        expect(mockPlatform.wasCalled('setDefaultPdfPreferences'), isTrue);
        expect(mockPlatform.defaultPdfPreferences, equals(prefs));
      });

      test('setDefaultPdfPreferences stores preferences in platform', () {
        final prefs = PDFPreferences(fit: PDFFit.contain);

        flureadium.setDefaultPdfPreferences(prefs);

        expect(mockPlatform.defaultPdfPreferences?.fit, equals(PDFFit.contain));
      });

      test('setEPUBPreferences calls platform method', () async {
        final prefs = EPUBPreferences(
          fontFamily: 'Arial',
          fontSize: 100,
          fontWeight: 300.0,
          verticalScroll: true,
          backgroundColor: null,
          textColor: null,
        );

        await flureadium.setEPUBPreferences(prefs);

        expect(mockPlatform.wasCalled('setEPUBPreferences'), isTrue);
      });

      test('applyDecorations calls platform method', () async {
        final decorations = [
          ReaderDecoration(
            id: 'highlight-1',
            locator: Locator(href: 'chapter1.xhtml', type: 'text/html'),
            style: ReaderDecorationStyle(
              style: DecorationStyle.highlight,
              tint: const Color(0xFFFFFF00),
            ),
          ),
        ];

        await flureadium.applyDecorations('highlights', decorations);

        expect(mockPlatform.wasCalled('applyDecorations'), isTrue);
        expect(
          mockPlatform.lastCallArgs('applyDecorations')?['id'],
          equals('highlights'),
        );
      });
    });

    group('Playback', () {
      test('play calls platform method', () async {
        await flureadium.play(null);

        expect(mockPlatform.wasCalled('play'), isTrue);
      });

      test('play with locator calls platform method', () async {
        final locator = Locator(href: 'chapter1.xhtml', type: 'text/html');

        await flureadium.play(locator);

        expect(mockPlatform.wasCalled('play'), isTrue);
        expect(
          mockPlatform.lastCallArgs('play')?['fromLocator'],
          equals(locator),
        );
      });

      test('pause calls platform method', () async {
        await flureadium.pause();

        expect(mockPlatform.wasCalled('pause'), isTrue);
      });

      test('resume calls platform method', () async {
        await flureadium.resume();

        expect(mockPlatform.wasCalled('resume'), isTrue);
      });

      test('stop calls platform method', () async {
        await flureadium.stop();

        expect(mockPlatform.wasCalled('stop'), isTrue);
      });

      test('next calls platform method', () async {
        await flureadium.next();

        expect(mockPlatform.wasCalled('next'), isTrue);
      });

      test('previous calls platform method', () async {
        await flureadium.previous();

        expect(mockPlatform.wasCalled('previous'), isTrue);
      });
    });

    group('TTS', () {
      test('ttsEnable calls platform method', () async {
        final prefs = TTSPreferences(speed: 1.5, pitch: 1.0);

        await flureadium.ttsEnable(prefs);

        expect(mockPlatform.wasCalled('ttsEnable'), isTrue);
      });

      test('ttsEnable with null preferences', () async {
        await flureadium.ttsEnable(null);

        expect(mockPlatform.wasCalled('ttsEnable'), isTrue);
      });

      test('ttsEnable with fromLocator passes locator to platform', () async {
        final prefs = TTSPreferences(speed: 1.5, pitch: 1.0);
        final locator = Locator(
          href: 'chapter3.xhtml',
          type: 'application/xhtml+xml',
        );

        await flureadium.ttsEnable(prefs, fromLocator: locator);

        expect(mockPlatform.wasCalled('ttsEnable'), isTrue);
        expect(
          mockPlatform.lastCallArgs('ttsEnable')?['fromLocator'],
          equals(locator),
        );
      });

      test('ttsGetAvailableVoices calls platform method', () async {
        mockPlatform.mockVoices = [
          ReaderTTSVoice(
            identifier: 'voice-1',
            name: 'Samantha',
            language: 'en-US',
            networkRequired: false,
            gender: TTSVoiceGender.female,
            quality: TTSVoiceQuality.high,
          ),
        ];

        final voices = await flureadium.ttsGetAvailableVoices();

        expect(mockPlatform.wasCalled('ttsGetAvailableVoices'), isTrue);
        expect(voices.single.identifier, equals('voice-1'));
        expect(voices.single.language, equals('en-US'));
      });

      test('ttsGetSystemVoices calls platform method', () async {
        mockPlatform.mockVoices = [
          ReaderTTSVoice(
            identifier: 'system-voice-1',
            name: 'Alex',
            language: 'en-GB',
            networkRequired: false,
            gender: TTSVoiceGender.male,
            quality: TTSVoiceQuality.normal,
          ),
        ];

        final voices = await flureadium.ttsGetSystemVoices();

        expect(mockPlatform.wasCalled('ttsGetSystemVoices'), isTrue);
        expect(voices.single.identifier, equals('system-voice-1'));
        expect(voices.single.language, equals('en-GB'));
      });

      test('ttsSetVoice calls platform method', () async {
        await flureadium.ttsSetVoice('voice-id', 'en-US');

        expect(mockPlatform.wasCalled('ttsSetVoice'), isTrue);
        expect(
          mockPlatform.lastCallArgs('ttsSetVoice')?['voiceIdentifier'],
          equals('voice-id'),
        );
        expect(
          mockPlatform.lastCallArgs('ttsSetVoice')?['forLanguage'],
          equals('en-US'),
        );
      });

      test('ttsSetPreferences calls platform method', () async {
        final prefs = TTSPreferences(
          speed: 2.0,
          controlPanelInfoType: ControlPanelInfoType.chapterTitle,
        );

        await flureadium.ttsSetPreferences(prefs);

        expect(mockPlatform.wasCalled('ttsSetPreferences'), isTrue);
      });

      test('ttsCanSpeak delegates to platform', () async {
        final result = await flureadium.ttsCanSpeak();

        expect(mockPlatform.wasCalled('ttsCanSpeak'), isTrue);
        expect(result, isTrue);
      });

      test('ttsRequestInstallVoice delegates to platform', () async {
        await flureadium.ttsRequestInstallVoice();

        expect(mockPlatform.wasCalled('ttsRequestInstallVoice'), isTrue);
      });

      test('setDecorationStyle calls platform method', () async {
        final style = ReaderDecorationStyle(
          style: DecorationStyle.underline,
          tint: const Color(0xFF0000FF),
        );

        await flureadium.setDecorationStyle(style, null);

        expect(mockPlatform.wasCalled('setDecorationStyle'), isTrue);
      });
    });

    group('Audio', () {
      test('audioEnable calls platform method', () async {
        final prefs = AudioPreferences(volume: 0.8, speed: 1.25);

        await flureadium.audioEnable(prefs: prefs);

        expect(mockPlatform.wasCalled('audioEnable'), isTrue);
      });

      test('audioEnable with locator', () async {
        final locator = Locator(href: 'track01.mp3', type: 'audio/mpeg');

        await flureadium.audioEnable(fromLocator: locator);

        expect(mockPlatform.wasCalled('audioEnable'), isTrue);
        expect(
          mockPlatform.lastCallArgs('audioEnable')?['fromLocator'],
          equals(locator),
        );
      });

      test('audioSetPreferences calls platform method', () async {
        final prefs = AudioPreferences(speed: 1.5, seekInterval: 30.0);

        await flureadium.audioSetPreferences(prefs);

        expect(mockPlatform.wasCalled('audioSetPreferences'), isTrue);
      });

      test('audioSeekBy calls platform method', () async {
        await flureadium.audioSeekBy(const Duration(seconds: 30));

        expect(mockPlatform.wasCalled('audioSeekBy'), isTrue);
        expect(
          mockPlatform.lastCallArgs('audioSeekBy')?['offset'],
          equals(const Duration(seconds: 30)),
        );
      });

      test('audioSeekBy with negative offset', () async {
        await flureadium.audioSeekBy(const Duration(seconds: -15));

        expect(mockPlatform.wasCalled('audioSeekBy'), isTrue);
        expect(
          mockPlatform.lastCallArgs('audioSeekBy')?['offset'],
          equals(const Duration(seconds: -15)),
        );
      });
    });

    group('Extract Page Thumbnail', () {
      test(
        'extractPageThumbnail forwards args and returns platform bytes',
        () async {
          mockPlatform.mockExtractPageThumbnailResult = Uint8List.fromList([
            0xFF,
            0xD8,
            0xAA,
          ]);

          final result = await flureadium.extractPageThumbnail(
            'OEBPS/page-3.jpg',
            80,
            70,
          );

          expect(mockPlatform.wasCalled('extractPageThumbnail'), isTrue);
          expect(
            mockPlatform.lastCallArgs('extractPageThumbnail')?['href'],
            equals('OEBPS/page-3.jpg'),
          );
          expect(
            mockPlatform.lastCallArgs('extractPageThumbnail')?['maxHeight'],
            equals(80),
          );
          expect(
            mockPlatform.lastCallArgs('extractPageThumbnail')?['quality'],
            equals(70),
          );
          expect(result, isNotNull);
          expect(result!.length, equals(3));
          expect(result[0], equals(0xFF));
        },
      );

      test(
        'extractPageThumbnail returns null when platform returns null',
        () async {
          mockPlatform.mockExtractPageThumbnailResult = null;

          final result = await flureadium.extractPageThumbnail(
            'OEBPS/missing.jpg',
            80,
            70,
          );

          expect(result, isNull);
        },
      );
    });

    group('Render First Page', () {
      test(
        'renderFirstPage calls platform method with correct arguments',
        () async {
          mockPlatform.mockRenderFirstPageResult = Uint8List.fromList([
            1,
            2,
            3,
          ]);

          final result = await flureadium.renderFirstPage(
            'file:///test.pdf',
            maxWidth: 300,
            maxHeight: 400,
          );

          expect(mockPlatform.wasCalled('renderFirstPage'), isTrue);
          expect(
            mockPlatform.lastCallArgs('renderFirstPage')?['pubUrl'],
            equals('file:///test.pdf'),
          );
          expect(
            mockPlatform.lastCallArgs('renderFirstPage')?['maxWidth'],
            equals(300),
          );
          expect(
            mockPlatform.lastCallArgs('renderFirstPage')?['maxHeight'],
            equals(400),
          );
          expect(result, isNotNull);
          expect(result!.length, equals(3));
        },
      );

      test('renderFirstPage uses default dimensions', () async {
        await flureadium.renderFirstPage('file:///test.pdf');

        expect(
          mockPlatform.lastCallArgs('renderFirstPage')?['maxWidth'],
          equals(600),
        );
        expect(
          mockPlatform.lastCallArgs('renderFirstPage')?['maxHeight'],
          equals(800),
        );
      });

      test('renderFirstPage returns null when platform returns null', () async {
        mockPlatform.mockRenderFirstPageResult = null;

        final result = await flureadium.renderFirstPage('file:///test.pdf');

        expect(result, isNull);
      });
    });

    group('Method call tracking', () {
      test('clearCalls resets call history', () async {
        await flureadium.goLeft();
        await flureadium.goRight();

        expect(mockPlatform.callCount('goLeft'), equals(1));
        expect(mockPlatform.callCount('goRight'), equals(1));

        mockPlatform.clearCalls();

        expect(mockPlatform.callCount('goLeft'), equals(0));
        expect(mockPlatform.callCount('goRight'), equals(0));
      });

      test('callsTo returns all calls to a method', () async {
        await flureadium.goLeft();
        await flureadium.goRight();
        await flureadium.goLeft();

        final leftCalls = mockPlatform.callsTo('goLeft');

        expect(leftCalls.length, equals(2));
      });
    });
  });
}
