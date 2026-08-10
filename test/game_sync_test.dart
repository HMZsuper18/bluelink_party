import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bluelink_party/data/models/game_phase.dart';
import 'package:bluelink_party/data/models/match_config.dart';
import 'package:bluelink_party/data/models/match_event.dart';
import 'package:bluelink_party/data/models/player_slot.dart';
import 'package:bluelink_party/data/models/team.dart';
import 'package:bluelink_party/features/game/bloc/game_bloc.dart';
import 'package:bluelink_party/features/game/bloc/game_event.dart';
import 'package:bluelink_party/features/game/domain/match_player.dart';
import 'package:bluelink_party/features/game/domain/match_projectile.dart';
import 'package:bluelink_party/features/game/sync/game_snapshot.dart';
import 'package:bluelink_party/features/game/sync/game_sync_adapter.dart';

MatchEvent seeded(List<PlayerSlot> players) {
  return MatchEvent(
    phase: GamePhase.countdown,
    config: MatchConfig(players: players),
  );
}

class FakeSyncAdapter implements GameSyncAdapter {
  FakeSyncAdapter({required this.isHost, required this.localPlayerId});

  @override
  final bool isHost;

  @override
  final String localPlayerId;

  final StreamController<GameSyncEvent> _ctrl =
      StreamController<GameSyncEvent>.broadcast();

  @override
  Stream<GameSyncEvent> get events => _ctrl.stream;

  final List<GameSnapshot> broadcasts = [];
  final List<({double moveX, double moveY, bool firing})> sentInputs = [];
  final List<({String playerId, bool ready})> sentReadies = [];
  final List<GameCommand> sentCommands = [];

  @override
  void broadcastSnapshot(GameSnapshot snapshot) => broadcasts.add(snapshot);

  @override
  void sendInput({required double moveX, required double moveY, required bool firing}) {
    sentInputs.add((moveX: moveX, moveY: moveY, firing: firing));
  }

  @override
  void sendReady({required String playerId, required bool ready}) {
    sentReadies.add((playerId: playerId, ready: ready));
  }

  @override
  void sendCommand(GameCommand command) => sentCommands.add(command);

  @override
  void dispose() {}

  void emitEvent(GameSyncEvent event) => _ctrl.add(event);
}

GameSnapshot snapshotWith({
  GamePhase phase = GamePhase.inGame,
  int elapsedMs = 0,
  List<MatchPlayer> players = const [],
  List<MatchProjectile> projectiles = const [],
  bool isPaused = false,
  List<String> readyPlayerIds = const [],
}) {
  return GameSnapshot(
    phase: phase,
    remainingSeconds: phase == GamePhase.inGame ? 0 : 3,
    elapsedMs: elapsedMs,
    matchDurationMs: 90000,
    redScore: 1,
    blueScore: 2,
    isPaused: isPaused,
    readyPlayerIds: readyPlayerIds,
    outcome: null,
    players: [for (final p in players) GamePlayerSnapshot.fromMatch(p)],
    projectiles: [
      for (final pr in projectiles) GameProjectileSnapshot.fromMatch(pr),
    ],
  );
}

MatchPlayer player({
  required String id,
  required Team team,
  double x = 100,
  double y = 200,
  bool local = false,
}) {
  return MatchPlayer(
    id: id,
    name: id,
    team: team,
    x: x,
    y: y,
    facingX: team == Team.red ? 1 : -1,
    facingY: 0,
    isLocal: local,
  );
}

