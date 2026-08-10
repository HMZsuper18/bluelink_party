import 'dart:collection';
import 'dart:math';
import 'dart:ui' show Color;

import '../../../core/theme/app_colors.dart';
import '../../../data/models/lobby_room.dart';
import '../../../data/models/team.dart';
import '../domain/battle_arena.dart';
import '../domain/game_effects.dart';
import '../domain/game_snapshots.dart';
import '../domain/player_entity.dart';
import '../domain/projectile_entity.dart';

abstract class BattleSyncAdapter {
  void sendPlayerInput(PlayerInput input);

  void broadcastPlayers(List<PlayerSnapshot> snapshots);

  void broadcastProjectiles(List<ProjectileSnapshot> snapshots);
}

class NoopBattleSyncAdapter implements BattleSyncAdapter {
  @override
  void sendPlayerInput(PlayerInput input) {}

  @override
  void broadcastPlayers(List<PlayerSnapshot> snapshots) {}

  @override
  void broadcastProjectiles(List<ProjectileSnapshot> snapshots) {}
}

class BattleSyncController {
  BattleSyncController({
    required this.arena,
    required this.localPlayerId,
    BattleSyncAdapter? adapter,
    Map<String, PlayerEntity>? initialPlayers,
    this.isHost = false,
  })  : adapter = adapter ?? NoopBattleSyncAdapter(),
        _players = initialPlayers ?? <String, PlayerEntity>{};

  factory BattleSyncController.fromRoom({
    required LobbyRoom room,
    required String localPlayerId,
    BattleArena? arena,
    BattleSyncAdapter? adapter,
    bool isHost = false,
  }) {
    final a = arena ?? const BattleArena();
    final players = <String, PlayerEntity>{};
    for (final team in Team.all) {
      final slots = room.slotsOf(team);
      for (final slot in slots) {
        if (!slot.isFilled || slot.playerId == null) continue;
        final spawn = a.spawnFor(team, slot.seat);
        players[slot.playerId!] = PlayerEntity(
          id: slot.playerId!,
          name: slot.playerName ?? 'Player',
          team: team,
          x: spawn.x,
          y: spawn.y,
          facingX: spawn.facingX,
          facingY: spawn.facingY,
          isLocal: slot.playerId == localPlayerId,
          radius: a.playerRadius,
          hitboxSize: a.playerHitbox,
          maxHp: 100,
          hp: 100,
        );
      }
    }
    return BattleSyncController(
      arena: a,
      localPlayerId: localPlayerId,
      adapter: adapter,
      initialPlayers: players,
      isHost: isHost,
    );
  }

  final BattleArena arena;
  final String localPlayerId;
  final BattleSyncAdapter adapter;
  final bool isHost;

  final Map<String, PlayerEntity> _players;
  final Map<String, PlayerInput> _inputs = {};
  final Map<String, double> _cooldowns = {};
  final List<ProjectileEntity> _projectiles = [];
  final List<GameEffect> _effects = [];
  int _fireSequence = 0;
  int _projectileSequence = 0;
  double _elapsed = 0;

  Team? _winnerTeam;
  bool _isMatchOver = false;

  PlayerInput _localInput = const PlayerInput();

  void Function(PlayerEntity defeat)? onPlayerDefeated;
  void Function(Team? winner)? onMatchEnded;
  void Function(PlayerEntity shooter)? onShotFired;
  void Function(PlayerEntity defender)? onPlayerHit;

  Map<String, PlayerEntity> get players => _players;
  UnmodifiableListView<ProjectileEntity> get projectiles =>
      UnmodifiableListView(_projectiles);
  UnmodifiableListView<GameEffect> get effects =>
      UnmodifiableListView(_effects);
  double get elapsed => _elapsed;
  Team? get winnerTeam => _winnerTeam;
  bool get isMatchOver => _isMatchOver;
  PlayerEntity? get localPlayer => _players[localPlayerId];

  int get aliveRedCount => _players.values
      .where((p) => p.team == Team.red && p.alive)
      .length;

  int get aliveBlueCount => _players.values
      .where((p) => p.team == Team.blue && p.alive)
      .length;

