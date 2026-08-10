import '../../../data/models/game_phase.dart';
import '../../../data/models/team.dart';
import '../domain/match_outcome.dart';
import '../domain/match_player.dart';
import '../domain/match_projectile.dart';

/// A single player's authoritative state inside a broadcast game snapshot.
class GamePlayerSnapshot {
  const GamePlayerSnapshot({
    required this.id,
    required this.name,
    required this.team,
    required this.x,
    required this.y,
    required this.facingX,
    required this.facingY,
    required this.hp,
    required this.maxHp,
    required this.alive,
    required this.radius,
    required this.hitboxSize,
    required this.damageMultiplier,
  });

  final String id;
  final String name;
  final Team team;
  final double x;
  final double y;
  final double facingX;
  final double facingY;
  final int hp;
  final int maxHp;
  final bool alive;
  final double radius;
  final double hitboxSize;
  final double damageMultiplier;

  factory GamePlayerSnapshot.fromMatch(MatchPlayer player) {
    return GamePlayerSnapshot(
      id: player.id,
      name: player.name,
      team: player.team,
      x: player.x,
      y: player.y,
      facingX: player.facingX,
      facingY: player.facingY,
      hp: player.hp,
      maxHp: player.maxHp,
      alive: player.alive,
      radius: player.radius,
      hitboxSize: player.hitboxSize,
      damageMultiplier: player.damageMultiplier,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'team': team.key,
        'x': x,
        'y': y,
        'facingX': facingX,
        'facingY': facingY,
        'hp': hp,
        'maxHp': maxHp,
        'alive': alive,
        'radius': radius,
        'hitboxSize': hitboxSize,
        'damageMultiplier': damageMultiplier,
      };

  factory GamePlayerSnapshot.fromMap(Map<String, dynamic> json) {
    return GamePlayerSnapshot(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      team: Team.fromTag(json['team'] as String?),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      facingX: (json['facingX'] as num?)?.toDouble() ?? 1,
      facingY: (json['facingY'] as num?)?.toDouble() ?? 0,
      hp: (json['hp'] as num?)?.toInt() ?? 100,
      maxHp: (json['maxHp'] as num?)?.toInt() ?? 100,
      alive: json['alive'] as bool? ?? true,
      radius: (json['radius'] as num?)?.toDouble() ?? 16,
      hitboxSize: (json['hitboxSize'] as num?)?.toDouble() ?? 34,
      damageMultiplier: (json['damageMultiplier'] as num?)?.toDouble() ?? 1,
    );
  }

  MatchPlayer toMatch({required bool isLocal}) {
    return MatchPlayer(
      id: id,
      name: name,
      team: team,
      x: x,
      y: y,
      facingX: facingX,
      facingY: facingY,
      hp: hp,
      maxHp: maxHp,
      alive: alive,
      isLocal: isLocal,
      radius: radius,
      hitboxSize: hitboxSize,
      damageMultiplier: damageMultiplier,
    );
  }
}

/// A single projectile's live state inside a broadcast game snapshot.
class GameProjectileSnapshot {
  const GameProjectileSnapshot({
    required this.id,
    required this.ownerTeam,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.damage,
  });

  final String id;
  final Team ownerTeam;
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double life;
  final double damage;

  factory GameProjectileSnapshot.fromMatch(MatchProjectile projectile) {
    return GameProjectileSnapshot(
      id: projectile.id,
      ownerTeam: projectile.ownerTeam,
      x: projectile.x,
      y: projectile.y,
      vx: projectile.vx,
      vy: projectile.vy,
      life: projectile.life,
      damage: projectile.damage,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerTeam': ownerTeam.key,
        'x': x,
        'y': y,
        'vx': vx,
        'vy': vy,
        'life': life,
        'damage': damage,
      };

  factory GameProjectileSnapshot.fromMap(Map<String, dynamic> json) {
    return GameProjectileSnapshot(
      id: json['id'] as String,
      ownerTeam: Team.fromTag(json['ownerTeam'] as String?),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      vx: (json['vx'] as num?)?.toDouble() ?? 0,
      vy: (json['vy'] as num?)?.toDouble() ?? 0,
      life: (json['life'] as num?)?.toDouble() ?? 0,
      damage: (json['damage'] as num?)?.toDouble() ?? 25,
    );
  }

  MatchProjectile toMatch() {
    return MatchProjectile(
      id: id,
      ownerTeam: ownerTeam,
      x: x,
      y: y,
      vx: vx,
      vy: vy,
      life: life,
      damage: damage,
    );
  }
}

/// The complete authoritative state of a match, serialized for the network.
class GameSnapshot {
  const GameSnapshot({
    required this.phase,
    required this.remainingSeconds,
    required this.elapsedMs,
    required this.matchDurationMs,
    required this.redScore,
    required this.blueScore,
    required this.isPaused,
    required this.readyPlayerIds,
    required this.outcome,
    required this.players,
    required this.projectiles,
  });

  final GamePhase phase;
  final int remainingSeconds;
  final int elapsedMs;
  final int matchDurationMs;
  final int redScore;
  final int blueScore;
  final bool isPaused;
  final List<String> readyPlayerIds;
  final MatchOutcome? outcome;
  final List<GamePlayerSnapshot> players;
  final List<GameProjectileSnapshot> projectiles;

  Map<String, dynamic> toMap() => {
        'phase': phase.key,
        'remainingSeconds': remainingSeconds,
        'elapsedMs': elapsedMs,
        'matchDurationMs': matchDurationMs,
        'redScore': redScore,
        'blueScore': blueScore,
        'isPaused': isPaused,
        'readyPlayerIds': readyPlayerIds,
        'outcome': outcome?.name,
        'players': [for (final p in players) p.toMap()],
        'projectiles': [for (final p in projectiles) p.toMap()],
      };

  factory GameSnapshot.fromMap(Map<String, dynamic> json) {
    String? outcomeName = json['outcome'] as String?;
    MatchOutcome? outcome;
    for (final o in MatchOutcome.values) {
      if (o.name == outcomeName) outcome = o;
    }
    return GameSnapshot(
      phase: GamePhase.fromKey(json['phase'] as String? ?? ''),
      remainingSeconds: (json['remainingSeconds'] as num?)?.toInt() ?? 0,
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      matchDurationMs: (json['matchDurationMs'] as num?)?.toInt() ?? 90000,
      redScore: (json['redScore'] as num?)?.toInt() ?? 0,
      blueScore: (json['blueScore'] as num?)?.toInt() ?? 0,
      isPaused: json['isPaused'] as bool? ?? false,
      readyPlayerIds: [
        for (final id in (json['readyPlayerIds'] as List<dynamic>? ?? const []))
          id as String,
      ],
      outcome: outcome,
      players: [
        for (final raw in (json['players'] as List<dynamic>? ?? const []))
          GamePlayerSnapshot.fromMap(raw as Map<String, dynamic>),
      ],
      projectiles: [
        for (final raw in (json['projectiles'] as List<dynamic>? ?? const []))
          GameProjectileSnapshot.fromMap(raw as Map<String, dynamic>),
      ],
    );
  }
}