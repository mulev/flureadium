@Tags(['native'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flureadium/flureadium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/ensure_app_showing.dart';
import 'helpers/pump_until.dart';

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

  // Reads the keyed latch the streamed-audio fixture flips when the client
  // cancels an in-flight range request (see StreamedAudioServer). Lets the
  // cancelled-read test confirm a cancellation actually happened, so its
  // no-error assertion is not vacuous.
  bool cancelledStreamDisconnectSeen(WidgetTester tester) =>
      (tester
                  .widget<Text>(
                    find.byKey(const Key('cancelled-stream-disconnect-seen')),
                  )
                  .data ??
              '')
          .contains('true');

  // Boots (or reuses) the app and opens the wanted audiobook. On Android the
  // reader widget must host an EPUB, so an audiobook cannot be a direct
  // initialAsset boot: the group cold-boots the host EPUB and then opens the
  // audiobook via [button]. openAfterColdBoot makes the cold-boot path tap
  // [button] too, so both cold and reuse calls end on a freshly opened
  // audiobook — its open-generation bump being the observable "loaded" signal.
  Future<void> showAudiobook(
    WidgetTester tester, {
    String button = 'Open AudioBook',
  }) => ensureAppShowing(
    tester,
    initialAsset: 'assets/pubs/moby_dick.epub',
    reopenButton: button,
    openAfterColdBoot: true,
  );

  // Waits for playback to report as active ('Audio Pause' shows while playing).
  Future<void> waitForPlaying(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 15),
  }) => pumpUntil(
    tester,
    () => find.text('Audio Pause').evaluate().isNotEmpty,
    timeout: timeout,
  );

  group('Audiobook', () {
    tearDown(() async {
      // Stop playback but leave the publication open. The next test's
      // ensureAppShowing switches publications via the Open button, exactly as a
      // user opening another book does — the app-accurate teardown. Closing the
      // container here while the reader widget is still mounted is a sequence the
      // app never performs, and on Android it races the live WebView still
      // reading the container (flureadium-i0s).
      await Flureadium().stop();
    });

    testWidgets('opens audiobook and shows reader widget', (tester) async {
      await showAudiobook(tester);
      expect(find.byType(ReadiumReaderWidget), findsOneWidget);
    });

    testWidgets('audio play changes button to Audio Pause', (tester) async {
      await showAudiobook(tester);
      await tester.tap(find.text('Audio Play'));
      // audioEnable() + play() + setState; poll for the button (max 15s).
      await waitForPlaying(tester);
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('audioSeekBy does not crash', (tester) async {
      await showAudiobook(tester);
      await tester.tap(find.text('Audio Play'));
      await waitForPlaying(tester);
      await tester.tap(find.text('+30s'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('pause then resume restores playback', (tester) async {
      await showAudiobook(tester);
      await tester.tap(find.text('Audio Play'));
      await waitForPlaying(tester);

      await tester.tap(find.text('Audio Pause'));
      await pumpUntil(
        tester,
        () => find.text('Audio Resume').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 5),
      );
      expect(find.text('Audio Resume'), findsOneWidget);

      await tester.tap(find.text('Audio Resume'));
      await waitForPlaying(tester, timeout: const Duration(seconds: 5));
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('chapter skip keeps playback going', (tester) async {
      // Skipping a chapter is the navigator path a head unit (Android Auto)
      // drives when the listener picks a chapter or hits next-track. This
      // guards that the MediaLibraryService migration left it working.
      await showAudiobook(tester);
      await tester.tap(find.text('Audio Play'));
      await waitForPlaying(tester);

      await tester.tap(find.text('Skip Next'));
      await waitForPlaying(tester, timeout: const Duration(seconds: 10));
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('chapter skip previous keeps playback going', (tester) async {
      // Previous-track is the other navigator path a head unit drives: on
      // Android Auto, PluginSimpleBasePlayer remaps a head-unit "previous" to a
      // backward seek. Skip Next is tested above; this guards the symmetric
      // previous path through the shared navigator.
      await showAudiobook(tester);
      await tester.tap(find.text('Audio Play'));
      await waitForPlaying(tester);

      // Advance a chapter first so there is a previous chapter to skip back to.
      await tester.tap(find.text('Skip Next'));
      await waitForPlaying(tester, timeout: const Duration(seconds: 10));

      await tester.tap(find.text('Skip Prev'));
      await waitForPlaying(tester, timeout: const Duration(seconds: 10));
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets(
      'go-to-chapter across a track boundary while playing does not freeze',
      (tester) async {
        // Pre-fix repro of the chapter-transition deadlock: go(to:) fires
        // loadedTimeRangesDidChange synchronously while AVPlayer's lock is held; the
        // old delegate re-read playbackInfo -> currentTime() -> __ulock_wait. This
        // guards the cached-state fix.
        await showAudiobook(tester);
        await tester.tap(find.text('Audio Play'));
        await waitForPlaying(tester);
        // Advance to track 2 so the next go(to:) crosses a real track boundary.
        await tester.tap(find.text('Skip Next'));
        await waitForPlaying(tester, timeout: const Duration(seconds: 10));
        // Cross-boundary go-to while playing — the path that deadlocked pre-fix.
        await tester.tap(find.text('Ch.1'));
        await waitForPlaying(tester);
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
      await showAudiobook(tester, button: 'Open AudioBook NoTitle');
      await tester.tap(find.text('Audio Play'));
      await waitForPlaying(tester);

      // Skip into the untitled second chapter.
      await tester.tap(find.text('Skip Next'));
      await waitForPlaying(tester, timeout: const Duration(seconds: 10));
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('next chapter advances the track', (tester) async {
      // Audio Next Chapter drives Flureadium.next(), which must move to the
      // next reading-order track — not seek inside the current one. The bug
      // this guards made next() a 30s seek, so the track never changed.
      await showAudiobook(tester);
      await tester.tap(find.text('Audio Play'));
      await waitForPlaying(tester);

      final before = currentTrack(tester);

      await tester.tap(find.text('Audio Next Chapter'));
      await pumpUntil(
        tester,
        () => currentTrack(tester) != before,
        timeout: const Duration(seconds: 10),
      );

      // The displayed track changed and playback is still active.
      expect(currentTrack(tester), isNot(before));
      expect(find.text('Audio Pause'), findsOneWidget);
    });

    testWidgets('previous chapter at first track is a no-op', (tester) async {
      // From track 1, Audio Prev Chapter must be bounded: next()/previous()
      // move exactly one track and clamp at the ends, so this leaves the
      // current track unchanged and does not crash.
      await showAudiobook(tester);
      await tester.tap(find.text('Audio Play'));
      await waitForPlaying(tester);

      final before = currentTrack(tester);

      await tester.tap(find.text('Audio Prev Chapter'));
      // Fixed settle wait: there is no state change to poll for — assert the
      // track stayed put after giving the no-op time to (not) act.
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
      await showAudiobook(tester);
      await tester.tap(find.text('Audio Play'));
      await waitForPlaying(tester);

      // Jump straight to the last reading-order track instead of skipping
      // track by track. goByLink is the same navigation the app performs;
      // loading the manifest separately just gets the reading order so we can
      // pick the last link. The audiobook stays opened through showAudiobook
      // above — on Android the reader widget must host an EPUB, so an audiobook
      // cannot be a direct initialAsset boot.
      final path = await _extractAsset('assets/pubs/38533.audiobook');
      final pub = await Flureadium().loadPublication(path);
      await Flureadium().goByLink(pub.readingOrder.last, pub);

      // Wait for the last track's duration to be reported.
      await pumpUntil(
        tester,
        () => timebasedPosition(tester).durMs > 0,
        timeout: const Duration(seconds: 10),
      );
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
      await pumpUntil(
        tester,
        () => endedSeen(tester),
        timeout: const Duration(seconds: 45),
      );

      expect(endedSeen(tester), isTrue);
    });

    testWidgets('unreachable streamed audio surfaces an error event', (
      tester,
    ) async {
      // A dead host ('Open AudioBook BadUrl') fails at *load time*, before
      // playback starts. Android forwards this to onErrorEvent via
      // ReadiumReader.onTimebasedPlaybackFailure. iOS now observes it too: the
      // onCreatePublication container wrapper (Readium.swift +
      // LoadFailureObservingResource/AudioResourceLoadFailureReporter) catches
      // the failed resource read during opening and routes it onto the error
      // channel, so a load that never starts playing is no longer silent.
      await showAudiobook(tester, button: 'Open AudioBook BadUrl');
      await tester.tap(find.text('Audio Play'));

      final surfaced = await pumpUntil(
        tester,
        () => lastAudioError(tester).isNotEmpty,
        timeout: const Duration(seconds: 20),
      );
      expect(
        surfaced,
        isTrue,
        reason: 'a failed streamed audio load must surface on onErrorEvent',
      );
    });

    testWidgets('partial stream failure surfaces an error event', (
      tester,
    ) async {
      // Regression for the streaming-error observability gap on Android:
      // 'Open AudioBook BadStream' serves a WAV whose Content-Length promises
      // 30s but drops the socket after ~1s. ExoPlayer raises a source error
      // mid-stream, which ReadiumReader.onTimebasedPlaybackFailure forwards to
      // onErrorEvent. Skipped on iOS: AVFoundation does not reliably post a
      // NotificationCenter entry for this synthetic truncation, so iOS audio
      // error delivery stays best-effort (see FlutterAudioNavigator and
      // platform-specific/ios.md). The Android forwarding itself is also
      // covered by the ReadiumReaderTimebasedErrorTest unit test.
      await showAudiobook(tester, button: 'Open AudioBook BadStream');
      await tester.tap(find.text('Audio Play'));

      final surfaced = await pumpUntil(
        tester,
        () => lastAudioError(tester).isNotEmpty,
        timeout: const Duration(seconds: 30),
      );
      expect(
        surfaced,
        isTrue,
        reason: 'a mid-stream audio failure must surface on onErrorEvent',
      );
    }, skip: Platform.isIOS);

    testWidgets(
      'seeking a streamed audiobook does not surface a spurious cancelled error',
      (tester) async {
        // A streamed audiobook served by a local range-seekable WAV server that
        // trickles the tail of each range, so a read-ahead request is in flight
        // during playback. Seeking supersedes it — Apple's documented
        // AVAssetResourceLoaderDelegate.resourceLoader(_:didCancel:) case — so
        // Readium's read task is cancelled and surfaces HTTPError.cancelled.
        // The iOS reporter must swallow that: no onErrorEvent, playback
        // continues. The server latches the client disconnect so this negative
        // assertion is non-vacuous — if no cancellation happened the latch
        // stays false and the test fails instead of passing trivially.
        await showAudiobook(tester, button: 'Open AudioBook Streamed');
        await tester.tap(find.text('Audio Play'));
        await waitForPlaying(tester, timeout: const Duration(seconds: 20));

        // Seek forward repeatedly to supersede in-flight read-ahead requests.
        for (var i = 0; i < 6; i++) {
          await tester.tap(find.text('+30s'));
          await tester.pump(const Duration(seconds: 1));
        }

        // A cancellation must actually have occurred (non-vacuity guard).
        final cancelled = await pumpUntil(
          tester,
          () => cancelledStreamDisconnectSeen(tester),
          timeout: const Duration(seconds: 20),
        );
        expect(
          cancelled,
          isTrue,
          reason:
              'a seek must supersede an in-flight range request so the '
              'cancelled-read path is actually exercised',
        );

        // Give any spurious error event time to propagate before asserting it
        // did not arrive.
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        // ...and the benign cancellation must not have surfaced as an error.
        expect(
          lastAudioError(tester),
          isEmpty,
          reason:
              'a cancelled read is benign churn and must not surface on '
              'onErrorEvent',
        );
        expect(
          find.text('Audio Pause'),
          findsOneWidget,
          reason: 'playback must continue through the cancellation',
        );
      },
      skip: !Platform.isIOS,
    );
  });
}

// Extracts a bundled asset to a temp file so loadPublication can read the
// manifest to pick the last reading-order track. Mirrors the app's own
// _extractAsset and cbz_test's copy.
Future<String> _extractAsset(String assetPath) async {
  final bytes = await rootBundle.load(assetPath);
  final filename = assetPath.split('/').last;
  final tmp = File(
    '${Directory.systemTemp.path}/${DateTime.now().millisecondsSinceEpoch}_$filename',
  );
  await tmp.writeAsBytes(bytes.buffer.asUint8List());
  return tmp.path;
}
