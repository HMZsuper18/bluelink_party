import 'package:equatable/equatable.dart';

import '../../../data/models/team.dart';

class MatchProjectile extends Equatable {
  const MatchProjectile({
    required this.id,
    required this.ownerTeam,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.life = 1.6,
    this.damage = 25,
  });

  final String id;
  final Team ownerTeam;
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double life;
  final double damage;

  bool get isExpired => life <= 0;

  MatchProjectile copyWith({
    double? x,
    double? y,
    double? life,
  }) {
    return MatchProjectile(
      id: id,
      ownerTeam: ownerTeam,
      x: x ?? this.x,
      y: y ?? this.y,
      vx: vx,
      vy: vy,
      life: life ?? this.life,
      damage: damage,
    );
  }

  @override
  List<Object?> get props => [id, ownerTeam, x, y, vx, vy, life, damage];
}
