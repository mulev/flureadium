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

  // Reads the keyed end-of-book latch. The example sets this once it has ever
  // seen TimebasedState.ended, because the player can settle to `paused`
  // immediately after `ended` and a polled resting state would miss it.
  bool endedSeen(WidgetTester tester) =>
      (tester.widget<Text>(find.byKey(const Key('ended-seen'))).data ?? '')
          .contains('true');

  // Reads the keyed position indicator: 'pos: <ms> dur: <ms>'. Returns the
  // parsed (offset, duration) in milliseconds, or -1 for either when unknown.
  ({int posMs, int durMs}) timebasedPosition(WidgetTester tester) {
    final text =
        tester.widget<Text>(find.byKey(const Key('timebased-position'))).data ??
        '';
    final match = RegExp(r'pos: (-?\d+) dur: (-?\d+)').firstMatch(text);
    if (match == null) return (posMs: -1, durMs: -1);
    return (
      posMs: int.parse(match.group(1)!),
      durMs: int.parse(match.group(2)!),
    );
  }

  // Reads the keyed error indicator the example latches from onErrorEvent.
  // The text is 'audio-error: <message>'; empty until an error surfaces.
  String lastAudioError(WidgetTester tester) =>
      (tester.widget<Text>(find.byKey(const Key('audio-error'))).data ?? '')
          .replaceFirst('audio-error: ', '');

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

    testWidgets('audiobook reaches ended state at end of book', (tester) async {
      // Playing the last track to its natural end must surface
      // TimebasedState.ended — the signal fablum turns into its completion
      // popup. Guards the iOS (shouldPlayNextResource) and Android (forward
      // Ended before teardown) fixes end-to-end.
      //
      // iOS only emits .ended from the end-of-resource hook, which fires when
      // the player reaches the end while playing — NOT when a seek lands past
      // it (that clamps to paused). So advance to the last track, seek to just
      // before its end, and let it play out naturally instead of over-seeking.
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

      // Advance to the last track: next() clamps at the end, so keep skipping
      // until the surfaced track stops changing.
      var previousTrack = currentTrack(tester);
      for (var skip = 0; skip < 12; skip++) {
        await tester.tap(find.text('Audio Next Chapter'));
        var changed = false;
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (currentTrack(tester) != previousTrack) {
            changed = true;
            break;
          }
        }
        if (!changed) break; // already at the last track
        previousTrack = currentTrack(tester);
      }

      // Wait for the last track's duration to be reported.
      for (var i = 0; i < 10; i++) {
        if (timebasedPosition(tester).durMs > 0) break;
        await tester.pump(const Duration(seconds: 1));
      }
      final pos = timebasedPosition(tester);
      expect(pos.durMs, greaterThan(0), reason: 'duration should be known');

      // Seek to ~3s before the end so the remaining audio plays out and the
      // engine fires its natural end-of-resource callback. +30s is the only
      // seek-forward control, so step forward until within the last 30s.
      const tailMs = 3000;
      for (var seek = 0; seek < 20; seek++) {
        final p = timebasedPosition(tester);
        if (p.durMs <= 0 || p.durMs - p.posMs <= 30000 + tailMs) break;
        await tester.tap(find.text('+30s'));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }

      // Let the last track play out; the ended latch must flip within a
      // bounded window. The latch (not the resting state) is asserted because
      // the player can settle to `paused` the instant after emitting `ended`.
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (endedSeen(tester)) break;
      }

      expect(endedSeen(tester), isTrue);
    });

    testWidgets('unreachable streamed audio surfaces an error event', (
      tester,
    ) async {
      // Regression for the streaming-error observability gap: an audio resource
      // that fails to load must surface on onErrorEvent (Phase 2) instead of
      // the player stalling silently at 0:00 with nothing logged. The example's
      // 'Open AudioBook BadUrl' opens a manifest whose only track points at an
      // unreachable host, so the first load fails inside AVFoundation.
      app.main();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(ReadiumReaderWidget).evaluate().isNotEmpty) break;
      }
      await tester.tap(find.text('Open AudioBook BadUrl'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Audio Play'));

      // Poll the latched error indicator: the failed load surfaces via
      // didFailToLoadResourceAt or the AVFoundation failure notifications.
      var surfaced = false;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (lastAudioError(tester).isNotEmpty) {
          surfaced = true;
          break;
        }
      }
      expect(
        surfaced,
        isTrue,
        reason: 'a failed streamed audio load must surface on onErrorEvent',
      );
    });
  });
}
