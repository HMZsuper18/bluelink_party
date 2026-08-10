import 'package:flutter_test/flutter_test.dart';
import 'package:screen_shift/data/models/game_mode.dart';
import 'package:screen_shift/data/models/lobby_room.dart';
import 'package:screen_shift/data/models/player_slot.dart';
import 'package:screen_shift/data/models/team.dart';
import 'package:screen_shift/features/battle_sync/domain/battle_arena.dart';
import 'package:screen_shift/features/battle_sync/domain/game_snapshots.dart';
import 'package:screen_shift/features/battle_sync/domain/player_entity.dart';
import 'package:screen_shift/features/battle_sync/game/battle_sync_controller.dart';

class _RecordingAdapter implements BattleSyncAdapter {
  final inputs = <PlayerInput>[];
  final playerBroadcasts = <List<PlayerSnapshot>>[];
  final projectileBroadcasts = <List<ProjectileSnapshot>>[];

  @override
  void sendPlayerInput(PlayerInput input) => inputs.add(input);

  @override
  void broadcastPlayers(List<PlayerSnapshot> snapshots) =>
      playerBroadcasts.add(snapshots);

  @override
  void broadcastProjectiles(List<ProjectileSnapshot> snapshots) =>
      projectileBroadcasts.add(snapshots);
}

LobbyRoom _roomWithRedBlue() {
  return LobbyRoom(
    hostIp: '192.168.1.10',
    lobbyName: 'Battle',
    selectedMode: GameMode.battleSync,
    teams: {
      Team.red: [
        const PlayerSlot(
          team: Team.red,
          seat: 0,
          playerId: 'red0',
          playerName: 'Ruby',
        ),
        const PlayerSlot(team: Team.red, seat: 1),
      ],
      Team.blue: [
        const PlayerSlot(
          team: Team.blue,
          seat: 0,
          playerId: 'blue0',
          playerName: 'Azure',
        ),
        const PlayerSlot(team: Team.blue, seat: 1),
      ],
    },
  );
}

