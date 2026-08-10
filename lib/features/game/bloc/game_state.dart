import 'dart:math';

import 'package:equatable/equatable.dart';

import '../../../data/models/game_phase.dart';
import '../../../data/models/match_config.dart';
import '../../../data/models/team.dart';
import '../domain/match_player.dart';
import '../domain/match_projectile.dart';
import 'game_event.dart';

class GameState extends Equatable {
  const GameState({
    this.phase = GamePhase.lobby,
    this.config,
    this.remainingSeconds = 0,
    this.outcome,
    this.elapsedMs = 0,
    this.matchDurationMs = 90000,
    this.players = const <MatchPlayer>[],
    this.projectiles = const <MatchProjectile>[],
    this.redScore = 0,
    this.blueScore = 0,
    this.isPaused = false,
    this.readyPlayerIds = const <String>{},
  });

  final GamePhase phase;
  final MatchConfig? config;
  final int remainingSeconds;
  final MatchOutcome? outcome;
  final int elapsedMs;
  final int matchDurationMs;
  final List<MatchPlayer> players;
  final List<MatchProjectile> projectiles;
  final int redScore;
  final int blueScore;
  final bool isPaused;

  /// Roster players that have readied up to continue after a pause.
  final Set<String> readyPlayerIds;

  int get timeRemainingMs => max(0, matchDurationMs - elapsedMs);

  bool get allPlayersReady {
    if (players.isEmpty) return false;
    for (final player in players) {
      if (!readyPlayerIds.contains(player.id)) return false;
    }
    return true;
  }

  int totalTeamHp(Team team) =>
      players.where((p) => p.team == team).fold(0, (sum, p) => sum + p.hp);

  int totalTeamMaxHp(Team team) =>
      players.where((p) => p.team == team).fold(0, (sum, p) => sum + p.maxHp);

  GameState copyWith({
    GamePhase? phase,
    MatchConfig? config,
    int? remainingSeconds,
    MatchOutcome? outcome,
    int? elapsedMs,
    int? matchDurationMs,
    List<MatchPlayer>? players,
    List<MatchProjectile>? projectiles,
    int? redScore,
    int? blueScore,
    bool? isPaused,
    Set<String>? readyPlayerIds,
    bool clearConfig = false,
    bool clearOutcome = false,
  }) {
    return GameState(
      phase: phase ?? this.phase,
      config: clearConfig ? null : (config ?? this.config),
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      outcome: clearOutcome ? null : (outcome ?? this.outcome),
      elapsedMs: elapsedMs ?? this.elapsedMs,
      matchDurationMs: matchDurationMs ?? this.matchDurationMs,
      players: players ?? this.players,
      projectiles: projectiles ?? this.projectiles,
      redScore: redScore ?? this.redScore,
      blueScore: blueScore ?? this.blueScore,
      isPaused: isPaused ?? this.isPaused,
      readyPlayerIds: readyPlayerIds ?? this.readyPlayerIds,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        config,
        remainingSeconds,
        outcome,
        elapsedMs,
        matchDurationMs,
        players,
        projectiles,
        redScore,
        blueScore,
        isPaused,
        readyPlayerIds,
      ];
}
