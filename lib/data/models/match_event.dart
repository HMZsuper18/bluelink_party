import 'package:equatable/equatable.dart';

import 'game_phase.dart';
import 'match_config.dart';

class MatchEvent extends Equatable {
  const MatchEvent({required this.phase, required this.config});

  final GamePhase phase;
  final MatchConfig config;

  Map<String, dynamic> toJson() => {
        'phase': phase.key,
        'config': config.toJson(),
      };

  factory MatchEvent.fromJson(Map<String, dynamic> json) {
    return MatchEvent(
      phase: GamePhase.fromKey(json['phase'] as String? ?? ''),
      config: MatchConfig.fromJson(
        json['config'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }

  @override
  List<Object?> get props => [phase, config];
}
