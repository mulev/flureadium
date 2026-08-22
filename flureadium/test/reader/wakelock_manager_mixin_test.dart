import 'package:fake_async/fake_async.dart';
import 'package:flureadium/src/reader/wakelock_manager_mixin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// Records every toggle instead of talking to a device.
class _RecordingWakelockPlatform extends WakelockPlusPlatformInterface {
  final List<bool> toggles = [];

  @override
  Future<void> toggle({required bool enable}) async => toggles.add(enable);
}

class _TestWakelockManager with WakelockManagerMixin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = wakelockPlusPlatformInstance;
  late _RecordingWakelockPlatform platform;
  late _TestWakelockManager manager;

  setUp(() {
    platform = _RecordingWakelockPlatform();
    wakelockPlusPlatformInstance = platform;
    manager = _TestWakelockManager();
  });

  tearDown(() => wakelockPlusPlatformInstance = originalPlatform);

  group('WakelockManagerMixin', () {
    test('enableWakelock turns the wakelock on', () async {
      await manager.enableWakelock();

      expect(platform.toggles, [true]);

      manager.disableWakelock();
    });

    test('the wakelock turns off after 30 minutes of inactivity', () {
      fakeAsync((async) {
        manager.enableWakelock();

        async.elapse(const Duration(minutes: 29));
        expect(platform.toggles, [true], reason: 'still within the window');

        async.elapse(const Duration(minutes: 1));
        expect(platform.toggles, [true, false]);
      });
    });

    test('a second enableWakelock restarts the 30-minute window', () {
      fakeAsync((async) {
        manager.enableWakelock();
        async.elapse(const Duration(minutes: 20));
        manager.enableWakelock();

        async.elapse(const Duration(minutes: 20));
        expect(
          platform.toggles,
          [true, true],
          reason: '40 minutes total, but only 20 since the last interaction',
        );

        async.elapse(const Duration(minutes: 10));
        expect(platform.toggles, [true, true, false]);
      });
    });

    test('disableWakelock cancels the pending timer', () {
      fakeAsync((async) {
        manager.enableWakelock();
        manager.disableWakelock();

        async.elapse(const Duration(minutes: 31));
        expect(
          platform.toggles,
          [true, false],
          reason: 'the cancelled timer must not toggle a second time',
        );
      });
    });
  });
}