void main() {
  group('GameSnapshot serialization', () {
    test('round-trips players, projectiles, and match fields', () {
      final snapshot = GameSnapshot(
        phase: GamePhase.matchResult,
        remainingSeconds: 0,
        elapsedMs: 54321,
        matchDurationMs: 90000,
        redScore: 3,
        blueScore: 1,
        isPaused: true,
        readyPlayerIds: const ['r1'],
        outcome: MatchOutcome.victory,
        players: [GamePlayerSnapshot.fromMatch(player(id: 'r1', team: Team.red))],
        projectiles: const [
          GameProjectileSnapshot(
            id: 'p0',
            ownerTeam: Team.red,
            x: 10,
            y: 20,
            vx: 900,
            vy: 0,
            life: 1.5,
            damage: 25,
          ),
        ],
      );

      final decoded = GameSnapshot.fromMap(snapshot.toMap());

      expect(decoded.phase, GamePhase.matchResult);
      expect(decoded.elapsedMs, 54321);
      expect(decoded.redScore, 3);
      expect(decoded.isPaused, isTrue);
      expect(decoded.readyPlayerIds, ['r1']);
      expect(decoded.outcome, MatchOutcome.victory);
      expect(decoded.players.single.id, 'r1');
      expect(decoded.projectiles.single.vx, 900);
    });
  });

  group('client replica', () {
    test('applies the host snapshot and marks the local player', () async {
      final sync = FakeSyncAdapter(isHost: false, localPlayerId: 'r1');
      final bloc = GameBloc(sync: sync);
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'r1', playerName: 'R1'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'b1', playerName: 'B1'),
        ]),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      sync.emitEvent(RemoteSnapshotEvent(snapshotWith(
        elapsedMs: 4000,
        players: [
          player(id: 'r1', team: Team.red, x: 11, y: 22),
          player(id: 'b1', team: Team.blue, x: 333, y: 444),
        ],
      )));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.phase, GamePhase.inGame);
      expect(bloc.state.elapsedMs, 4000);
      final r1 = bloc.state.players.firstWhere((p) => p.id == 'r1');
      final b1 = bloc.state.players.firstWhere((p) => p.id == 'b1');
      expect(r1.isLocal, isTrue);
      expect(b1.isLocal, isFalse);
      expect(r1.x, 11);
      expect(b1.x, 333);

      await bloc.close();
    });

    test('forwards input, ready, and pause requests to the host', () async {
      final sync = FakeSyncAdapter(isHost: false, localPlayerId: 'r1');
      final bloc = GameBloc(sync: sync);
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'r1', playerName: 'R1'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'b1', playerName: 'B1'),
        ]),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bloc.add(const PlayerInputChanged(moveX: 0.5, moveY: 0, firing: true));
      bloc.add(const PauseMatch());
      bloc.add(const PlayerReadyChanged('r1', ready: true));
      bloc.add(const RestartMatch());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(sync.sentInputs, hasLength(1));
      expect(sync.sentInputs.single.moveX, 0.5);
      expect(sync.sentCommands, [GameCommand.pause],
          reason: 'restart stays local-blocked until the host says everyone is ready');
      expect(sync.sentReadies, hasLength(1));
      expect(sync.sentReadies.single.playerId, 'r1');
      expect(bloc.state.isPaused, isTrue);

      sync.emitEvent(RemoteSnapshotEvent(snapshotWith(
        phase: GamePhase.inGame,
        isPaused: true,
        readyPlayerIds: const ['r1', 'b1'],
        players: [
          player(id: 'r1', team: Team.red, x: 40, y: 100, local: true),
          player(id: 'b1', team: Team.blue, x: 200, y: 100),
        ],
      )));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.allPlayersReady, isTrue);

      bloc.add(const ResumeMatch());
      bloc.add(const RestartMatch());
      bloc.add(const ReturnToLobby());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        sync.sentCommands,
        [
          GameCommand.pause,
          GameCommand.resume,
        ],
        reason: 'restart and quit are host-only; clients must not forward them',
      );
      expect(bloc.state.isPaused, isTrue,
          reason: 'client stays paused until the host acts');

      await bloc.close();
    });

    test('client cannot quit or restart from pause even when everyone is ready',
        () async {
      final sync = FakeSyncAdapter(isHost: false, localPlayerId: 'c1');
      final bloc = GameBloc(sync: sync);
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'h1', playerName: 'Host'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'c1', playerName: 'Guest'),
        ]),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      sync.emitEvent(RemoteSnapshotEvent(snapshotWith(
        phase: GamePhase.inGame,
        isPaused: true,
        readyPlayerIds: const ['h1', 'c1'],
        players: [
          player(id: 'h1', team: Team.red, x: 40, y: 100),
          player(id: 'c1', team: Team.blue, x: 200, y: 100, local: true),
        ],
      )));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.allPlayersReady, isTrue);

      bloc.add(const RestartMatch());
      bloc.add(const ReturnToLobby());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(sync.sentCommands, isEmpty);
      expect(bloc.state.phase, GamePhase.inGame);
      expect(bloc.state.isPaused, isTrue);

      await bloc.close();
    });
  });

  group('host authority', () {
    test('moves remote players from their reported input and broadcasts', () async {
      final sync = FakeSyncAdapter(isHost: true, localPlayerId: 'h1');
      final bloc = GameBloc(sync: sync);
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'h1', playerName: 'Host'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'c1', playerName: 'Guest'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final before = bloc.state.players.firstWhere((p) => p.id == 'c1').x;
      sync.emitEvent(const RemoteInputEvent(
        playerId: 'c1',
        moveX: -1,
        moveY: 0,
        firing: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final after = bloc.state.players.firstWhere((p) => p.id == 'c1').x;
      expect(after, lessThan(before));
      expect(sync.broadcasts, isNotEmpty);

      await bloc.close();
    });

    test('pause command pauses the match for everyone and broadcasts', () async {
      final sync = FakeSyncAdapter(isHost: true, localPlayerId: 'h1');
      final bloc = GameBloc(sync: sync);
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'h1', playerName: 'Host'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'c1', playerName: 'Guest'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      sync.emitEvent(const RemoteCommandEvent(GameCommand.pause));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.isPaused, isTrue);
      expect(sync.broadcasts.last.isPaused, isTrue);

      await bloc.close();
    });

    test('stays paused once every roster player is ready until resume', () async {
      final sync = FakeSyncAdapter(isHost: true, localPlayerId: 'h1');
      final bloc = GameBloc(sync: sync);
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'h1', playerName: 'Host'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'c1', playerName: 'Guest'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      bloc.add(const PauseMatch());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.isPaused, isTrue);

      bloc.add(const PlayerReadyChanged('h1', ready: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.isPaused, isTrue);

      sync.emitEvent(const RemoteReadyEvent(playerId: 'c1', ready: true));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.isPaused, isTrue);
      expect(bloc.state.allPlayersReady, isTrue);
      expect(sync.broadcasts.last.isPaused, isTrue);
      expect(sync.broadcasts.last.readyPlayerIds, containsAll(['h1', 'c1']));

      bloc.add(const ResumeMatch());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.isPaused, isFalse);
      expect(sync.broadcasts.last.isPaused, isFalse);

      await bloc.close();
    });

    test('quit from pause is host-only after every player is ready', () async {
      final sync = FakeSyncAdapter(isHost: true, localPlayerId: 'h1');
      final bloc = GameBloc(sync: sync);
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'h1', playerName: 'Host'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'c1', playerName: 'Guest'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      bloc.add(const PauseMatch());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      bloc.add(const PlayerReadyChanged('h1', ready: true));
      sync.emitEvent(const RemoteReadyEvent(playerId: 'c1', ready: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // A remote quit request must be ignored — only the host UI may quit.
      sync.emitEvent(const RemoteCommandEvent(GameCommand.quit));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.phase, GamePhase.inGame);
      expect(bloc.state.isPaused, isTrue);

      bloc.add(const ReturnToLobby());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.phase, GamePhase.lobby);
      expect(sync.broadcasts.last.phase, GamePhase.lobby);

      await bloc.close();
    });

    test('keeps re-broadcasting the frozen state while paused so no device lags behind', () async {
      final sync = FakeSyncAdapter(isHost: true, localPlayerId: 'h1');
      final bloc = GameBloc(sync: sync);
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'h1', playerName: 'Host'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'c1', playerName: 'Guest'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final movingCount = sync.broadcasts.length;
      bloc.add(const PauseMatch());
      await Future<void>.delayed(const Duration(milliseconds: 700));

      final pausedBroadcasts =
          sync.broadcasts.skip(movingCount).where((s) => s.isPaused);
      expect(pausedBroadcasts, isNotEmpty);
      expect(bloc.state.isPaused, isTrue);
      final frames = pausedBroadcasts
          .map((s) => s.players.map((p) => p.x).toList())
          .toList();
      final firstFrame = frames.first;
      for (final frame in frames.skip(1)) {
        expect(frame, firstFrame,
            reason: 'every paused broadcast must carry identical frozen positions');
      }

      sync.emitEvent(const RemoteReadyEvent(playerId: 'c1', ready: true));
      bloc.add(const PlayerReadyChanged('h1', ready: true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.allPlayersReady, isTrue);
      expect(bloc.state.isPaused, isTrue);

      bloc.add(const ResumeMatch());
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(bloc.state.isPaused, isFalse);
      expect(sync.broadcasts.last.isPaused, isFalse);
      final resumes =
          sync.broadcasts.skip(movingCount).where((s) => !s.isPaused);
      expect(resumes.isNotEmpty, isTrue);

      await bloc.close();
    });

    test('host restart re-enters the countdown and clears the field', () async {
      final sync = FakeSyncAdapter(isHost: true, localPlayerId: 'h1');
      final bloc = GameBloc(sync: sync);
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'h1', playerName: 'Host'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'c1', playerName: 'Guest'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Remote restart requests are ignored; only the host UI may restart.
      sync.emitEvent(const RemoteCommandEvent(GameCommand.restart));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.phase, GamePhase.inGame);

      bloc.add(const RestartMatch());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(bloc.state.phase, GamePhase.countdown);
      expect(bloc.state.players, isEmpty);

      await bloc.close();
    });
  });
}
