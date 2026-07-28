import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

CarContentStrings _strings() => CarContentStrings(
  emptyRootTitle: 'Nothing to play yet',
  emptyRootSubtitle:
      'Audiobooks and read-aloud EPUBs you add will appear here.',
  voiceUnavailable: 'This voice is not installed.',
  offline: 'This book needs a connection.',
);

void main() {
  group('CarContentStrings', () {
    test('fromMap(toMap()) round-trips every field', () {
      final strings = _strings();

      final restored = CarContentStrings.fromMap(strings.toMap());

      expect(restored.emptyRootTitle, strings.emptyRootTitle);
      expect(restored.emptyRootSubtitle, strings.emptyRootSubtitle);
      expect(restored.voiceUnavailable, strings.voiceUnavailable);
      expect(restored.offline, strings.offline);
    });

    test('a blank field is rejected', () {
      expect(
        () => CarContentStrings(
          emptyRootTitle: '',
          emptyRootSubtitle: 'x',
          voiceUnavailable: 'y',
          offline: 'z',
        ),
        throwsArgumentError,
      );
    });

    test('a missing field on fromMap is rejected', () {
      expect(
        () => CarContentStrings.fromMap(<String, Object?>{
          'emptyRootTitle': 'a',
          'emptyRootSubtitle': 'b',
          'voiceUnavailable': 'c',
        }),
        throwsArgumentError,
      );
    });
  });
}
