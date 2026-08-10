import '../../../data/models/team.dart';

class ProjectileEntity {
  ProjectileEntity({
    required this.id,
    required this.ownerId,
    required this.ownerTeam,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.radius = 5,
    this.damage = 25,
    this.life = 1.6,
    this.maxLife = 1.6,
  });

  final String id;
  final String ownerId;
  final Team ownerTeam;
  double x;
  double y;
  final double vx;
  final double vy;
  final double radius;
  final double damage;
  double life;
  final double maxLife;

  bool get isExpired => life <= 0;

  void step(double dt) {
    x += vx * dt;
    y += vy * dt;
    life -= dt;
  }
}