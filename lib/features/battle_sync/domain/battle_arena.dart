import 'dart:math';

import '../../../data/models/team.dart';

class BattleArena {
  const BattleArena({
    this.width = 1000,
    this.height = 600,
    this.wallThickness = 10,
    this.playerSpeed = 240,
    this.playerRadius = 16,
    this.playerHitbox = 30,
    this.projectileSpeed = 680,
    this.projectileRadius = 5,
    this.projectileDamage = 25,
    this.projectileLife = 1.6,
    this.fireCooldown = 0.38,
  });

  final double width;
  final double height;
  final double wallThickness;
  final double playerSpeed;
  final double playerRadius;
  final double playerHitbox;
  final double projectileSpeed;
  final double projectileRadius;
  final double projectileDamage;
  final double projectileLife;
  final double fireCooldown;

  double get midX => width / 2;
  double get midY => height / 2;

  ({double x, double y, double facingX, double facingY}) spawnFor(
    Team team,
    int seat,
  ) {
    final isRed = team == Team.red;
    final col = (seat % 2).toDouble();
    final x = isRed ? width * (0.14 + 0.06 * col) : width * (0.86 - 0.06 * col);
    final y = height * (col == 0 ? 0.35 : 0.65);
    return (
      x: x,
      y: y,
      facingX: isRed ? 1 : -1,
      facingY: 0,
    );
  }

  ({double x, double y}) clampInside(
    double x,
    double y,
    double radius,
  ) {
    final minX = wallThickness + radius;
    final minY = wallThickness + radius;
    final maxX = width - wallThickness - radius;
    final maxY = height - wallThickness - radius;
    return (
      x: x.clamp(minX, maxX),
      y: y.clamp(minY, maxY),
    );
  }

  bool contains(({double x, double y}) point, double radius) {
    return point.x - radius >= wallThickness &&
        point.x + radius <= width - wallThickness &&
        point.y - radius >= wallThickness &&
        point.y + radius <= height - wallThickness;
  }

  double minScreenSide({required double maxWidth, required double maxHeight}) {
    return min(maxWidth / width, maxHeight / height);
  }
}