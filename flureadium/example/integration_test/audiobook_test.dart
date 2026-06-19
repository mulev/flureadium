@Tags(['native'])
library;

import 'package:flutter/widgets.dart';
import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flureadium_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Reads the keyed current-track indicator the example surfaces from the
  // audiobook timebased state. The text is 'track: <position> <href>'.
  String currentTrack(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('current-track'))).data ?? '';

  group('Audiobook', () {
    tearDown(() async {
      final flureadium = Flureadium();
      await flureadium.stop();
      await flureadium.closePublication();
    });

    testWidgets('opens audiobook and shows reader widget', (tester) async {
      app.main();
      // app.main() auto-opens an EPUB. CircularProgressIndicator prevents
      // pumpAndSettle from settling, so poll for the reader widget instead.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook'));
      // Pump in short intervals so platform channel events get processed
      // during the audiobook switch. A single pump(10s) only processes events
      // once; frequent pumps catch native callbacks as they arrive. 15s
      // ceiling adds headroom for parallel test runs where CPU is shared.
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('audio play changes button to Audio Pause', (tester) async {
      app.main();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Audio Play'));
      // audioEnable() + play() + setState; poll for the button (max 15s).
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('audioSeekBy does not crash', (tester) async {
      app.main();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Audio Play'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('+30s'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('pause then resume restores playback', (tester) async {
      app.main();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Audio Play'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }

      await tester.tap(find.text('Audio Pause'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Resume').evaluate().isNotEmpty) break;
      }
      expect(find.text('Audio Resume'), findsOneWidget);

      await tester.tap(find.text('Audio Resume'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('chapter skip keeps playback going', (tester) async {
      // Skipping a chapter is the navigator path a head unit (Android Auto)
      // drives when the listener picks a chapter or hits next-track. This
      // guards that the MediaLibraryService migration left it working.
      app.main();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Audio Play'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }

      await tester.tap(find.text('Skip Next'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('chapter skip previous keeps playback going', (tester) async {
      // Previous-track is the other navigator path a head unit drives: on
      // Android Auto, PluginSimpleBasePlayer remaps a head-unit "previous" to a
      // backward seek. Skip Next is tested above; this guards the symmetric
      // previous path through the shared navigator.
      app.main();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Audio Play'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }

      // Advance a chapter first so there is a previous chapter to skip back to.
      await tester.tap(find.text('Skip Next'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }

      await tester.tap(find.text('Skip Prev'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets(
      'go-to-chapter across a track boundary while playing does not freeze',
      (tester) async {
        // Pre-fix repro of the chapter-transition deadlock: go(to:) fires
        // loadedTimeRangesDidChange synchronously while AVPlayer's lock is held; the
        // old delegate re-read playbackInfo -> currentTime() -> __ulock_wait. This
        // guards the cached-state fix.
        app.main();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
        }
        await tester.tap(find.text('Open AudioBook'));
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.tap(find.text('Audio Play'));
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.text('Audio Pause').evaluate().isNotEmpty) break;
        }
        // Advance to track 2 so the next go(to:) crosses a real track boundary.
        await tester.tap(find.text('Skip Next'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.text('Audio Pause').evaluate().isNotEmpty) break;
        }
        // Cross-boundary go-to while playing — the path that deadlocked pre-fix.
        await tester.tap(find.text('Ch.1'));
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.text('Audio Pause').evaluate().isNotEmpty) break;
        }
        expect(find.text('Audio Pause'), findsOneWidget);
      },
    );

    testWidgets('untitled chapter audiobook plays and skips without crashing', (
      tester,
    ) async {
      // The untitled_chapter.audiobook fixture has a second chapter with no
      // title. Skipping into it drives the real native now-playing / browse-tree
      // builders down their "Chapter N" fallback path with the actual audio
      // engine — the path that is otherwise only unit-tested with mock pubs.
      app.main();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook NoTitle'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Audio Play'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }

      // Skip into the untitled second chapter.
      await tester.tap(find.text('Skip Next'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('next chapter advances the track', (tester) async {
      // Audio Next Chapter drives Flureadium.next(), which must move to the
      // next reading-order track — not seek inside the current one. The bug
      // this guards made next() a 30s seek, so the track never changed.
      app.main();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Audio Play'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }

      final before = currentTrack(tester);

      await tester.tap(find.text('Audio Next Chapter'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (currentTrack(tester) != before) break;
      }

      // The displayed track changed and playback is still active.
      expect(currentTrack(tester), isNot(before));
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('previous chapter at first track is a no-op', (tester) async {
      // From track 1, Audio Prev Chapter must be bounded: next()/previous()
      // move exactly one track and clamp at the ends, so this leaves the
      // current track unchanged and does not crash.
      app.main();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Audio Play'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Audio Pause').evaluate().isNotEmpty) break;
      }

      final before = currentTrack(tester);

      await tester.tap(find.text('Audio Prev Chapter'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      // Still on the first track; no crash.
      expect(currentTrack(tester), before);
      expect(find.text('Audio Pause'), findsOneWidget);
    });
  });
}