  void setLocalInput({double moveX = 0, double moveY = 0, bool firing = false}) {
    _localInput = PlayerInput(moveX: moveX, moveY: moveY, firing: firing);
    _inputs[localPlayerId] = _localInput;
  }

  void sendLocalInputToHost() {
    adapter.sendPlayerInput(_localInput.copyWith(sequence: ++_fireSequence));
  }

  void applyRemoteInput(String playerId, PlayerInput input) {
    if (playerId == localPlayerId || !_players.containsKey(playerId)) return;
    _inputs[playerId] = input;
  }

  void step(double dt) {
    if (_isMatchOver) return;

    for (final player in _players.values) {
      if (!player.alive) continue;
      final input = _inputs[player.id] ?? const PlayerInput();
      _integrate(player, input, dt);
    }

    _stepProjectiles(dt);
    _resolveProjectileHits();
    _cullProjectiles();
    _advanceEffects(dt);
    _elapsed += dt;

    if (_isMatchOver) return;
    if (isHost) {
      broadcastPlayerStates();
      broadcastProjectileStates();
    }
    _checkWin();
  }

  void _integrate(PlayerEntity player, PlayerInput input, double dt) {
    final mag = sqrt(input.moveX * input.moveX + input.moveY * input.moveY);
    if (mag > 0.001) {
      final nx = input.moveX / mag;
      final ny = input.moveY / mag;
      player.vx = nx * arena.playerSpeed;
      player.vy = ny * arena.playerSpeed;
      player.facingX = nx;
      player.facingY = ny;
    } else {
      player.vx = 0;
      player.vy = 0;
    }

    player.x += player.vx * dt;
    player.y += player.vy * dt;

    final clamped = arena.clampInside(player.x, player.y, player.radius);
    player.x = clamped.x;
    player.y = clamped.y;

    final cooldown = _cooldowns[player.id] ?? 0;
    if (input.firing && cooldown <= 0) {
      _fire(player);
      _cooldowns[player.id] = arena.fireCooldown;
    } else if (cooldown > 0) {
      _cooldowns[player.id] = cooldown - dt;
    }
  }

  void _fire(PlayerEntity player) {
    final totalRadius = player.radius + arena.projectileRadius;
    final startX = player.x + player.facingX * (totalRadius + 2);
    final startY = player.y + player.facingY * (totalRadius + 2);
    _addEffect(
      GameEffect(
        type: GameEffectType.muzzle,
        x: startX,
        y: startY,
        vx: player.facingX,
        vy: player.facingY,
        color: _teamColorFx(player.team),
        life: 0.16,
      ),
    );
    onShotFired?.call(player);
    _projectiles.add(
      ProjectileEntity(
        id: '${player.id}_${++_projectileSequence}',
        ownerId: player.id,
        ownerTeam: player.team,
        x: startX,
        y: startY,
        vx: player.facingX * arena.projectileSpeed,
        vy: player.facingY * arena.projectileSpeed,
        radius: arena.projectileRadius,
        damage: arena.projectileDamage,
        life: arena.projectileLife,
        maxLife: arena.projectileLife,
      ),
    );
  }

  void _stepProjectiles(double dt) {
    for (final projectile in _projectiles) {
      projectile.step(dt);
    }
  }

  void _resolveProjectileHits() {
    final removals = <int>[];
    for (var i = 0; i < _projectiles.length; i++) {
      final projectile = _projectiles[i];
      if (projectile.isExpired) {
        removals.add(i);
        continue;
      }
      if (!arena.contains(
        (x: projectile.x, y: projectile.y),
        projectile.radius,
      )) {
        removals.add(i);
        continue;
      }
      for (final defender in _players.values) {
        if (!defender.alive) continue;
        if (defender.team == projectile.ownerTeam) continue;
        if (!_overlaps(defender, projectile)) continue;
        defender.takeDamage(projectile.damage.toInt());
        removals.add(i);
        _addEffect(
          GameEffect(
            type: defender.alive
                ? GameEffectType.hitSpark
                : GameEffectType.death,
            x: projectile.x,
            y: projectile.y,
            vx: projectile.vx,
            vy: projectile.vy,
            color: _teamColorFx(defender.team),
            life: defender.alive ? 0.4 : 0.9,
          ),
        );
        if (defender.alive) {
          _addEffect(
            GameEffect(
              type: GameEffectType.shockwave,
              x: defender.x,
              y: defender.y,
              color: _teamColorFx(defender.team),
              life: 0.5,
            ),
          );
        } else {
          _addEffect(
            GameEffect(
              type: GameEffectType.shockwave,
              x: defender.x,
              y: defender.y,
              color: const Color(0xFFFFFFFF),
              life: 0.9,
            ),
          );
        }
        onPlayerHit?.call(defender);
        if (onPlayerDefeated != null && !defender.alive) {
          onPlayerDefeated!(defender);
        }
        break;
      }
    }
    _removeAtIndices(removals);
  }

