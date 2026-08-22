import 'dart:io';

import 'package:flureadium/flureadium.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/extract_asset.dart';
import 'helpers/pump_until.dart';
import 'helpers/tap_latch.dart';

/// Proves a content tap inside an Android edge strip reaches `onTap` when only
/// swipe navigation is on.
///
/// `EdgeTapInterceptView` used to claim a 44 dp strip whenever it held *either*
/// an edge-tap or a swipe callback, and `enableSwipeNavigation` defaults to
/// enabled. So `enableEdgeTapNavigation: false` left the overlay claiming both
/// strips and then dropping the touch on a null edge-tap callback: no page
/// turn, and no `onTap` either. The claim predicate reads the edge-tap
/// callbacks alone now, and this is the case that measures it on a device.
///
/// Reflowable EPUB on Android only, for the reasons `tap_test.dart` records:
/// `WidgetTester` cannot synthesize a `UITouch` on iOS, and an Android
/// fixed-layout page receives the `MotionEvent` and drops it above the view.
///
/// It pumps its own widget tree rather than the example app: the app never
/// calls `setNavigationConfig`, and a test-owned harness is cheaper than
/// growing `main.dart`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _edgeStripTapTests();
}

/// Plain reflowable text. `tap_targets.epub`'s first page is a single anchor
/// filling the viewport, so a tap anywhere on it — edge strip included — hits
/// a link, which Readium follows and deliberately does not report.
const _epub = 'assets/pubs/moby_dick.epub';

/// Inset from the reader's edge, in logical pixels. Flutter logical pixels are
/// Android dp, so 22 is inside the 44 dp strip.
const _stripInset = 22.0;

int _tapCount = 0;
Offset? _lastTap;
bool _ready = false;
int _locatorCount = 0;
Locator? _lastLocator;

/// Pumps until [condition] holds, failing with [reason] on timeout.
///
/// [pumpUntil] reports a timeout in its return value, so every wait has to
/// assert that value or a never-satisfied condition passes silently.
Future<void> _expectEventually(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final satisfied = await pumpUntil(tester, condition, timeout: timeout);
  expect(satisfied, isTrue, reason: reason);
}

/// A resource plus how far into it the reader sits — the page, as far as these
/// cases need to tell one from another.
typedef _Page = ({String? href, double? progression});

/// How much progression may drift before it counts as movement. Matches the
/// tolerance `epub_test.dart` uses for "the position did not move".
const _progressionEpsilon = 0.01;

/// The page the reader last reported.
///
/// Deliberately not a count of locators. One Android open reports the same page
/// twice: Readium seeds `currentLocator` from `Manifest.locatorFromLink`, which
/// carries no `position`, then rebuilds it about 180 ms later once positions
/// load. Both name page 1 of the same resource, so a count rises while the
/// reader stands still — href and progression do not.
_Page _page() => (
  href: _lastLocator?.href,
  progression: _lastLocator?.locations?.progression,
);

/// Whether the reader has left [from].
///
/// One predicate serves the no-turn assertion and the turn detector below: two
/// that disagreed on what counts as movement would leave a gap for a real
/// regression to sit in.
bool _movedFrom(_Page from) {
  final now = _page();
  if (now.href != from.href) return true;

  final before = from.progression;
  final after = now.progression;
  if (before == null || after == null) return before != after;

  return (after - before).abs() >= _progressionEpsilon;
}

