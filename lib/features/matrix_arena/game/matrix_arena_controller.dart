import 'dart:collection';
import 'dart:math';

import '../domain/matrix_grid.dart';
import '../domain/matrix_snapshots.dart';
import '../domain/matrix_spawn.dart';
import '../domain/matrix_world.dart';
import 'matrix_interpolation.dart';
import 'matrix_sync_adapter.dart';

class MatrixArenaController {
  MatrixArenaController({
    required this.matrix,
    required this.deviceCount,
    required this.isHost,
    MatrixWorldConfig? config,
    MatrixSyncAdapter? adapter,
    Random? random,
    this.deviceIndex = 0,
    this.calibrationDuration = 6,
    this.countdownDuration = 3,
  })  : config = config ?? const MatrixWorldConfig(),
        adapter = adapter ?? const NoopMatrixSyncAdapter(),
        _random = random ?? Random() {
    _spawnManager = MatrixSpawnManager(matrix: matrix, random: _random);
    _buildPlayers();
    _beginCalibration();
  }

  final TileMatrix matrix;
  final int deviceCount;
  final bool isHost;
  final MatrixWorldConfig config;
  final MatrixSyncAdapter adapter;
  final int deviceIndex;
  final double calibrationDuration;
  final double countdownDuration;
  final Random _random;

  late final MatrixSpawnManager _spawnManager;
  final List<MatrixWorldAvatar> _players = [];
  final List<MatrixWorldProjectile> _projectiles = [];
  final Map<int, MatrixInput> _inputs = {};
  final MatrixSnapshotBuffer _remoteBuffer = MatrixSnapshotBuffer();

  MatrixMatchPhase _phase = MatrixMatchPhase.calibrating;
  double _countdownRemaining = 6;
  double _elapsedMatchTime = 0;
  double _snapshotTime = 0;
  int _snapshotSeq = 0;
  int _projectileSeq = 0;
  int _localSequence = 0;
  int? _winnerIndex;
  bool _paused = false;

  MatrixInput _localInput = const MatrixInput(
    deviceIndex: 0,
    moveX: 0,
    moveY: 0,
    firing: false,
  );

  MatrixMatchPhase get phase => _phase;
  double get countdownRemaining => _countdownRemaining;
  double get elapsedMatchTime => _elapsedMatchTime;
  int? get winnerIndex => _winnerIndex;
  bool get isMatchOver => _phase == MatrixMatchPhase.finished;

  /// True while the host has frozen the shared match for every device.
  bool get isPaused => _paused;

  List<MatrixWorldAvatar> get players => UnmodifiableListView(_players);
  List<MatrixWorldProjectile> get projectiles =>
      UnmodifiableListView(_projectiles);

  MatrixWorldAvatar? playerAt(int deviceIndex) {
    if (deviceIndex < 0 || deviceIndex >= _players.length) return null;
    return _players[deviceIndex];
  }

  MatrixTileLayout get localTile => matrix.layoutForIndex(deviceIndex);

  MatrixInterpolationFrame renderFrame() {
    if (isHost) {
      return MatrixInterpolationFrame(
        players: _players
            .map((p) => MatrixPlayerSnapshot(
                  deviceIndex: p.deviceIndex,
                  name: p.name,
                  x: p.x,
                  y: p.y,
                  facingYaw: p.facingYaw,
                  hp: p.hp,
                  maxHp: p.maxHp,
                  alive: p.alive,
                  kills: p.kills,
                  tileX:
                      matrix.layoutForIndex(p.deviceIndex).column,
                  tileY: matrix.layoutForIndex(p.deviceIndex).row,
                  columns: matrix.columns,
                  rows: matrix.rows,
                ))
            .toList(),
        projectiles: _projectiles
            .map(
              (p) => MatrixProjectileSnapshot(
                id: p.id,
                ownerIndex: p.ownerIndex,
                x: p.x,
                y: p.y,
                vx: p.vx,
                vy: p.vy,
                life: p.life,
              ),
            )
            .toList(),
        ageMs: 0,
      );
    }
    return _remoteBuffer.sample();
  }

  void _buildPlayers() {
    _players.clear();
    for (var i = 0; i < deviceCount; i++) {
      _players.add(MatrixWorldAvatar(
        deviceIndex: i,
        name: 'Player ${i + 1}',
        x: 0,
        y: 0,
        hp: config.maxHp,
        maxHp: config.maxHp,
      ));
    }
  }

  void _beginCalibration() {
    _paused = false;
    _phase = MatrixMatchPhase.calibrating;
    _countdownRemaining = calibrationDuration;
    _elapsedMatchTime = 0;
    _winnerIndex = null;
    _snapshotSeq = 0;
    _projectileSeq = 0;
    _projectiles.clear();
    for (final player in _players) {
      final spawn = _spawnManager.randomPoint();
      player.spawnAt(nextX: spawn.x, nextY: spawn.y);
    }
    if (!isHost) return;
    _broadcastPhase();
    _broadcastSnapshot(now: 0);
  }

