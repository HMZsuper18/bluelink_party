import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/team.dart';
import '../domain/game_effects.dart';
import '../domain/player_entity.dart';
import '../game/battle_sync_controller.dart';

class ArenaBackdropPainter extends CustomPainter {
  const ArenaBackdropPainter({required this.scale});

  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF141621), Color(0xFF0D0E15)],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    final accent = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [
          AppColors.accent.withValues(alpha: 0.07),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, accent);

    final step = 90 * scale;
    final grid = Paint()
      ..color = AppColors.border.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var x = size.width / 2 % step; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = size.height / 2 % step; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.15,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withValues(alpha: 0.28),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant ArenaBackdropPainter oldDelegate) =>
      oldDelegate.scale != scale;
}

class ArenaPainter extends CustomPainter {
  ArenaPainter({
    required this.controller,
    required this.scale,
  });

  final BattleSyncController controller;
  final double scale;

  Color _teamColor(Team team) {
    return team == Team.red ? AppColors.p2 : AppColors.p1;
  }

  double get _time => controller.elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    final bounds = Rect.fromLTWH(
      0,
      0,
      controller.arena.width,
      controller.arena.height,
    );

    _paintArenaField(canvas, bounds);
    _paintSpawnZones(canvas);
    _paintEffects(canvas);
    _paintProjectiles(canvas);

    for (final player in controller.players.values) {
      _paintPlayer(canvas, player);
    }

