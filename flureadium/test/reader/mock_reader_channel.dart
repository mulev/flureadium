import 'package:flureadium/reader_channel.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

/// One `go` call recorded by [MockReaderChannel].
typedef GoCall = ({Locator locator, bool animated, bool isAudioBookWithText});

/// A [ReadiumReaderChannel] that records every navigation request and answers
/// visibility from a per-test function.
class MockReaderChannel extends ReadiumReaderChannel {
  MockReaderChannel() : super('test-channel', onPageChanged: (_) {});

  final goCallLog = <GoCall>[];

  /// Every locator passed to [isLocatorVisible], in call order.
  final visibilityProbeLog = <Locator>[];

  /// Answers [isLocatorVisible]. Null means "nothing is on screen", which is
  /// what a reader showing some other page reports.
  bool Function(Locator locator)? visible;

  /// Runs inside `go`, standing in for anything the host does while the
  /// native navigation round-trip is still in flight.
  void Function()? duringGo;

  @override
  Future<void> go(
    Locator locator, {
    bool animated = false,
    required bool isAudioBookWithText,
  }) async {
    goCallLog.add((
      locator: locator,
      animated: animated,
      isAudioBookWithText: isAudioBookWithText,
    ));
    duringGo?.call();
  }

  @override
  Future<bool> isLocatorVisible(Locator locator) async {
    visibilityProbeLog.add(locator);
    try {
      return visible?.call(locator) ?? false;
    } on Object catch (_) {
      // The real channel swallows a failed probe and answers `true`
      // (`reader_channel.dart`: `.onError((error, _) => true)`), so a throwing
      // answer must exercise that same path rather than a Dart error.
      return true;
    }
  }
}
