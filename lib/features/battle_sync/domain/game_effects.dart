import 'dart:ui';

enum GameEffectType { hitSpark, death, muzzle, shockwave }

class GameEffect {
  GameEffect({
    required this.type,
    required this.x,
    required this.y,
    required this.color,
    this.vx = 0,
    this.vy = 0,
    this.life = 0.4,
  });

  final GameEffectType type;
  final double x;
  final double y;
  final double vx;
  final double vy;
  final Color color;
  final double life;

  double age = 0;

  double get progress => (age / life).clamp(0.0, 1.0);
  bool get isExpired => age >= life;
}