    canvas.restore();
  }

  void _paintArenaField(Canvas canvas, Rect bounds) {
    final time = _time;
    final pulse = 0.5 + 0.5 * math.sin(time * 2.2);
    final wallThickness = controller.arena.wallThickness;

    final redSide = Rect.fromLTRB(
      bounds.left,
      bounds.top,
      controller.arena.midX,
      bounds.bottom,
    );
    final blueSide = Rect.fromLTRB(
      controller.arena.midX,
      bounds.top,
      bounds.right,
      bounds.bottom,
    );

    final redGradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          AppColors.p2.withValues(alpha: 0.16 + 0.05 * pulse),
          AppColors.p2.withValues(alpha: 0.03),
        ],
      ).createShader(redSide);
    final blueGradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [
          AppColors.p1.withValues(alpha: 0.16 + 0.05 * pulse),
          AppColors.p1.withValues(alpha: 0.03),
        ],
      ).createShader(blueSide);
    canvas.drawRect(redSide, redGradient);
    canvas.drawRect(blueSide, blueGradient);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(wallThickness / 2),
        const Radius.circular(14),
      ),
      Paint()
        ..color = AppColors.surfaceRaised.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );

    final wallOuter = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.accent.withValues(alpha: 0.5 + 0.3 * pulse),
          AppColors.borderStrong.withValues(alpha: 0.4),
        ],
      ).createShader(bounds);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(16)),
      wallOuter..style = PaintingStyle.stroke..strokeWidth = wallThickness,
    );
    final wallInner = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(wallThickness / 2 - 1),
        const Radius.circular(12),
      ),
      wallInner,
    );

    final mid = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.28)
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(controller.arena.midX, bounds.top),
      Offset(controller.arena.midX, bounds.bottom),
      mid,
    );

    _paintCenterEmblem(canvas, bounds.center);
  }

  void _paintCenterEmblem(Canvas canvas, Offset center) {
    final time = _time;
    final pulse = 0.5 + 0.5 * math.sin(time * 2.6);

    final outer = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.5 + 0.35 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 + 1.5 * pulse;
    canvas.drawCircle(center, 62, outer);

    final ring = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 46, ring);

    final glow = Paint()..color = AppColors.accent.withValues(alpha: 0.10);
    canvas.drawCircle(center, 34 + 8 * pulse, glow);

    final core = Paint()..color = AppColors.accent.withValues(alpha: 0.55);
    canvas.drawCircle(center, 4, core);
  }

  void _paintSpawnZones(Canvas canvas) {
    final time = _time;
    for (final team in Team.all) {
      for (var seat = 0; seat < Team.capacity; seat++) {
        final spawn = controller.arena.spawnFor(team, seat);
        final color = _teamColor(team);
        final position = Offset(spawn.x, spawn.y);
        final localPulse = 0.6 + 0.4 * math.sin(time * 3 + seat * 1.7);

        final base = Paint()
          ..color = color.withValues(alpha: 0.10 * localPulse)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(position, 30, base);

        final ring = Paint()
          ..color = color.withValues(alpha: 0.20 + 0.15 * localPulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(position, 26, ring);
      }
    }
  }

  void _paintEffects(Canvas canvas) {
    for (final effect in controller.effects) {
      switch (effect.type) {
        case GameEffectType.hitSpark:
          _paintHitSpark(canvas, effect);
        case GameEffectType.muzzle:
          _paintMuzzle(canvas, effect);
        case GameEffectType.death:
          _paintDeath(canvas, effect);
        case GameEffectType.shockwave:
          _paintShockwave(canvas, effect);
      }
    }
  }

  void _paintShockwave(Canvas canvas, GameEffect effect) {
    final position = Offset(effect.x, effect.y);
    final fade = 1 - effect.progress;
    final radius = 10 + effect.progress * 70;

    final ring = Paint()
      ..color = effect.color.withValues(alpha: 0.55 * fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 + (1 - effect.progress) * 4
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(position, radius, ring);

    final halo = Paint()
      ..color = effect.color.withValues(alpha: 0.18 * fade)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(position, radius * 0.7, halo);
  }

  void _paintHitSpark(Canvas canvas, GameEffect effect) {
    final position = Offset(effect.x, effect.y);
    final fade = 1 - effect.progress;
    final radius = 4 + effect.progress * 26;

    final ring = Paint()
      ..color = effect.color.withValues(alpha: 0.7 * fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 + (1 - effect.progress) * 2;
    canvas.drawCircle(position, radius, ring);

    final fill = Paint()
      ..color = Colors.white.withValues(alpha: 0.7 * fade);
    canvas.drawCircle(position, 3 + (1 - effect.progress) * 4, fill);
  }

  void _paintMuzzle(Canvas canvas, GameEffect effect) {
    final position = Offset(effect.x, effect.y);
    final fade = 1 - effect.progress;
    final length = 16 * (1 - effect.progress);
    final spread = 0.35;

    final flash = Paint()
      ..color = effect.color.withValues(alpha: 0.9 * fade)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      position,
      Offset(
        position.dx + effect.vx * length,
        position.dy + effect.vy * length,
      ),
      flash,
    );
    final side = Paint()
      ..color = Colors.white.withValues(alpha: 0.8 * fade)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      position,
      Offset(
        position.dx + effect.vx * length - effect.vy * spread * length,
        position.dy + effect.vy * length + effect.vx * spread * length,
      ),
      side,
    );
    canvas.drawLine(
      position,
      Offset(
        position.dx + effect.vx * length + effect.vy * spread * length,
        position.dy + effect.vy * length - effect.vx * spread * length,
      ),
      side,
    );
  }

  void _paintDeath(Canvas canvas, GameEffect effect) {
    final position = Offset(effect.x, effect.y);
    final fade = 1 - effect.progress;
    final radius = 6 + effect.progress * 46;

    final ring = Paint()
      ..color = effect.color.withValues(alpha: 0.8 * fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 + (1 - effect.progress) * 3;
    canvas.drawCircle(position, radius, ring);

    final fill = Paint()
      ..color = effect.color.withValues(alpha: 0.30 * fade);
    canvas.drawCircle(position, radius * 0.6, fill);
  }

  void _paintProjectiles(Canvas canvas) {
    for (final projectile in controller.projectiles) {
      final color = _teamColor(projectile.ownerTeam);
      final position = Offset(projectile.x, projectile.y);
      final speed = math.sqrt(projectile.vx * projectile.vx + projectile.vy * projectile.vy);
      final trail = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = projectile.radius * 1.8
        ..strokeCap = StrokeCap.round;

      if (speed > 0.001) {
        final len = 18.0;
        final nx = projectile.vx / speed;
        final ny = projectile.vy / speed;
        canvas.drawLine(
          Offset(position.dx - nx * len, position.dy - ny * len),
          position,
          trail,
        );
      }

      final halo = Paint()
        ..color = color.withValues(alpha: 0.35 + 0.15 * math.sin(_time * 20));
      canvas.drawCircle(position, projectile.radius * 3.2, halo);

      final core = Paint()..color = Colors.white;
      canvas.drawCircle(position, projectile.radius * 0.7, core);
      final tint = Paint()..color = color;
      canvas.drawCircle(position, projectile.radius, tint);
    }
  }

  void _paintPlayer(Canvas canvas, PlayerEntity player) {
    final color = _teamColor(player.team);
    final position = Offset(player.x, player.y);

    if (player.alive) {
      final glow = Paint()..color = color.withValues(alpha: 0.30);
      canvas.drawCircle(position, player.radius * 1.9, glow);
    }

    final body = Paint()
      ..color = player.alive ? color : color.withValues(alpha: 0.22);
    canvas.drawCircle(position, player.radius, body);

    final rim = Paint()
      ..color = Colors.white.withValues(alpha: player.alive ? 0.85 : 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(position, player.radius, rim);

    if (player.alive) {
      _paintFacingChevron(canvas, player, position, color);

      final inner = Paint()..color = Colors.white.withValues(alpha: 0.35);
      canvas.drawCircle(position, player.radius * 0.45, inner);
    }

    _paintHealthBar(canvas, player, position);
    _paintName(canvas, player, position);
  }

  void _paintFacingChevron(
    Canvas canvas,
    PlayerEntity player,
    Offset position,
    Color color,
  ) {
    final dirX = player.facingX;
    final dirY = player.facingY;
    final mag = math.sqrt(dirX * dirX + dirY * dirY);
    if (mag < 0.001) return;
    final nx = dirX / mag;
    final ny = dirY / mag;
    final px = -ny;
    final py = nx;

    final tip = Offset(
      position.dx + nx * player.radius * 1.55,
      position.dy + ny * player.radius * 1.55,
    );
    final base = Offset(
      position.dx + nx * player.radius * 0.55,
      position.dy + ny * player.radius * 0.55,
    );
    final wing = player.radius * 0.6;

    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        base.dx + px * wing,
        base.dy + py * wing,
      )
      ..lineTo(
        base.dx - px * wing,
        base.dy - py * wing,
      )
      ..close();

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrow, paint);

    final edge = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(arrow, edge);
  }

  void _paintHealthBar(Canvas canvas, PlayerEntity player, Offset position) {
    final barWidth = player.hitboxSize;
    final barHeight = 5.0;
    final top = position.dy - player.radius - 14;
    final left = position.dx - barWidth / 2;
    final ratio = (player.hp / player.maxHp).clamp(0.0, 1.0).toDouble();

    final back = Paint()..color = AppColors.inactiveSlotDarker;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        const Radius.circular(3),
      ),
      back,
    );

    final fillColor = Color.lerp(
      AppColors.danger,
      _teamColor(player.team),
      ratio,
    )!;
    final fill = Paint()..color = fillColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth * ratio, barHeight),
        const Radius.circular(3),
      ),
      fill,
    );
  }

  void _paintName(Canvas canvas, PlayerEntity player, Offset position) {
    final displayName = player.isLocal ? '${player.name} (You)' : player.name;
    final textPainter = TextPainter(
      text: TextSpan(
        text: displayName,
        style: TextStyle(
          color: player.alive
              ? AppColors.textPrimary
              : AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy + player.radius + 6,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant ArenaPainter oldDelegate) => true;
}