  void _cullProjectiles() {
    _projectiles.removeWhere((p) => p.isExpired || p.life <= 0);
  }

  bool _overlaps(PlayerEntity defender, ProjectileEntity projectile) {
    final half = defender.hitboxSize / 2;
    final projHalf = projectile.radius;
    return (defender.x - half < projectile.x + projHalf &&
            defender.x + half > projectile.x - projHalf) &&
        (defender.y - half < projectile.y + projHalf &&
            defender.y + half > projectile.y - projHalf);
  }

  void _removeAtIndices(List<int> indices) {
    if (indices.isEmpty) return;
    final keep = <ProjectileEntity>[];
    for (var i = 0; i < _projectiles.length; i++) {
      if (!indices.contains(i)) keep.add(_projectiles[i]);
    }
    _projectiles
      ..clear()
      ..addAll(keep);
  }

  void _advanceEffects(double dt) {
    _effects.removeWhere((e) {
      e.age += dt;
      return e.isExpired;
    });
  }

  void _addEffect(GameEffect effect) {
    _effects.add(effect);
  }

  void _checkWin() {
    if (_isMatchOver) return;
    if (aliveRedCount == 0) {
      _winnerTeam = Team.blue;
      _isMatchOver = true;
      onMatchEnded?.call(_winnerTeam);
    } else if (aliveBlueCount == 0) {
      _winnerTeam = Team.red;
      _isMatchOver = true;
      onMatchEnded?.call(_winnerTeam);
    }
  }

  void broadcastPlayerStates() {
    adapter.broadcastPlayers(
      _players.values.map(_toPlayerSnapshot).toList(growable: false),
    );
  }

  void broadcastProjectileStates() {
    adapter.broadcastProjectiles(
      _projectiles.map(_toProjectileSnapshot).toList(growable: false),
    );
  }

  PlayerSnapshot _toPlayerSnapshot(PlayerEntity player) {
    return PlayerSnapshot(
      playerId: player.id,
      playerName: player.name,
      team: player.team,
      x: player.x,
      y: player.y,
      facingX: player.facingX,
      facingY: player.facingY,
      hp: player.hp,
      alive: player.alive,
    );
  }

  ProjectileSnapshot _toProjectileSnapshot(ProjectileEntity projectile) {
    return ProjectileSnapshot(
      projectileId: projectile.id,
      ownerTeam: projectile.ownerTeam,
      x: projectile.x,
      y: projectile.y,
      vx: projectile.vx,
      vy: projectile.vy,
      life: projectile.life,
    );
  }

  void applyRemotePlayer(PlayerSnapshot snapshot) {
    final player = _players[snapshot.playerId];
    if (player == null) return;
    player
      ..x = snapshot.x
      ..y = snapshot.y
      ..facingX = snapshot.facingX
      ..facingY = snapshot.facingY
      ..hp = snapshot.hp
      ..alive = snapshot.alive;
  }

  void applyRemoteProjectiles(List<ProjectileSnapshot> snapshots) {
    _projectiles.clear();
    for (final snapshot in snapshots) {
      _projectiles.add(
        ProjectileEntity(
          id: snapshot.projectileId,
          ownerId: '',
          ownerTeam: snapshot.ownerTeam,
          x: snapshot.x,
          y: snapshot.y,
          vx: snapshot.vx,
          vy: snapshot.vy,
          radius: arena.projectileRadius,
          damage: arena.projectileDamage,
          life: snapshot.life,
          maxLife: arena.projectileLife,
        ),
      );
    }
  }

  Color _teamColorFx(Team team) => team == Team.red ? AppColors.p2 : AppColors.p1;
}