void _edgeStripTapTests() {
  group('edge strip tap', () {
    Finder reader() => find.byType(ReadiumReaderWidget);

    setUp(() {
      _tapCount = 0;
      _lastTap = null;
      _ready = false;
      _locatorCount = 0;
      _lastLocator = null;
    });

    tearDown(() async {
      await Flureadium().closePublication();
      // The config is process-global and now actually reaches readers, so a
      // leftover would configure every reader built after this file.
      await Flureadium().setNavigationConfig(ReaderNavigationConfig());
    });

    /// Turns edge taps off and leaves swipe on — the configuration that used
    /// to swallow the touch — then opens the fixture and waits for the reader
    /// to be listening.
    ///
    /// The config goes first, the way a real host sends it: it is stored on
    /// the platform and replayed when the reader registers.
    Future<void> showFixture(WidgetTester tester) async {
      await Flureadium().setNavigationConfig(
        ReaderNavigationConfig(
          enableEdgeTapNavigation: false,
          enableSwipeNavigation: true,
        ),
      );

      final path = await extractAsset(_epub);
      final publication = await Flureadium().openPublication(path);
      await tester.pumpWidget(_EdgeStripHarness(publication: publication));

      await _expectEventually(
        tester,
        () => _ready,
        reason: 'the reader never reported ready',
        timeout: const Duration(seconds: 30),
      );
      // `ready` is the plugin's own status and does not prove the WebView's
      // JavaScript side is listening. A delivered locator does, because that
      // is where locators come from.
      await _expectEventually(
        tester,
        () => _locatorCount > 0,
        reason: 'no locator arrived, so the JS layer is not alive',
        timeout: const Duration(seconds: 30),
      );
    }

    Future<void> expectTapAt(WidgetTester tester, Offset position) async {
      final before = tapEvents(tester);
      await tester.tapAt(position);
      await _expectEventually(
        tester,
        () => tapEvents(tester) > before,
        reason: 'no tap arrived from native at $position',
      );
    }

    /// `all_tests.dart` runs on the iOS simulator too, where a synthesized tap
    /// cannot reach Readium at all. The skip sits on each test because
    /// `flutter_test`'s `group` drops it.
    void edgeTest(String description, WidgetTesterCallback body) =>
        testWidgets(description, body, skip: !Platform.isAndroid);

    edgeTest('a centre tap reports', (tester) async {
      await showFixture(tester);

      // The control. Without it a green strip case cannot be told apart from a
      // harness that never delivers a tap at all.
      await expectTapAt(tester, tester.getCenter(reader()));
      expect(
        lastTap(tester),
        isNotNull,
        reason: 'tap-events rose without a position',
      );
    });

    edgeTest('the left and right strips report and turn no page', (
      tester,
    ) async {
      await showFixture(tester);

      final rect = tester.getRect(reader());
      // With edge taps off the strip has to do both: report the tap, and not
      // page. A regression that reported the tap while still turning the page
      // would pass on the report alone, so the page is checked too — by
      // identity, never by locator count, for the reason `_page` records.
      //
      // The other direction — a claimed strip that does page — is not testable
      // from here: `GestureDetector.onSingleTapConfirmed` needs the double-tap
      // timeout to expire on a real touch sequence, and a `WidgetTester` tap
      // never gets that far. The overlay logs `claimed=true` and nothing
      // follows. `EdgeTapInterceptViewDispatchTest` owns that case on the JVM,
      // where `ShadowLooper` can run the delayed confirm.
      final before = _page();
      await expectTapAt(
        tester,
        Offset(rect.left + _stripInset, rect.center.dy),
      );
      await expectTapAt(
        tester,
        Offset(rect.right - _stripInset, rect.center.dy),
      );
      expect(
        _movedFrom(before),
        isFalse,
        reason:
            'a strip tap turned a page with edge-tap navigation off: '
            '$before -> ${_page()}',
      );
    });
  });
}

/// The reader plus the two latches `helpers/tap_latch.dart` parses.
///
/// The latches sit top-centre: a `Stack`'s later child wins the hit test, so a
/// top-left latch would cover the very strip these cases aim at.
class _EdgeStripHarness extends StatefulWidget {
  const _EdgeStripHarness({required this.publication});

  final Publication publication;

  @override
  State<_EdgeStripHarness> createState() => _EdgeStripHarnessState();
}

class _EdgeStripHarnessState extends State<_EdgeStripHarness> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(
            child: ReadiumReaderWidget(
              publication: widget.publication,
              onReady: () => setState(() => _ready = true),
              onLocatorChanged: (locator) => setState(() {
                _locatorCount++;
                _lastLocator = locator;
              }),
              onTap: (position) => setState(() {
                _tapCount++;
                _lastTap = position;
              }),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('tap-events: $_tapCount', key: const Key('tap-events')),
                Text(
                  _lastTap == null ? '' : '${_lastTap!.dx},${_lastTap!.dy}',
                  key: const Key('last-tap'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
