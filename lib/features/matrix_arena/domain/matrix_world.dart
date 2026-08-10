import 'dart:math';

class MatrixWorldConfig {
  const MatrixWorldConfig({
    this.playerSpeed = 240,
    this.playerRadius = 20,
    this.playerHitbox = 34,
    this.projectileSpeed = 680,
    this.projectileRadius = 6,
    this.projectileDamage = 34,
    this.projectileLife = 1.4,
    this.fireCooldown = 0.42,
    this.maxHp = 100,
    this.killsToWin = 5,
    this.respawnDelay = 2.2,
    this.wallPadding = 8,
  });

  final double playerSpeed;
  final double playerRadius;
  final double playerHitbox;
  final double projectileSpeed;
  final double projectileRadius;
  final double projectileDamage;
  final double projectileLife;
  final double fireCooldown;
  final int maxHp;
  final int killsToWin;
  final double respawnDelay;
  final double wallPadding;
}

class MatrixWorldAvatar {
  MatrixWorldAvatar({
    required this.deviceIndex,
    required this.name,
    required this.x,
    required this.y,
    required this.hp,
    required this.maxHp,
  });

  final int deviceIndex;
  final String name;
  double x;
  double y;
  double facingYaw = 0;
  double vx = 0;
  double vy = 0;
  int hp;
  final int maxHp;
  bool alive = true;
  int kills = 0;
  double respawnTimer = 0;
  double fireCooldown = 0;

  /// Host-only marker for AI goalkeeper avatars in failed/unbalanced teams.
  /// Keepers are simulated locally and never receive player input.
  bool isGoalkeeper = false;

  bool get isDefeated => hp <= 0;

  void takeDamage(int amount) {
    if (!alive) return;
    hp -= amount;
    if (hp <= 0) {
      hp = 0;
      alive = false;
    }
  }

  void spawnAt({
    required double nextX,
    required double nextY,
  }) {
    x = nextX;
    y = nextY;
    vx = 0;
    vy = 0;
    hp = maxHp;
    alive = true;
    respawnTimer = 0;
    facingYaw = 0;
  }
}

class MatrixWorldProjectile {
  MatrixWorldProjectile({
    required this.id,
    required this.ownerIndex,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.life = 1.4,
  });

  final int id;
  final int ownerIndex;
  double x;
  double y;
  final double vx;
  final double vy;
  double life;

  bool get isExpired => life <= 0;

  void step(double dt) {
    x += vx * dt;
    y += vy * dt;
    life -= dt;
  }
}

({double fx, double fy}) normalizeDirection(double fx, double fy) {
  final length = sqrt(fx * fx + fy * fy);
  if (length == 0) return (fx: 1, fy: 0);
  return (fx: fx / length, fy: fy / length);
}