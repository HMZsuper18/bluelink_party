import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/team.dart';
import '../bloc/game_state.dart';
import '../domain/match_player.dart';
import '../domain/match_projectile.dart';
import 'screen_scaler.dart';

/// Pure-presentation particle overlay. Watches `GameState` transitions and
/// spawns one-shot effects (muzzle flashes, impact bursts, death explosions)
/// so hits and kills feel physical without touching the authoritative state.
class MatchEffectsOverlay extends StatefulWidget {
  const MatchEffectsOverlay({super.key, required this.state});

  final GameState state;

  @override
  State<MatchEffectsOverlay> createState() => _MatchEffectsOverlayState();
}

class _MatchEffectsOverlayState extends State<MatchEffectsOverlay>
    with SingleTickerProviderStateMixin {
  final List<_Particle> _particles = [];
  Ticker? _ticker;
  double _lastFrame = -1;

  Set<String> _knownProjectileIds = const {};
  Map<String, bool> _knownAlive = const {};

  @override
  void initState() {
    super.initState();
    _seedFrom(widget.state);
    _ticker = createTicker(_onTick)..start();
  }

  void _seedFrom(GameState state) {
    _knownProjectileIds = {for (final pr in state.projectiles) pr.id};
    _knownAlive = {
      for (final p in state.players) p.id: p.alive,
    };
  }

  @override
  void didUpdateWidget(covariant MatchEffectsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _diff(oldWidget.state, widget.state);
  }

  void _diff(GameState prev, GameState next) {
    for (final player in next.players) {
      final wasAlive = _knownAlive[player.id] ?? player.alive;
      if (_knownAlive.containsKey(player.id) && wasAlive && !player.alive) {
        _spawnDeath(player);
      }
      _knownAlive[player.id] = player.alive;
    }

    final prevIds = _knownProjectileIds;
    final nextIds = {for (final pr in next.projectiles) pr.id};
    for (final id in prevIds.difference(nextIds)) {
      final gone = prev.projectiles.where((pr) => pr.id == id);
      if (gone.isNotEmpty) {
        _spawnImpact(gone.first);
      }
    }
    _knownProjectileIds = nextIds;
  }

  void _spawnImpact(MatchProjectile pr) {
    final color = _teamColor(pr.ownerTeam);
    for (var i = 0; i < 7; i++) {
      final a = _rand(-math.pi, math.pi);
      final speed = _rand(30, 130);
      _particles.add(_Particle(
        x: pr.x,
        y: pr.y,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        life: _rand(0.15, 0.35),
        maxLife: 0.35,
        color: i == 0 ? Colors.white : color,
        size: 18,
        kind: _ParticleKind.spark,
      ));
    }
    _particles.add(_Particle.burst(
      x: pr.x,
      y: pr.y,
      size: 18,
      life: 0.28,
      color: color.withValues(alpha: 0.85),
    ));
  }

  void _spawnDeath(MatchPlayer player) {
    final color = _teamColor(player.team);
    for (var i = 0; i < 18; i++) {
      final a = i * math.pi / 9 + _rand(-0.5, 0.5);
      final speed = _rand(40, 180);
      _particles.add(_Particle(
        x: player.x,
        y: player.y,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        life: _rand(0.3, 0.7),
        maxLife: 0.7,
        color: i.isEven ? color : Colors.white.withValues(alpha: 0.9),
        size: 20,
        kind: _ParticleKind.spark,
      ));
    }
    _particles.add(_Particle(
      x: player.x,
      y: player.y,
      vx: 0,
      vy: 0,
      life: 0.5,
      maxLife: 0.5,
      color: color.withValues(alpha: 0.8),
      size: player.radius * 2.2,
      kind: _ParticleKind.burst,
    ));
    _particles.add(_Particle(
      x: player.x,
      y: player.y,
      vx: 0,
      vy: 0,
      life: 0.35,
      maxLife: 0.35,
      color: color.withValues(alpha: 0.8),
      size: player.radius * 0.5,
      kind: _ParticleKind.ring,
    ));
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = _lastFrame < 0 ? 0.016 : (now - _lastFrame);
    _lastFrame = now;
    if (dt <= 0 || dt > 0.2) return;

    var alive = false;
    for (var i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        _particles.removeAt(i);
        continue;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      final drag = math.pow(0.9, dt * 60).toDouble();
      p.vx *= drag;
      p.vy *= drag;
      alive = true;
    }
    if (alive) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ParticlePainter(
          particles: List<_Particle>.from(_particles),
          scale: ScaledViewport.scaleOf(context),
        ),
        size: Size.infinite,
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.maxLife,
    required this.color,
    required this.size,
    required this.kind,
  });

  factory _Particle.burst({
    required double x,
    required double y,
    required double size,
    required Color color,
    required double life,
  }) {
    return _Particle(
      x: x,
      y: y,
      vx: 0,
      vy: 0,
      life: life,
      maxLife: life,
      color: color,
      size: size,
      kind: _ParticleKind.burst,
    );
  }

  double x;
  double y;
  double vx;
  double vy;
  double life;
  double maxLife;
  Color color;
  double size;
  _ParticleKind kind;
}

enum _ParticleKind { spark, burst, ring }

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.particles, required this.scale});

  final List<_Particle> particles;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    for (final p in particles) {
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      switch (p.kind) {
        case _ParticleKind.spark:
          final spark = Paint()
            ..color = p.color.withValues(alpha: t)
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round;
          final tail = Offset(p.vx * 0.12, p.vy * 0.12);
          canvas.drawLine(
            Offset(p.x, p.y),
            Offset(p.x - tail.dx, p.y - tail.dy),
            spark,
          );
        case _ParticleKind.burst:
          canvas.drawCircle(
            Offset(p.x, p.y),
            p.size * (1 - t * 0.6),
            Paint()
              ..color = p.color.withValues(alpha: t)
              ..style = PaintingStyle.fill,
          );
        case _ParticleKind.ring:
          canvas.drawCircle(
            Offset(p.x, p.y),
            p.size + 36 * (1 - t),
            Paint()
              ..color = p.color.withValues(alpha: t)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

Color _teamColor(Team team) => team == Team.red ? AppColors.p2 : AppColors.p1;

double _rand(double min, double max) =>
    min + math.Random().nextDouble() * (max - min);