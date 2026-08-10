import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_shift/data/models/game_phase.dart';
import 'package:screen_shift/data/models/match_config.dart';
import 'package:screen_shift/data/models/match_event.dart';
import 'package:screen_shift/data/models/player_slot.dart';
import 'package:screen_shift/data/models/team.dart';
import 'package:screen_shift/features/game/bloc/game_bloc.dart';
import 'package:screen_shift/features/game/bloc/game_event.dart';
import 'package:screen_shift/features/game/sync/game_snapshot.dart';
import 'package:screen_shift/features/game/sync/game_sync_adapter.dart';

/// Two [GameSyncAdapter]s wired directly together so a host [GameBloc] and a
/// client [GameBloc] exchange snapshots/inputs without real sockets.
class LinkedSync implements GameSyncAdapter {
  LinkedSync({required this.isHost, required this.localPlayerId});

  @override
  final bool isHost;

  @override
  final String localPlayerId;

  LinkedSync? peer;

  final StreamController<GameSyncEvent> _events =
      StreamController<GameSyncEvent>.broadcast();

  @override
  Stream<GameSyncEvent> get events => _events.stream;

  void _inject(GameSyncEvent event) => _events.add(event);

  @override
  void broadcastSnapshot(GameSnapshot snapshot) {
    peer?._inject(RemoteSnapshotEvent(snapshot));
  }

  @override
  void sendInput({required double moveX, required double moveY, required bool firing}) {
    peer?._inject(RemoteInputEvent(
      playerId: localPlayerId,
      moveX: moveX,
      moveY: moveY,
      firing: firing,
    ));
  }

  @override
  void sendReady({required String playerId, required bool ready}) {
    peer?._inject(RemoteReadyEvent(playerId: playerId, ready: ready));
  }

  @override
  void sendCommand(GameCommand command) {
    peer?._inject(RemoteCommandEvent(command));
  }

  @override
  void dispose() {
    _events.close();
  }
}

MatchEvent _match(List<PlayerSlot> players) => MatchEvent(
      phase: GamePhase.countdown,
      config: MatchConfig(players: players),
    );

void main() {
  test('a client sees BOTH players move: its own remote player and the host player', () async {
    final hostSync = LinkedSync(isHost: true, localPlayerId: 'h1');
    final clientSync = LinkedSync(isHost: false, localPlayerId: 'c1');
    hostSync.peer = clientSync;
    clientSync.peer = hostSync;

    final roster = const [
      PlayerSlot(team: Team.red, seat: 0, playerId: 'h1', playerName: 'Host'),
      PlayerSlot(team: Team.blue, seat: 0, playerId: 'c1', playerName: 'Guest'),
    ];

    final hostBloc = GameBloc(sync: hostSync);
    final clientBloc = GameBloc(sync: clientSync);

    hostBloc.add(MatchStarted(_match(roster), localPlayerId: 'h1'));
    clientBloc.add(MatchStarted(_match(roster), localPlayerId: 'c1'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    hostBloc.add(const CountdownFinished());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Host player (red) moves right; client player (blue) moves left.
    final clientR1Before = clientBloc.state.players.firstWhere((p) => p.id == 'h1').x;
    final clientC1Before = clientBloc.state.players.firstWhere((p) => p.id == 'c1').x;

    hostBloc.add(const PlayerInputChanged(moveX: 1));
    clientBloc.add(const PlayerInputChanged(moveX: -1));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final after = clientBloc.state;
    final h1Moved = after.players.firstWhere((p) => p.id == 'h1').x != clientR1Before;
    final c1Moved = after.players.firstWhere((p) => p.id == 'c1').x != clientC1Before;

    expect(h1Moved, isTrue,
        reason: 'client should see the host player move via snapshots (h1 was frozen)');
    expect(c1Moved, isTrue,
        reason: 'client should see its own remote player move (guest was frozen)');

    await hostBloc.close();
    await clientBloc.close();
    hostSync.dispose();
    clientSync.dispose();
  });
}