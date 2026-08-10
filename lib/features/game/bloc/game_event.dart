import 'package:equatable/equatable.dart';

import '../../../data/models/match_event.dart';
import '../domain/match_outcome.dart';
import '../sync/game_snapshot.dart';

export '../domain/match_outcome.dart';

sealed class GameEvent extends Equatable {
  const GameEvent();

  @override
  List<Object?> get props => const [];
}

class MatchStarted extends GameEvent {
  const MatchStarted(this.event, {this.localPlayerId = ''});

  final MatchEvent event;
  final String localPlayerId;

  @override
  List<Object?> get props => [event, localPlayerId];
}

class CountdownTick extends GameEvent {
  const CountdownTick();
}

class CountdownFinished extends GameEvent {
  const CountdownFinished();
}

class PlayerInputChanged extends GameEvent {
  const PlayerInputChanged({
    this.moveX = 0,
    this.moveY = 0,
    this.firing = false,
  });

  final double moveX;
  final double moveY;
  final bool firing;

  @override
  List<Object?> get props => [moveX, moveY, firing];
}

class MatchTick extends GameEvent {
  const MatchTick();
}

class MatchOver extends GameEvent {
  const MatchOver(this.outcome);

  final MatchOutcome outcome;

  @override
  List<Object?> get props => [outcome];
}

class PauseMatch extends GameEvent {
  const PauseMatch();
}

class PlayerReadyChanged extends GameEvent {
  const PlayerReadyChanged(this.playerId, {required this.ready});

  final String playerId;
  final bool ready;

  @override
  List<Object?> get props => [playerId, ready];
}

class ResumeMatch extends GameEvent {
  const ResumeMatch();
}

class RestartMatch extends GameEvent {
  const RestartMatch();
}

class ReturnToLobby extends GameEvent {
  const ReturnToLobby();
}

/// Host-only: applies a move/fire intent received from a remote client.
class RemoteInputApplied extends GameEvent {
  const RemoteInputApplied({
    required this.playerId,
    required this.moveX,
    required this.moveY,
    required this.firing,
  });

  final String playerId;
  final double moveX;
  final double moveY;
  final bool firing;

  @override
  List<Object?> get props => [playerId, moveX, moveY, firing];
}

/// Client-only: replace local state with the host's authoritative snapshot.
class RemoteStateApplied extends GameEvent {
  const RemoteStateApplied(this.snapshot);

  final GameSnapshot snapshot;

  @override
  List<Object?> get props => [snapshot];
}
