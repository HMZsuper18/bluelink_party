import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/matrix_grid.dart';
import '../domain/matrix_snapshots.dart';
import '../game/matrix_interpolation.dart';
import '../game/matrix_viewport.dart';
import 'matrix_arena_screen.dart';

class MatrixArenaPainter extends CustomPainter {
  const MatrixArenaPainter({
    required this.viewport,
    required this.frame,
    required this.matrix,
    required this.phase,
    required this.countdown,
    this.debugGuides = false,
    this.effects = const [],
  });

  final MatrixViewportCamera viewport;
  final MatrixInterpolationFrame frame;
  final TileMatrix matrix;
  final MatrixMatchPhase phase;
  final double countdown;
  final bool debugGuides;
  final List<MatrixFx> effects;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    canvas.save();
    canvas.clipRect(viewport.playRect);

    _paintTileBorders(canvas);
    _paintProjectiles(canvas);
    _paintPlayers(canvas);
    _paintEffects(canvas);

    canvas.restore();
    _paintBorder(canvas);

    if (debugGuides) {
      _paintDebugGuides(canvas, size);
    }
  }

  void _paintEffects(Canvas canvas) {
    for (final fx in effects) {
      if (fx.elapsed >= fx.life) continue;
      final progress = (fx.elapsed / fx.life).clamp(0.0, 1.0);
      final fade = 1 - progress;
      final center = viewport.worldToScreen(fx.x, fx.y);
      if (!isPotentiallyVisible(center, 80)) continue;

      switch (fx.kind) {
        case MatrixFxKind.muzzle:
          final fade = 1 - progress;
          final dirVec = Offset(fx.vx, fx.vy);
          final len = dirVec.distance;
          final dir = len > 0.001 ? dirVec / len : Offset.zero;
          final flashLen = viewport.worldDeltaToScreen(16) * fade;
          final flash = Paint()
            ..color = fx.color.withValues(alpha: 0.9 * fade)
            ..strokeWidth = 5 * fade
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            center,
            center + dir * flashLen,
            flash,
          );
          final sideDot = Offset(-dir.dy, dir.dx);
          final side = Paint()
            ..color = Colors.white.withValues(alpha: 0.8 * fade)
            ..strokeWidth = 3 * fade
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            center,
            center + dir * flashLen + sideDot * (8 * fade),
            side,
          );
          canvas.drawLine(
            center,
            center + dir * flashLen - sideDot * (8 * fade),
            side,
          );
        case MatrixFxKind.shockwave:
          final fade = 1 - progress;
          final radius = viewport.worldDeltaToScreen(10 + progress * 70);
          final ring = Paint()
            ..color = fx.color.withValues(alpha: 0.55 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 + (1 - progress) * 4
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawCircle(center, radius, ring);
          final halo = Paint()
            ..color = fx.color.withValues(alpha: 0.18 * fade)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14);
          canvas.drawCircle(center, radius * 0.7, halo);
        case MatrixFxKind.hit:
          final radius = viewport.worldDeltaToScreen(14) * (0.4 + progress);
          final spark = Paint()
            ..color = const Color(0xFFFCE38A).withValues(alpha: 0.85 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 * fade;
          canvas.drawCircle(center, radius, spark);
          for (var i = 0; i < 8; i++) {
            final angle = i * pi / 4;
            final inner = center + Offset(cos(angle), sin(angle)) * radius * 0.4;
            final outer = center + Offset(cos(angle), sin(angle)) * radius;
            canvas.drawLine(
              inner,
              outer,
              Paint()
                ..color = const Color(0xFFFFE082).withValues(alpha: 0.9 * fade)
                ..strokeWidth = 2.4 * fade + 0.6
                ..strokeCap = StrokeCap.round,
            );
          }
        case MatrixFxKind.death:
          final radius = viewport.worldDeltaToScreen(10 + progress * 34);
          final ring = Paint()
            ..color = Colors.white.withValues(alpha: 0.6 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4 * fade + 1
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8);
          canvas.drawCircle(center, radius, ring);
          final halo = Paint()
            ..color = const Color(0xFFFF5252).withValues(alpha: 0.3 * fade)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18);
          canvas.drawCircle(center, radius * 0.8, halo);
      }
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.background, AppColors.surfaceRaised],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _paintTileBorders(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var col = 0; col <= matrix.columns; col++) {
      final screenX = viewport.worldToScreen(
        col * matrix.tileWidth,
        0,
      ).dx;
      final topY = viewport.worldToScreen(0, 0).dy;
      final bottomY = viewport.worldToScreen(
        0,
        matrix.worldHeight,
      ).dy;
      canvas.drawLine(
        Offset(screenX, topY),
        Offset(screenX, bottomY),
        paint,
      );
    }
    for (var row = 0; row <= matrix.rows; row++) {
      final screenY = viewport.worldToScreen(
        0,
        row * matrix.tileHeight,
      ).dy;
      final leftX = viewport.worldToScreen(0, 0).dx;
      final rightX = viewport.worldToScreen(
        matrix.worldWidth,
        0,
      ).dx;
      canvas.drawLine(
        Offset(leftX, screenY),
        Offset(rightX, screenY),
        paint,
      );
    }
  }

  void _paintProjectiles(Canvas canvas) {
    for (final projectile in frame.projectiles) {
      final screenCenter = viewport.worldToScreen(projectile.x, projectile.y);
      if (!isPotentiallyVisible(screenCenter, viewport.worldDeltaToScreen(20))) {
        continue;
      }
      final radius = viewport.worldDeltaToScreen(6).clamp(3.0, 16.0);
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 2);
      canvas.drawCircle(screenCenter, radius * 2.4, glow);
      final core = Paint()..color = Colors.white;
      canvas.drawCircle(screenCenter, radius, core);
      final speed = sqrt(
        projectile.vx * projectile.vx + projectile.vy * projectile.vy,
      );
      if (speed > 0.01) {
        final trail = Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = radius * 0.8
          ..strokeCap = StrokeCap.round;
        final dirDx = projectile.vx / speed;
        final dirDy = projectile.vy / speed;
        canvas.drawLine(
          screenCenter - Offset(dirDx, dirDy) * radius * 3,
          screenCenter,
          trail,
        );
      }
    }
  }

  void _paintPlayers(Canvas canvas) {
    for (final player in frame.players) {
      if (!player.alive) continue;
      final center = viewport.worldToScreen(player.x, player.y);
      final radius = viewport.worldDeltaToScreen(20).clamp(6.0, 34.0);
      if (!isPotentiallyVisible(center, radius * 2)) continue;
      final color = SlotVisuals.colorOf(player.deviceIndex);

      final halo = Paint()
        ..color = color.withValues(alpha: 0.26)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.9);
      canvas.drawCircle(center, radius * 1.5, halo);

      final body = Paint()..color = color;
      canvas.drawCircle(center, radius, body);

      final rim = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(center, radius, rim);

      final facingX = cos(player.facingYaw);
      final facingY = sin(player.facingYaw);
      final tip = center + Offset(facingX, facingY) * (radius + 7);
      final sideA = center +
          Offset(facingX, facingY) * (radius * 0.45) -
          Offset(-facingY, facingX) * (radius * 0.6);
      final sideB = center +
          Offset(facingX, facingY) * (radius * 0.45) +
          Offset(-facingY, facingX) * (radius * 0.6);
      final chevron = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(sideA.dx, sideA.dy)
        ..lineTo(sideB.dx, sideB.dy)
        ..close();
      canvas.drawPath(
        chevron,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );

      _paintHealthBar(canvas, center, radius, player);
    }
  }

  void _paintHealthBar(
    Canvas canvas,
    Offset center,
    double radius,
    MatrixPlayerSnapshot player,
  ) {
    final width = viewport.worldDeltaToScreen(56).clamp(
          18.0,
          viewport.playRect.width * 0.28,
        );
    final height = viewport.worldDeltaToScreen(7).clamp(3.0, 12.0);
    final barTop = center.dy - radius - height - 8;
    final barRect = Rect.fromLTWH(
      center.dx - width / 2,
      barTop,
      width,
      height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    final ratio = player.hp / player.maxHp;
    if (ratio > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barRect.left, barRect.top, barRect.width * ratio, barRect.height),
          const Radius.circular(3),
        ),
        Paint()..color = SlotVisuals.colorOf(player.deviceIndex),
      );
    }
  }

  void _paintBorder(Canvas canvas) {
    final borderPaint = Paint()
      ..color = Colors.white
          .withValues(alpha: phase == MatrixMatchPhase.playing ? 0.12 : 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = phase == MatrixMatchPhase.playing ? 2 : 4;
    canvas.drawRect(viewport.playRect.deflate(1), borderPaint);

    if (phase != MatrixMatchPhase.playing) {
      final pulse = 0.5 + 0.5 * sin(countdown * 4);
      final guidePaint = Paint()
        ..color = AppColors.accent.withValues(alpha: 0.5 + pulse * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawRect(viewport.playRect.inflate(3), guidePaint);
    }
  }

  bool isPotentiallyVisible(Offset screenPoint, double radius) {
    final rect = viewport.playRect;
    return screenPoint.dx >= rect.left - radius &&
        screenPoint.dx <= rect.right + radius &&
        screenPoint.dy >= rect.top - radius &&
        screenPoint.dy <= rect.bottom + radius;
  }

  void _paintDebugGuides(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(viewport.playRect, paint);
    final center = viewport.playRect.center;
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant MatrixArenaPainter oldDelegate) {
    return true;
  }
}