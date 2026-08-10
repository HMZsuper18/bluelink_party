import 'dart:convert';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_shift/features/matrix_arena/domain/matrix_grid.dart';
import 'package:screen_shift/features/matrix_arena/domain/matrix_snapshots.dart';
import 'package:screen_shift/features/matrix_arena/domain/matrix_spawn.dart';
import 'package:screen_shift/features/matrix_arena/domain/matrix_world.dart';
import 'package:screen_shift/features/matrix_arena/game/matrix_arena_controller.dart';
import 'package:screen_shift/features/matrix_arena/game/matrix_interpolation.dart';
import 'package:screen_shift/features/matrix_arena/game/matrix_sync_adapter.dart';
import 'package:screen_shift/features/matrix_arena/game/matrix_viewport.dart';

/// Records pause/resume requests instead of sending them over the network.
class _PauseAwareAdapter implements MatrixSyncAdapter {
  bool? requestedPause;

  @override
  void requestPause(bool paused) {
    requestedPause = paused;
  }

  @override
  void sendInput(MatrixInput input) {}

  @override
  void sendPhase(MatrixPhaseMessage phase) {}

  @override
  void sendSnapshot(MatrixWorldSnapshot snapshot) {}

  @override
  void dispose() {}
}

void main() {
  const layout = MatrixLayoutManager();

  group('MatrixLayoutManager', () {
    test('2 players form a 2x1 horizontal grid', () {
      final grid = layout.gridForPlayerCount(2);
      expect(grid.columns, 2);
      expect(grid.rows, 1);
      expect(grid.count, 2);

      final tile1 = layout.tileForDevice(0, 2);
      final tile2 = layout.tileForDevice(1, 2);
      expect(tile1.column, 0);
      expect(tile1.row, 0);
      expect(tile2.column, 1);
      expect(tile2.row, 0);
      expect(tile1.left, 0);
      expect(tile2.left, 1000);
      expect(tile2.overlapsPoint(1500, 300), isTrue);
    });

    test('3 players form a horizontal split: top halves side by side, the '
        'bottom device spans the full row', () {
      final grid = layout.gridForPlayerCount(3);
      expect(grid.columns, 2);
      expect(grid.rows, 2);
      expect(grid.count, 3);

      final topLeft = layout.tileForDevice(0, 3);
      final topRight = layout.tileForDevice(1, 3);
      final bottom = layout.tileForDevice(2, 3);
      expect(topLeft.column, 0);
      expect(topLeft.row, 0);
      expect(topRight.column, 1);
      expect(topRight.row, 0);
      expect(bottom.column, 0);
      expect(bottom.row, 1);

      expect(topLeft.tileRect, const Rect.fromLTWH(0, 0, 1000, 600));
      expect(topRight.tileRect, const Rect.fromLTWH(1000, 0, 1000, 600));
      expect(bottom.tileRect, const Rect.fromLTWH(0, 600, 2000, 600),
          reason: 'the lone device spans the full width so every part of the '
              'world stays covered by a camera');
      expect(bottom.centerX, 1000);
      expect(bottom.centerY, 900);

      // The full-width bottom slice has no side neighbors, only the top seam.
      expect(bottom.hasLeftNeighbor, isFalse);
      expect(bottom.hasRightNeighbor, isFalse);
      expect(bottom.hasTopNeighbor, isTrue);
      expect(bottom.hasBottomNeighbor, isFalse);
      expect(topLeft.hasRightNeighbor, isTrue);
      expect(topRight.hasLeftNeighbor, isTrue);
    });

    test('4 players form a 2x2 grid', () {
      final grid = layout.gridForPlayerCount(4);
      expect(grid.columns, 2);
      expect(grid.rows, 2);
      expect(grid.count, 4);

      final tiles = [for (var i = 0; i < 4; i++) layout.tileForDevice(i, 4)];
      expect(tiles[0].tileRect, const Rect.fromLTWH(0, 0, 1000, 600));
      expect(tiles[1].tileRect, const Rect.fromLTWH(1000, 0, 1000, 600));
      expect(tiles[2].tileRect, const Rect.fromLTWH(0, 600, 1000, 600));
      expect(tiles[3].tileRect, const Rect.fromLTWH(1000, 600, 1000, 600));
    });

    test('world spans the combined matrix', () {
      final matrix = layout.matrixForPlayerCount(4);
      expect(matrix.worldWidth, 2000);
      expect(matrix.worldHeight, 1200);
      expect(matrix.deviceCount, 4);
    });

    test('rejects unsupported player counts', () {
      expect(() => layout.gridForPlayerCount(1), throwsArgumentError);
      expect(() => layout.gridForPlayerCount(5), throwsArgumentError);
    });
  });

  group('Tile neighbor flags', () {
    test('middle tile has both horizontal neighbors', () {
      const matrix = TileMatrix(columns: 3, rows: 1);
      final middle = matrix.layoutForIndex(1);
      expect(middle.hasLeftNeighbor, isTrue);
      expect(middle.hasRightNeighbor, isTrue);
      expect(middle.hasTopNeighbor, isFalse);
      expect(middle.hasBottomNeighbor, isFalse);
    });

    test('edge tile has only an inward neighbor', () {
      const matrix = TileMatrix(columns: 3, rows: 1);
      final edge = matrix.layoutForIndex(0);
      expect(edge.hasLeftNeighbor, isFalse);
      expect(edge.hasRightNeighbor, isTrue);
    });

    test('tile offsets track world arena origin', () {
      const matrix = TileMatrix(columns: 2, rows: 2);
      final tile = matrix.layoutForIndex(3);
      expect(tile.left, 1000);
      expect(tile.top, 600);
      expect(tile.centerX, 1500);
      expect(tile.centerY, 900);
    });
  });

  group('MatrixSpawnManager', () {
    test('spawns across all tiles of the global world', () {
      const matrix = TileMatrix(columns: 2, rows: 2);
      final spawner = MatrixSpawnManager(matrix: matrix);

      final seenTiles = <int>{};
      for (var i = 0; i < 500; i++) {
        final point = spawner.randomPoint();
        expect(point.x, inInclusiveRange(0, matrix.worldWidth));
        expect(point.y, inInclusiveRange(0, matrix.worldHeight));
        seenTiles.add(point.tileIndex);
      }
      expect(seenTiles, hasLength(4));
    });

    test('a player may spawn inside another tile', () {
      const matrix = TileMatrix(columns: 3, rows: 1);
      final spawner = MatrixSpawnManager(matrix: matrix, random: Random(7));
      final tiles = <int>{};
      for (var i = 0; i < 100; i++) {
        tiles.add(spawner.randomPoint().tileIndex);
      }
      expect(tiles, containsAll([0, 1, 2]));
    });

    test('spawnAll keeps minimum separation', () {
      const matrix = TileMatrix(columns: 2, rows: 1);
      final spawner = MatrixSpawnManager(matrix: matrix, random: Random(3));
      final spawns = spawner.spawnAll(2);
      expect(spawns, hasLength(2));
      final dx = spawns[0].x - spawns[1].x;
      final dy = spawns[0].y - spawns[1].y;
      expect(dx * dx + dy * dy, greaterThanOrEqualTo(160 * 160));
    });
  });

  group('MatrixArenaController host engine', () {
    MatrixArenaController makeHost({
      int players = 2,
      MatrixWorldConfig? config,
    }) {
      final matrix = MatrixLayoutManager().matrixForPlayerCount(players);
      return MatrixArenaController(
        matrix: matrix,
        deviceCount: players,
        isHost: true,
        config: config,
        random: Random(42),
      );
    }

    test('creates one avatar per device', () {
      final host = makeHost(players: 4);
      expect(host.players, hasLength(4));
      for (final player in host.players) {
        expect(player.alive, isTrue);
        expect(player.hp, 100);
      }
    });

    test('runs through calibration and countdown into play', () {
      final host = makeHost();
      expect(host.phase, MatrixMatchPhase.calibrating);

      for (var i = 0; i < 600; i++) {
        host.step(1 / 60);
      }
      expect(host.phase, MatrixMatchPhase.playing);
    });

    test('routes remote input into the authoritative simulation', () {
      final host = makeHost();
      for (var i = 0; i < 600; i++) {
        host.step(1 / 60);
      }

      final startX = host.players[1].x;
      host.applyRemoteInput(const MatrixInput(
        deviceIndex: 1,
        moveX: 1,
        moveY: 0,
        firing: false,
      ));
      for (var i = 0; i < 60; i++) {
        host.step(1 / 60);
      }
      expect(host.players[1].x, greaterThan(startX));
    });

    test('projectiles travel across the matrix boundary', () {
      final host = makeHost();
      for (var i = 0; i < 600; i++) {
        host.step(1 / 60);
      }

      final shooter = host.players[0];
      final bystander = host.players[1];
      shooter.x = 500;
      shooter.y = 300;
      shooter.facingYaw = 0;
      bystander.x = 1900;
      bystander.y = 300;
      bystander.facingYaw = pi;

      host.applyRemoteInput(const MatrixInput(
        deviceIndex: 0,
        moveX: 0,
        moveY: 0,
        firing: true,
      ));
      for (var i = 0; i < 70; i++) {
        host.step(1 / 60);
      }
      host.applyRemoteInput(const MatrixInput(
        deviceIndex: 0,
        moveX: 0,
        moveY: 0,
        firing: false,
      ));

      expect(host.players[0].x, lessThan(1000));
      expect(
        host.projectiles.where((p) => p.x > 1000).length,
        greaterThan(0),
      );
    });

    test('projectiles damage opposing players on contact', () {
      final host = makeHost();
      for (var i = 0; i < 600; i++) {
        host.step(1 / 60);
      }

      final attacker = host.players[0];
      final defender = host.players[1];
      attacker.x = 800;
      attacker.y = 300;
      attacker.facingYaw = 0;
      defender.x = 1100;
      defender.y = 300;
      defender.facingYaw = pi;

      host.applyRemoteInput(const MatrixInput(
        deviceIndex: 0,
        moveX: 0,
        moveY: 0,
        firing: true,
      ));
      for (var i = 0; i < 90; i++) {
        host.step(1 / 60);
      }
      host.applyRemoteInput(const MatrixInput(
        deviceIndex: 0,
        moveX: 0,
        moveY: 0,
        firing: false,
      ));

      expect(host.players[0].hp, 100);
      expect(host.players[1].hp, lessThan(100));
    });
  });

  group('MatrixViewportCamera', () {
    test('fits the tile within the screen at reference aspect', () {
      const matrix = TileMatrix(columns: 2, rows: 1);
      final tile = matrix.layoutForIndex(1);
      final camera = MatrixViewportCamera(
        tile: tile,
        screenSize: const Size(1600, 800),
      );

      expect(camera.playRect.width / camera.playRect.height,
          closeTo(1000 / 600, 0.001));
      expect(camera.playRect.center.dx, closeTo(800, 0.001));
      expect(camera.playRect.center.dy, closeTo(400, 0.001));
    });

    test('maps world coordinates to tile-local screen space', () {
      const matrix = TileMatrix(columns: 2, rows: 1);
      final tile = matrix.layoutForIndex(1);
      final camera = MatrixViewportCamera(
        tile: tile,
        screenSize: const Size(800, 600),
      );

      final origin = camera.worldToScreen(1000, 0);
      expect(origin.dx, closeTo(camera.playRect.left, 0.001));
      expect(origin.dy, closeTo(camera.playRect.top, 0.001));

      final edge = camera.worldToScreen(2000, 0);
      expect(edge.dx, closeTo(camera.playRect.right, 0.001));
    });
  });

  group('MatrixControlZones', () {
    test('wide screens get dedicated side control zones', () {
      const play = Rect.fromLTWH(400, 0, 800, 600);
      final zones = MatrixControlZones.compute(
        screenSize: const Size(1600, 800),
        playRect: play,
        padding: EdgeInsets.zero,
      );
      expect(zones.joystickRect.center.dx, lessThan(play.left));
      expect(zones.fireRect.center.dx, greaterThan(play.right));
      expect(zones.healthBarsRect, isNotNull);
    });

    test('small margins fall back to in-play overlay controls', () {
      final zones = MatrixControlZones.compute(
        screenSize: const Size(800, 600),
        playRect: const Rect.fromLTWH(0, 75, 800, 450),
        padding: EdgeInsets.zero,
      );
      expect(zones.joystickRect.bottom, lessThanOrEqualTo(600));
      expect(zones.fireRect.bottom, lessThanOrEqualTo(600));
      expect(zones.healthBarsRect, isNotNull);
    });
  });

  group('pause & resume', () {
    MatrixArenaController makeHost({int players = 2}) {
      final matrix = MatrixLayoutManager().matrixForPlayerCount(players);
      return MatrixArenaController(
        matrix: matrix,
        deviceCount: players,
        isHost: true,
        config: const MatrixWorldConfig(
          maxHp: 100,
          playerSpeed: 200,
          respawnDelay: 10,
        ),
        random: Random(42),
      );
    }

    MatrixArenaController makeClient({MatrixSyncAdapter? adapter}) {
      return MatrixArenaController(
        matrix: MatrixLayoutManager().matrixForPlayerCount(2),
        deviceCount: 2,
        isHost: false,
        deviceIndex: 1,
        adapter: adapter ?? const NoopMatrixSyncAdapter(),
      );
    }

    test('host pause freezes the world and the match clock until resumed', () {
      final host = makeHost();
      for (var i = 0; i < 600; i++) {
        host.step(1 / 60);
      }
      expect(host.phase, MatrixMatchPhase.playing);

      host.applyRemoteInput(const MatrixInput(
        deviceIndex: 0,
        moveX: 1,
        moveY: 0,
        firing: false,
      ));
      for (var i = 0; i < 30; i++) {
        host.step(1 / 60);
      }
      final xBefore = host.players[0].x;
      final clockBefore = host.elapsedMatchTime;

      host.pause();
      expect(host.isPaused, isTrue);
      for (var i = 0; i < 60; i++) {
        host.step(1 / 60);
      }
      expect(host.players[0].x, xBefore,
          reason: 'paused world must not move');
      expect(host.elapsedMatchTime, clockBefore,
          reason: 'paused match clock must not advance');

      host.resume();
      expect(host.isPaused, isFalse);
      for (var i = 0; i < 30; i++) {
        host.step(1 / 60);
      }
      expect(host.players[0].x, isNot(xBefore),
          reason: 'world must move again after resuming');
      expect(host.elapsedMatchTime, greaterThan(clockBefore));
    });

    test('requestPause on a client forwards the request over the adapter', () {
      final adapter = _PauseAwareAdapter();
      final client = makeClient(adapter: adapter);

      client.requestPause(true);
      expect(adapter.requestedPause, isTrue);
      expect(client.isPaused, isFalse,
          reason: 'only the host actually freezes the match');

      client.requestPause(false);
      expect(adapter.requestedPause, isFalse);
    });

    test('requestPause on the host pauses directly without the adapter', () {
      final host = makeHost();
      host.requestPause(true);
      expect(host.isPaused, isTrue);
      host.requestPause(false);
      expect(host.isPaused, isFalse);
    });

    test('client mirrors the paused flag from the host phase message', () {
      final client = makeClient();
      client.applyRemotePhase(const MatrixPhaseMessage(
        phase: MatrixMatchPhase.playing,
        remainingSeconds: 0,
        paused: true,
      ));
      expect(client.isPaused, isTrue);

      client.applyRemotePhase(const MatrixPhaseMessage(
        phase: MatrixMatchPhase.playing,
        remainingSeconds: 0,
        paused: false,
      ));
      expect(client.isPaused, isFalse);
    });
  });

  group('MatrixSnapshotBuffer', () {
    test('empty buffer yields an empty frame', () {
      final buffer = MatrixSnapshotBuffer();
      final frame = buffer.sample();
      expect(frame.players, isEmpty);
    });

    test('interpolates between two snapshots', () {
      final buffer = MatrixSnapshotBuffer();
      buffer.push(MatrixWorldSnapshot(
        seq: 1,
        timeStamp: 0,
        players: const [
          MatrixPlayerSnapshot(
            deviceIndex: 0,
            name: 'P1',
            x: 0,
            y: 0,
            facingYaw: 0,
            hp: 100,
            maxHp: 100,
            alive: true,
            kills: 0,
          ),
        ],
        projectiles: const [],
      ));
      buffer.push(MatrixWorldSnapshot(
        seq: 2,
        timeStamp: 100,
        players: const [
          MatrixPlayerSnapshot(
            deviceIndex: 0,
            name: 'P1',
            x: 100,
            y: 0,
            facingYaw: 0,
            hp: 90,
            maxHp: 100,
            alive: true,
            kills: 0,
          ),
        ],
        projectiles: const [],
      ));

      buffer.advanceLocalClock(100);
      final frame = buffer.sample();
      expect(frame.players.single.x, greaterThanOrEqualTo(0));
      expect(frame.players.single.x, lessThanOrEqualTo(100));
      expect(frame.players.single.hp, 90);
    });
  });

  group('snapshot wire format', () {
    test('MatrixInput round-trips through JSON', () {
      const input = MatrixInput(
        deviceIndex: 2,
        moveX: 0.5,
        moveY: -0.8,
        firing: true,
        sequence: 12,
      );
      final decoded = MatrixInput.fromJson(
        jsonDecode(jsonEncode(input.toJson())),
      );
      expect(decoded, input);
    });

    test('MatrixPhaseMessage round-trips the paused flag through JSON', () {
      const message = MatrixPhaseMessage(
        phase: MatrixMatchPhase.playing,
        remainingSeconds: 2.5,
        winnerIndex: 1,
        paused: true,
      );
      final decoded = MatrixPhaseMessage.fromJson(
        jsonDecode(jsonEncode(message.toJson())),
      );
      expect(decoded.phase, MatrixMatchPhase.playing);
      expect(decoded.remainingSeconds, 2.5);
      expect(decoded.winnerIndex, 1);
      expect(decoded.paused, isTrue);

      const unpaused = MatrixPhaseMessage(
        phase: MatrixMatchPhase.playing,
        remainingSeconds: 2.5,
      );
      final decodedUnpaused = MatrixPhaseMessage.fromJson(
        jsonDecode(jsonEncode(unpaused.toJson())),
      );
      expect(decodedUnpaused.paused, isFalse);
    });

    test('MatrixWorldSnapshot round-trips through JSON', () {
      const snapshot = MatrixWorldSnapshot(
        seq: 7,
        timeStamp: 1234.5,
        players: [
          MatrixPlayerSnapshot(
            deviceIndex: 0,
            name: 'P1',
            x: 123.4,
            y: 56.7,
            facingYaw: 0.5,
            hp: 100,
            maxHp: 100,
            alive: true,
            kills: 2,
          ),
        ],
        projectiles: [
          MatrixProjectileSnapshot(
            id: 3,
            ownerIndex: 1,
            x: 10,
            y: 20,
            vx: 30,
            vy: 40,
            life: 0.9,
          ),
        ],
      );
      final decoded = MatrixWorldSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())),
      );
      expect(decoded.seq, 7);
      expect(decoded.timeStamp, 1234.5);
      expect(decoded.players.single.x, 123.4);
      expect(decoded.players.single.kills, 2);
      expect(decoded.projectiles.single.id, 3);
    });
  });
}