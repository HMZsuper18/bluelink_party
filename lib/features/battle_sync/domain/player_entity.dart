import 'dart:math';

import '../../../data/models/team.dart';

class PlayerEntity {
  PlayerEntity({
    required this.id,
    required this.name,
    required this.team,
    required this.x,
    required this.y,
    this.facingX = 0,
    this.facingY = 1,
    this.vx = 0,
    this.vy = 0,
    this.hp = 100,
    this.maxHp = 100,
    this.isLocal = false,
    this.alive = true,
    this.radius = 16,
    this.hitboxSize = 30,
  });

  final String id;
  final String name;
  final Team team;
  double x;
  double y;
  double vx;
  double vy;
  double facingX;
  double facingY;
  int hp;
  final int maxHp;
  final bool isLocal;
  bool alive;
  final double radius;
  final double hitboxSize;

  bool get isDefeated => hp <= 0;

  void takeDamage(int amount) {
    hp = max(0, hp - amount);
    if (hp <= 0) alive = false;
  }

  double get centerX => x;
  double get centerY => y;

  PlayerEntity copyWith({
    double? x,
    double? y,
    double? facingX,
    double? facingY,
    int? hp,
    bool? alive,
  }) {
    return PlayerEntity(
      id: id,
      name: name,
      team: team,
      x: x ?? this.x,
      y: y ?? this.y,
      facingX: facingX ?? this.facingX,
      facingY: facingY ?? this.facingY,
      vx: vx,
      vy: vy,
      hp: hp ?? this.hp,
      maxHp: maxHp,
      isLocal: isLocal,
      alive: alive ?? this.alive,
      radius: radius,
      hitboxSize: hitboxSize,
    );
  }
}
