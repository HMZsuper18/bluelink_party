import 'package:equatable/equatable.dart';

import 'game_mode.dart';
import 'player_slot.dart';

class MatchConfig extends Equatable {
  const MatchConfig({
    this.viewportWidth = defaultViewportWidth,
    this.viewportHeight = defaultViewportHeight,
    this.countdownSeconds = defaultCountdownSeconds,
    this.matchDuration = const Duration(seconds: 90),
    this.mode = GameMode.battleSync,
    this.seed = 0,
    this.players = const <PlayerSlot>[],
  });

  static const double defaultViewportWidth = 1920;
  static const double defaultViewportHeight = 1080;
  static const int defaultCountdownSeconds = 3;

  final double viewportWidth;
  final double viewportHeight;
  final int countdownSeconds;
  final Duration matchDuration;
  final GameMode mode;
  final int seed;

  /// Filled lobby slots that join this match; every device derives the exact
  /// same player roster from this list.
  final List<PlayerSlot> players;

  double get viewportAspectRatio => viewportWidth / viewportHeight;

  Map<String, dynamic> toJson() => {
        'viewportWidth': viewportWidth,
        'viewportHeight': viewportHeight,
        'countdownSeconds': countdownSeconds,
        'matchDurationMs': matchDuration.inMilliseconds,
        'mode': mode.key,
        'seed': seed,
        'players': [for (final p in players) p.toJson()],
      };

  factory MatchConfig.fromJson(Map<String, dynamic> json) {
    return MatchConfig(
      viewportWidth:
          (json['viewportWidth'] as num?)?.toDouble() ?? defaultViewportWidth,
      viewportHeight:
          (json['viewportHeight'] as num?)?.toDouble() ?? defaultViewportHeight,
      countdownSeconds:
          (json['countdownSeconds'] as num?)?.toInt() ?? defaultCountdownSeconds,
      matchDuration: Duration(
        milliseconds: (json['matchDurationMs'] as num?)?.toInt() ?? 90000,
      ),
      mode: GameMode.fromKey(json['mode'] as String? ?? ''),
      seed: (json['seed'] as num?)?.toInt() ?? 0,
      players: [
        for (final raw in (json['players'] as List<dynamic>? ?? const []))
          PlayerSlot.fromJson(raw as Map<String, dynamic>),
      ],
    );
  }

  @override
  List<Object?> get props => [
        viewportWidth,
        viewportHeight,
        countdownSeconds,
        matchDuration,
        mode,
        seed,
        players,
      ];
}
