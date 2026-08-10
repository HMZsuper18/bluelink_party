import 'package:equatable/equatable.dart';

import '../../../data/models/team.dart';

class MatchPlayer extends Equatable {
  const MatchPlayer({
    required this.id,
    required this.team,
    required this.x,
    required this.y,
    this.name = '',
    this.facingX = 0,
    this.facingY = 1,
    this.vx = 0,
    this.vy = 0,
    this.hp = 100,
    this.maxHp = 100,
    this.alive = true,
    this.isLocal = false,
    this.radius = 16,
    this.hitboxSize = 34,
    this.damageMultiplier = 1.0,
  });

  final String id;
  final String name;
  final Team team;
  final double x;
  final double y;
  final double facingX;
  final double facingY;
  final double vx;
  final double vy;
  final int hp;
  final int maxHp;
  final bool alive;
  final bool isLocal;
  final double radius;
  final double hitboxSize;
  final double damageMultiplier;

  double get hpRatio => maxHp == 0 ? 0 : hp / maxHp;

  bool get isDefeated => hp <= 0;

  MatchPlayer copyWith({
    double? x,
    double? y,
    double? facingX,
    double? facingY,
    double? vx,
    double? vy,
    int? hp,
    int? maxHp,
    bool? alive,
    bool? isLocal,
    double? radius,
    double? damageMultiplier,
  }) {
    return MatchPlayer(
      id: id,
      name: name,
      team: team,
      x: x ?? this.x,
      y: y ?? this.y,
      facingX: facingX ?? this.facingX,
      facingY: facingY ?? this.facingY,
      vx: vx ?? this.vx,
      vy: vy ?? this.vy,
      hp: hp ?? this.hp,
      maxHp: maxHp ?? this.maxHp,
      alive: alive ?? this.alive,
      isLocal: isLocal ?? this.isLocal,
      radius: radius ?? this.radius,
      hitboxSize: hitboxSize,
      damageMultiplier: damageMultiplier ?? this.damageMultiplier,
    );
  }

  @override
  List<Object?> get props => [
        id,
        team,
        x,
        y,
        facingX,
        facingY,
        vx,
        vy,
        hp,
        maxHp,
        alive,
        isLocal,
        radius,
        hitboxSize,
        damageMultiplier,
      ];
}
