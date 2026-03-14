import 'dart:convert';

import 'package:collection/collection.dart';

import 'index.dart';

class ReadiumTimebasedState {
  ReadiumTimebasedState({
    required this.state,
    this.currentOffset,
    this.currentBuffered,
    this.currentDuration,
    this.currentLocator,
    this.ttsErrorType,
  });

  factory ReadiumTimebasedState.fromJsonMap(final Map<String, dynamic> map) =>
      ReadiumTimebasedState(
        state:
            TimebasedState.values.firstWhereOrNull(
              (v) =>
                  v.name.toLowerCase() == map['state'].toString().toLowerCase(),
            ) ??
            TimebasedState.failure,
        currentOffset: map['currentOffset'] is int
            ? Duration(milliseconds: map['currentOffset'])
            : null,
        currentBuffered: map['currentBuffered'] is int
            ? Duration(milliseconds: map['currentBuffered'])
            : null,
        currentDuration: map['currentDuration'] is int
            ? Duration(milliseconds: map['currentDuration'])
            : null,
        currentLocator: map['currentLocator'] is String
            ? Locator.fromJson(
                json.decode(map['currentLocator']) as Map<String, dynamic>,
              )
            : (map['currentLocator'] is Map<String, dynamic>
                  ? Locator.fromJson(
                      map['currentLocator'] as Map<String, dynamic>,
                    )
                  : null),
        ttsErrorType: map['ttsErrorType'] is String
            ? TtsErrorType.values.firstWhereOrNull(
                (e) => e.name == map['ttsErrorType'],
              )
            : null,
      );

  @override
  String toString() =>
      'ReadiumTimebasedState($state,offset=$currentOffset,duration=$currentDuration,buffered=$currentBuffered,'
      'href=${currentLocator?.href},'
      'progression=${currentLocator?.locations?.progression},'
      'totalProgression=${currentLocator?.locations?.totalProgression})';

  /// Current time-based player state.
  TimebasedState state;

  /// Playback offset in the current audio file.
  Duration? currentOffset;

  /// Duration buffered of the current file.
  Duration? currentBuffered;

  /// Total duration of the current file.
  Duration? currentDuration;

  /// Current Locator in the publication being played.
  Locator? currentLocator;

  /// Error type when TTS fails (only populated when state == failure).
  TtsErrorType? ttsErrorType;
}