void main() {
  final arena = const BattleArena();

  group('spawn placement', () {
    test('red spawns left of midline, blue spawns right', () {
      final controller = BattleSyncController.fromRoom(
        room: _roomWithRedBlue(),
        localPlayerId: 'red0',
      );
      final red = controller.players['red0']!;
      final blue = controller.players['blue0']!;
      expect(red.team, Team.red);
      expect(red.x, lessThan(arena.midX));
      expect(red.facingX, greaterThan(0));
      expect(blue.x, greaterThan(arena.midX));
      expect(blue.facingX, lessThan(0));
      expect(blue.team, Team.blue);
    });
  });

  group('movement', () {
    test('player moves toward input direction', () {
      final controller = _makeController([
        _make(id: 'red0', team: Team.red, x: 200, y: 200, facingX: 1, facingY: 0),
      ], localId: 'red0');
      final before = controller.players['red0']!.x;
      controller.setLocalInput(moveX: 1);
      controller.step(0.016);
      expect(controller.players['red0']!.x, greaterThan(before));
      expect(controller.players['red0']!.facingX, 1);
    });

    test('player is clamped inside the walls', () {
      final controller = _makeController([
        _make(id: 'red0', team: Team.red, x: 1, y: 200),
      ], localId: 'red0');
      controller.setLocalInput(moveX: -1);
      for (var i = 0; i < 20; i++) {
        controller.step(0.1);
      }
      final player = controller.players['red0']!;
      expect(player.x, greaterThanOrEqualTo(arena.wallThickness + player.radius));
    });
  });

  group('combat', () {
    test('projectile damages an opposing team player', () {
      final adapter = _RecordingAdapter();
      final controller = _makeController(
        [
          _make(id: 'red0', team: Team.red, x: 150, y: 150, facingX: 1, facingY: 0, hp: 100),
          _make(id: 'blue0', team: Team.blue, x: 260, y: 150, hp: 100),
        ],
        localId: 'red0',
        adapter: adapter,
      );
      controller.setLocalInput(firing: true);
      _runFrames(controller, 30);
      final blue = controller.players['blue0']!;
      expect(blue.hp, lessThan(100));
    });

    test('defeat eliminates a player and declares the winner', () {
      var defeatedId = '';
      final controller = _makeController([
        _make(id: 'red0', team: Team.red, x: 150, y: 150, facingX: 1, facingY: 0, hp: 100),
        _make(id: 'blue0', team: Team.blue, x: 260, y: 150, hp: 10),
      ], localId: 'red0');
      controller.onPlayerDefeated = (p) => defeatedId = p.id;
      controller.setLocalInput(firing: true);
      _runFrames(controller, 40);

      expect(defeatedId, 'blue0');
      expect(controller.players['blue0']!.alive, isFalse);
      expect(controller.isMatchOver, isTrue);
      expect(controller.winnerTeam, Team.red);
    });

    test('projectile ignores friendly teammates', () {
      final controller = _makeController([
        _make(id: 'red0', team: Team.red, x: 150, y: 150, facingX: 1, facingY: 0, hp: 100),
        _make(id: 'red1', team: Team.red, x: 240, y: 150),
        _make(id: 'blue0', team: Team.blue, x: 400, y: 150, hp: 100),
      ], localId: 'red0');
      controller.setLocalInput(firing: true);
      _runFrames(controller, 20);

      expect(controller.players['red1']!.hp, 100);
    });

    test('projectiles are culled when they leave the arena', () {
      final controller = _makeController([
        _make(id: 'red0', team: Team.red, x: 900, y: 150, facingX: 1, facingY: 0),
        _make(id: 'blue0', team: Team.blue, x: 100, y: 400, hp: 100),
      ], localId: 'red0');
      controller.setLocalInput(firing: true);
      _runFrames(controller, 40);
      expect(controller.projectiles, isEmpty);
    });
  });

  group('networking template', () {
    test('sendLocalInputToHost forwards input through the adapter', () {
      final adapter = _RecordingAdapter();
      final controller = _makeController(
        [_make(id: 'red0', team: Team.red, x: 200, y: 200)],
        localId: 'red0',
        adapter: adapter,
      );
      controller.setLocalInput(moveY: 1, firing: true);
      controller.sendLocalInputToHost();
      expect(adapter.inputs, hasLength(1));
      expect(adapter.inputs.first.moveY, 1);
      expect(adapter.inputs.first.firing, isTrue);
    });

    test('host broadcast emits player and projectile snapshots', () {
      final adapter = _RecordingAdapter();
      final controller = _makeController(
        [
          _make(id: 'red0', team: Team.red, x: 200, y: 200),
          _make(id: 'blue0', team: Team.blue, x: 800, y: 200),
        ],
        localId: 'red0',
        isHost: true,
        adapter: adapter,
      );
      controller.step(0.016);
      expect(adapter.playerBroadcasts, hasLength(1));
      expect(adapter.playerBroadcasts.last, hasLength(2));
    });

    test('client applies authoritative remote snapshots', () {
      final controller = _makeController(
        [_make(id: 'red0', team: Team.red, x: 200, y: 200)],
        localId: 'red0',
        adapter: _RecordingAdapter(),
      );
      controller.applyRemotePlayer(
        const PlayerSnapshot(
          playerId: 'red0',
          playerName: 'Ruby',
          team: Team.red,
          x: 500,
          y: 400,
          facingX: 1,
          facingY: 0,
          hp: 50,
          alive: true,
        ),
      );
      expect(controller.players['red0']!.x, 500);
      expect(controller.players['red0']!.hp, 50);
    });

    test('remote input is applied and reflected in the next step', () {
      final adapter = _RecordingAdapter();
      final controller = _makeController(
        [
          _make(id: 'red0', team: Team.red, x: 200, y: 200),
          _make(id: 'blue0', team: Team.blue, x: 800, y: 200),
        ],
        localId: 'red0',
        adapter: adapter,
      );
      final before = controller.players['blue0']!.x;
      controller.applyRemoteInput(
        'blue0',
        const PlayerInput(moveX: -1),
      );
      controller.step(0.1);
      expect(controller.players['blue0']!.x, lessThan(before));
    });
  });

  group('snapshot codec', () {
    test('PlayerInput round-trips over JSON', () {
      const input = PlayerInput(moveX: 0.5, moveY: -0.25, firing: true, sequence: 7);
      expect(PlayerInput.fromJson(input.toJson()), input);
    });

    test('PlayerSnapshot round-trips over JSON', () {
      const snapshot = PlayerSnapshot(
        playerId: 'p1',
        playerName: 'Neo',
        team: Team.blue,
        x: 120,
        y: 80,
        facingX: -1,
        facingY: 0,
        hp: 75,
        alive: true,
      );
      expect(PlayerSnapshot.fromJson(snapshot.toJson()), snapshot);
    });
  });
}

PlayerEntity _make({
  required String id,
  required Team team,
  required double x,
  required double y,
  double facingX = 0,
  double facingY = 1,
  int hp = 100,
}) {
  return PlayerEntity(
    id: id,
    name: id,
    team: team,
    x: x,
    y: y,
    facingX: facingX,
    facingY: facingY,
    hp: hp,
  );
}

BattleSyncController _makeController(
  List<PlayerEntity> players, {
  String localId = 'red0',
  bool isHost = true,
  BattleSyncAdapter? adapter,
}) {
  return BattleSyncController(
    arena: const BattleArena(),
    localPlayerId: localId,
    initialPlayers: {for (final p in players) p.id: p},
    isHost: isHost,
    adapter: adapter ?? _RecordingAdapter(),
  );
}

void _runFrames(BattleSyncController controller, int frames, [double dt = 0.05]) {
  for (var i = 0; i < frames; i++) {
    controller.step(dt);
  }
}