  void beginMatch() {
    if (!isHost) return;
    _beginCalibration();
  }

  void _broadcastPhase() {
    adapter.sendPhase(MatrixPhaseMessage(
      phase: _phase,
      remainingSeconds: _countdownRemaining,
      winnerIndex: _winnerIndex,
      paused: _paused,
    ));
  }

  void _broadcastSnapshot({required double now}) {
    final players = _players
        .map((p) => MatrixPlayerSnapshot(
              deviceIndex: p.deviceIndex,
              name: p.name,
              x: p.x,
              y: p.y,
              facingYaw: p.facingYaw,
              hp: p.hp,
              maxHp: p.maxHp,
              alive: p.alive,
              kills: p.kills,
              tileX: matrix.layoutForIndex(p.deviceIndex).column,
              tileY: matrix.layoutForIndex(p.deviceIndex).row,
              columns: matrix.columns,
              rows: matrix.rows,
            ))
        .toList();
    final projectiles = _projectiles
        .map((p) => MatrixProjectileSnapshot(
              id: p.id,
              ownerIndex: p.ownerIndex,
              x: p.x,
              y: p.y,
              vx: p.vx,
              vy: p.vy,
              life: p.life,
            ))
        .toList();
    adapter.sendSnapshot(MatrixWorldSnapshot(
      seq: _snapshotSeq++,
      timeStamp: now,
      players: players,
      projectiles: projectiles,
    ));
    adapter.sendPhase(MatrixPhaseMessage(
      phase: _phase,
      remainingSeconds: _countdownRemaining,
      winnerIndex: _winnerIndex,
      paused: _paused,
    ));
  }

  void setLocalInput({
    required double moveX,
    required double moveY,
    required bool firing,
  }) {
    _localInput = MatrixInput(
      deviceIndex: deviceIndex,
      moveX: moveX,
      moveY: moveY,
      firing: firing,
      sequence: ++_localSequence,
    );
    _inputs[deviceIndex] = _localInput;
    adapter.sendInput(_localInput);
  }

  void sendLocalInputToHost() {
    adapter.sendInput(_localInput);
  }

  void applyRemoteInput(MatrixInput input) {
    if (isHost) {
      _inputs[input.deviceIndex] = input;
    }
  }

  void applyRemoteSnapshot(MatrixWorldSnapshot snapshot) {
    if (isHost) return;
    _remoteBuffer.push(snapshot);
    _applySnapshotToPlayers(snapshot);
    _projectiles.clear();
    for (final p in snapshot.projectiles) {
      _projectiles.add(MatrixWorldProjectile(
        id: p.id,
        ownerIndex: p.ownerIndex,
        x: p.x,
        y: p.y,
        vx: p.vx,
        vy: p.vy,
        life: p.life,
      ));
    }
  }

  void applyRemotePhase(MatrixPhaseMessage phase) {
    if (isHost) return;
    _phase = phase.phase;
    _countdownRemaining = phase.remainingSeconds;
    _winnerIndex = phase.winnerIndex;
    _paused = phase.paused;
  }

  /// Host only: freeze the match for every device. Clients converge on the
  /// frozen frame through the continuing snapshot stream and show the pause
  /// overlay once they receive the paused phase flag.
  void pause() {
    if (!isHost || _paused) return;
    _paused = true;
    _broadcastPhase();
  }

  /// Host only: unfreeze the shared match.
  void resume() {
    if (!isHost || !_paused) return;
    _paused = false;
    _broadcastPhase();
  }

  /// Any device: pause/resume the shared match. The host applies the request
  /// directly; clients forward it over the game-command channel.
  void requestPause(bool paused) {
    if (isHost) {
      if (paused) {
        pause();
      } else {
        resume();
      }
    } else {
      adapter.requestPause(paused);
    }
  }

  void _applySnapshotToPlayers(MatrixWorldSnapshot snapshot) {
    for (final snapshotPlayer in snapshot.players) {
      final player = playerAt(snapshotPlayer.deviceIndex);
      if (player == null) continue;
      player.x = snapshotPlayer.x;
      player.y = snapshotPlayer.y;
      player.facingYaw = snapshotPlayer.facingYaw;
      player.hp = snapshotPlayer.hp;
      player.alive = snapshotPlayer.alive;
      player.kills = snapshotPlayer.kills;
    }
  }

