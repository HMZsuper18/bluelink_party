import 'package:equatable/equatable.dart';

import '../../../data/models/team.dart';

class PlayerInput extends Equatable {
  const PlayerInput({
    this.moveX = 0,
    this.moveY = 0,
    this.firing = false,
    this.sequence = 0,
  });

  final double moveX;
  final double moveY;
  final bool firing;
  final int sequence;

  bool get hasMovement => moveX != 0 || moveY != 0;

  PlayerInput copyWith({
    double? moveX,
    double? moveY,
    bool? firing,
    int? sequence,
  }) {
    return PlayerInput(
      moveX: moveX ?? this.moveX,
      moveY: moveY ?? this.moveY,
      firing: firing ?? this.firing,
      sequence: sequence ?? this.sequence,
    );
  }

  Map<String, dynamic> toJson() => {
        'moveX': moveX,
        'moveY': moveY,
        'firing': firing,
        'seq': sequence,
      };

  factory PlayerInput.fromJson(Map<String, dynamic> json) {
    return PlayerInput(
      moveX: (json['moveX'] as num?)?.toDouble() ?? 0,
      moveY: (json['moveY'] as num?)?.toDouble() ?? 0,
      firing: json['firing'] as bool? ?? false,
      sequence: (json['seq'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [moveX, moveY, firing, sequence];
}

class PlayerSnapshot extends Equatable {
  const PlayerSnapshot({
    required this.playerId,
    required this.playerName,
    required this.team,
    required this.x,
    required this.y,
    required this.facingX,
    required this.facingY,
    required this.hp,
    required this.alive,
  });

  final String playerId;
  final String playerName;
  final Team team;
  final double x;
  final double y;
  final double facingX;
  final double facingY;
  final int hp;
  final bool alive;

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'playerName': playerName,
        'team': team.key,
        'x': x,
        'y': y,
        'facingX': facingX,
        'facingY': facingY,
        'hp': hp,
        'alive': alive,
      };

  factory PlayerSnapshot.fromJson(Map<String, dynamic> json) {
    return PlayerSnapshot(
      playerId: json['playerId'] as String,
      playerName: json['playerName'] as String? ?? '',
      team: Team.fromTag(json['team'] as String?),
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      facingX: (json['facingX'] as num?)?.toDouble() ?? 0,
      facingY: (json['facingY'] as num?)?.toDouble() ?? 0,
      hp: (json['hp'] as num?)?.toInt() ?? 0,
      alive: json['alive'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props =>
      [playerId, playerName, team, x, y, facingX, facingY, hp, alive];
}

class ProjectileSnapshot extends Equatable {
  const ProjectileSnapshot({
    required this.projectileId,
    required this.ownerTeam,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
  });

  final String projectileId;
  final Team ownerTeam;
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double life;

  Map<String, dynamic> toJson() => {
        'projectileId': projectileId,
        'ownerTeam': ownerTeam.key,
        'x': x,
        'y': y,
        'vx': vx,
        'vy': vy,
        'life': life,
      };

  factory ProjectileSnapshot.fromJson(Map<String, dynamic> json) {
    return ProjectileSnapshot(
      projectileId: json['projectileId'] as String,
      ownerTeam: Team.fromTag(json['ownerTeam'] as String?),
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      vx: (json['vx'] as num?)?.toDouble() ?? 0,
      vy: (json['vy'] as num?)?.toDouble() ?? 0,
      life: (json['life'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  List<Object?> get props =>
      [projectileId, ownerTeam, x, y, vx, vy, life];
}