  void step(double dt) {
    if (dt <= 0) return;
    _remoteBuffer.advanceLocalClock(dt * 1000);
    if (!isHost) return;

    if (_paused) {
      // Keep streaming the frozen world (and the paused phase flag) so every
      // device converges on the same still frame and shows the pause overlay.
      _snapshotTime += dt;
      if (_snapshotTime >= 0.25) {
        _snapshotTime = 0;
        _broadcastSnapshot(now: _elapsedMatchTime);
        _broadcastPhase();
      }
      return;
    }

    switch (_phase) {
      case MatrixMatchPhase.calibrating:
        _countdownRemaining -= dt;
        _snapshotTime += dt;
        if (_snapshotTime >= 0.25) {
          _snapshotTime = 0;
          _broadcastSnapshot(now: _elapsedMatchTime);
        }
        if (_countdownRemaining <= 0) {
          _phase = MatrixMatchPhase.countdown;
          _countdownRemaining = countdownDuration;
          _broadcastPhase();
          _broadcastSnapshot(now: _elapsedMatchTime);
        }
        break;
      case MatrixMatchPhase.countdown:
        _countdownRemaining -= dt;
        _snapshotTime += dt;
        if (_snapshotTime >= 0.25) {
          _snapshotTime = 0;
          _broadcastSnapshot(now: _elapsedMatchTime);
        }
        if (_countdownRemaining <= 0) {
          _phase = MatrixMatchPhase.playing;
          _countdownRemaining = 0;
          _elapsedMatchTime = 0;
          _broadcastPhase();
          _broadcastSnapshot(now: 0);
        }
        break;
      case MatrixMatchPhase.playing:
        _elapsedMatchTime += dt;
        _simulate(dt);
        _snapshotTime += dt;
        if (_snapshotTime >= 0.05) {
          _snapshotTime = 0;
          _broadcastSnapshot(now: _elapsedMatchTime);
        }
        if (_winnerIndex != null) {
          _phase = MatrixMatchPhase.finished;
          _broadcastPhase();
        }
        break;
      case MatrixMatchPhase.finished:
        break;
    }
  }

  void _simulate(double dt) {
    for (final player in _players) {
      if (!player.alive) {
        player.respawnTimer += dt;
        if (player.respawnTimer >= config.respawnDelay) {
          final spawn = _spawnManager.randomPoint();
          player.spawnAt(nextX: spawn.x, nextY: spawn.y);
        }
        continue;
      }
      final input = _inputs[player.deviceIndex] ?? const MatrixInput(
        deviceIndex: -1,
        moveX: 0,
        moveY: 0,
        firing: false,
      );
      final magnitude = sqrt(input.moveX * input.moveX + input.moveY * input.moveY);
      if (magnitude > 0.001) {
        player.vx = input.moveX / magnitude * config.playerSpeed;
        player.vy = input.moveY / magnitude * config.playerSpeed;
        player.facingYaw = atan2(input.moveY, input.moveX);
      } else {
        player.vx = 0;
        player.vy = 0;
      }
      player.x += player.vx * dt;
      player.y += player.vy * dt;
      final clamped = _spawnManager.clampedWithinWorld(
        config,
        player.x,
        player.y,
      );
      player.x = clamped.x;
      player.y = clamped.y;

      player.fireCooldown -= dt;
      if (input.firing && player.fireCooldown <= 0) {
        _fireProjectile(player);
        player.fireCooldown = config.fireCooldown;
      }
    }

    for (final projectile in _projectiles) {
      projectile.step(dt);
    }
    _projectiles.removeWhere((p) => p.isExpired);

    _resolveProjectileHits();

    if (_players.length > 1) {
      _separateAvatars();
    }

    for (final player in _players) {
      if (player.kills >= config.killsToWin && _winnerIndex == null) {
        _winnerIndex = player.deviceIndex;
      }
    }
  }

  void _fireProjectile(MatrixWorldAvatar player) {
    final cosA = cos(player.facingYaw);
    final sinA = sin(player.facingYaw);
    _projectiles.add(MatrixWorldProjectile(
      id: _projectileSeq++,
      ownerIndex: player.deviceIndex,
      x: player.x + cosA * (config.playerRadius + 4),
      y: player.y + sinA * (config.playerRadius + 4),
      vx: cosA * config.projectileSpeed,
      vy: sinA * config.projectileSpeed,
      life: config.projectileLife,
    ));
  }

  void _resolveProjectileHits() {
    for (final projectile in _projectiles) {
      if (projectile.isExpired) continue;
      for (final player in _players) {
        if (!player.alive) continue;
        if (player.deviceIndex == projectile.ownerIndex) continue;
        final dx = projectile.x - player.x;
        final dy = projectile.y - player.y;
        final hitRadius = config.playerHitbox + config.projectileRadius;
        if (dx * dx + dy * dy <= hitRadius * hitRadius) {
          player.takeDamage(config.projectileDamage.toInt());
          projectile.life = 0;
          if (player.isDefeated) {
            final owner = playerAt(projectile.ownerIndex);
            if (owner != null) {
              owner.kills += 1;
            }
          }
          break;
        }
      }
    }
  }

  void _separateAvatars() {
    for (var i = 0; i < _players.length; i++) {
      for (var j = i + 1; j < _players.length; j++) {
        final a = _players[i];
        final b = _players[j];
        if (!a.alive || !b.alive) continue;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dist = sqrt(dx * dx + dy * dy);
        final minDist = config.playerRadius * 2;
        if (dist < minDist && dist > 0.0001) {
          final push = (minDist - dist) / 2;
          final nx = dx / dist;
          final ny = dy / dist;
          a.x -= nx * push;
          a.y -= ny * push;
          b.x += nx * push;
          b.y += ny * push;
        }
      }
    }
  }

  void dispose() {}
}