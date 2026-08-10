import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/team.dart';
import '../../matrix_arena/game/matrix_viewport.dart';
import '../game/futbol_interpolation.dart';
import '../game/futbol_match_controller.dart';
import 'futbol_player_sprite.dart';

enum FutbolFxKind { kick, bounce, goal }

class FutbolFx {
  FutbolFx.kick({required this.x, required this.y})
      : kind = FutbolFxKind.kick,
        color = Colors.white,
        life = 0.3;

  FutbolFx.bounce({required this.x, required this.y})
      : kind = FutbolFxKind.bounce,
        color = Colors.white70,
        life = 0.25;

  FutbolFx.goal({required this.x, required this.y, required this.color})
      : kind = FutbolFxKind.goal,
        life = 1.6;

  final FutbolFxKind kind;
  final double x;
  final double y;
  final Color color;
  final double life;
  double elapsed = 0;
}

class FutbolArenaPainter extends CustomPainter {
  FutbolArenaPainter({
    required this.controller,
    required this.screenSize,
    required this.frame,
    this.effects = const [],
    MatrixViewportCamera? viewport,
  }) : viewport = viewport ?? controller.camera(screenSize);

  final FutbolMatchController controller;
  final Size screenSize;
  final FutbolRenderFrame frame;
  final List<FutbolFx> effects;
  final MatrixViewportCamera viewport;

  @override
  void paint(Canvas canvas, Size size) {
    _paintPitchBase(canvas);
    canvas.save();
    canvas.clipRect(viewport.playRect);
    _paintStripes(canvas);
    _paintFieldLines(canvas);
    _paintGoals(canvas);
    _paintEffects(canvas);
    _paintPlayers(canvas);
    _paintBall(canvas);
    canvas.restore();
    if (controller.phase != FutbolMatchPhase.calibrating) {
      _paintScoreboard(canvas, size);
    }
  }

  void _paintPitchBase(Canvas canvas) {
    canvas.drawRect(
      Offset.zero & screenSize,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [futbolPitchTop, futbolPitchBottom],
        ).createShader(Offset.zero & screenSize),
    );
  }

  void _paintStripes(Canvas canvas) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.045);
    final tile = controller.localTile;
    final stripeWidth = controller.matrix.tileWidth / 4;
    final worldLeft = tile.left;
    final worldRight = tile.right;
    for (var col = 0; col < 4; col += 2) {
      final stripeX = worldLeft + col * stripeWidth;
      if (stripeX >= worldRight) break;
      final screenX = viewport.worldToScreen(stripeX, 0).dx;
      final screenStripe = viewport.worldDeltaToScreen(stripeWidth);
      canvas.drawRect(
        Rect.fromLTWH(
          screenX,
          viewport.playRect.top,
          screenStripe,
          viewport.playRect.height,
        ),
        paint,
      );
    }
  }

  void _paintFieldLines(Canvas canvas) {
    final pitch = controller.pitch;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawLine(
      viewport.worldToScreen(pitch.centerX, 0),
      viewport.worldToScreen(pitch.centerX, pitch.worldHeight),
      paint,
    );
    canvas.drawCircle(
      viewport.worldToScreen(pitch.centerX, pitch.centerY),
      viewport.worldDeltaToScreen(90),
      paint,
    );
    canvas.drawCircle(
      viewport.worldToScreen(pitch.centerX, pitch.centerY),
      viewport.worldDeltaToScreen(5),
      paint,
    );

    _paintWorldRect(canvas, pitch.leftPenaltyBox, paint);
    _paintWorldRect(canvas, pitch.rightPenaltyBox, paint);
  }

  void _paintWorldRect(Canvas canvas, Rect world, Paint paint) {
    final topLeft = viewport.worldToScreen(world.left, world.top);
    final bottomRight = viewport.worldToScreen(world.right, world.bottom);
    canvas.drawRect(Rect.fromPoints(topLeft, bottomRight), paint);
  }

  void _paintGoals(Canvas canvas) {
    final pitch = controller.pitch;
    final postRadius = viewport.worldDeltaToScreen(controller.rules.postRadius);

    final redNet = Paint()
      ..color = AppColors.p1.withValues(alpha: 0.5);
    final blueNet = Paint()
      ..color = AppColors.p4.withValues(alpha: 0.5);

    final leftTop = viewport.worldToScreen(
      -pitch.goalInset,
      pitch.leftGoalTop,
    );
    final leftBottom = viewport.worldToScreen(
      0,
      pitch.leftGoalBottom,
    );
    final rightTop = viewport.worldToScreen(
      pitch.worldWidth,
      pitch.rightGoalTop,
    );
    final rightBottom = viewport.worldToScreen(
      pitch.worldWidth + pitch.goalInset,
      pitch.rightGoalBottom,
    );

    // Netting panels.
    canvas.drawRect(Rect.fromPoints(leftTop, leftBottom), redNet);
    canvas.drawRect(Rect.fromPoints(rightTop, rightBottom), blueNet);

    final netLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1;

    // Diagonal net mesh.
    final leftRect = Rect.fromPoints(leftTop, leftBottom);
    final rightRect = Rect.fromPoints(rightTop, rightBottom);
    final meshStep = viewport.worldDeltaToScreen(26);
    for (var k = -leftRect.height; k < leftRect.width + leftRect.height;
        k += meshStep) {
      canvas.drawLine(
        Offset(leftRect.right - k, leftRect.top),
        Offset(leftRect.right, leftRect.top + k),
        netLine,
      );
    }
    for (var k = -rightRect.width; k < rightRect.width + rightRect.height;
      k += meshStep) {
      canvas.drawLine(
        Offset(rightRect.left + k, rightRect.top),
        Offset(rightRect.left, rightRect.bottom - k),
        netLine,
      );
    }

    // Crossbars connecting the posts.
    final crossbar = Paint()
      ..color = const Color(0xFFE8ECF4)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = postRadius * 1.7;
    canvas.drawLine(leftTop, leftBottom, crossbar);
    canvas.drawLine(rightTop, rightBottom, crossbar);

    for (final post in [
      pitch.leftPostTop,
      pitch.leftPostBottom,
      pitch.rightPostTop,
      pitch.rightPostBottom,
    ]) {
      final postCenter = viewport.worldToScreen(post.dx, post.dy);
      canvas.drawCircle(
        postCenter,
        postRadius * 1.4,
        Paint()..color = Colors.black.withValues(alpha: 0.3),
      );
      canvas.drawCircle(
        postCenter,
        postRadius,
        Paint()..color = const Color(0xFFE8ECF4),
      );
      canvas.drawCircle(
        postCenter - Offset(postRadius * 0.3, postRadius * 0.3),
        postRadius * 0.4,
        Paint()..color = Colors.white70,
      );
    }
  }

  void _paintPlayers(Canvas canvas) {
    for (final player in frame.players) {
      final center = viewport.worldToScreen(player.x, player.y);
      final radius = viewport.worldDeltaToScreen(controller.rules.playerRadius);
      // Roster order is red seats then blue, so index parity is not team.
      final teamColor = controller.teamOf(player.deviceIndex) == Team.red
          ? AppColors.p1
          : AppColors.p4;

      if (player.isGoalkeeper) {
        final halfWidth = viewport.worldDeltaToScreen(
          controller.rules.playerRadius * 0.8,
        );
        final halfHeight = viewport.worldDeltaToScreen(
          controller.rules.playerRadius * 1.4,
        );
        paintGoalkeeper(canvas, center, halfWidth, halfHeight, teamColor);
        continue;
      }
      paintOutfieldPlayer(
        canvas,
        center,
        radius,
        teamColor,
        player.facingYaw,
        walkPhase: controller.walk.phaseFor(player.deviceIndex),
        stride: controller.walk.strideFor(player.deviceIndex),
      );
    }
  }

  void _paintBall(Canvas canvas) {
    final ballScreen = viewport.worldToScreen(frame.ballX, frame.ballY);
    if (!viewport.playRect.inflate(24).contains(ballScreen)) return;
    final radius = viewport.worldDeltaToScreen(controller.rules.ballRadius);
    final speed = sqrt(
      controller.ballVx * controller.ballVx +
          controller.ballVy * controller.ballVy,
    );
    final speedFactor = (speed / controller.rules.maxBallSpeed).clamp(0.0, 1.0);

    if (speedFactor > 0.15) {
      final direction = Offset(controller.ballVx, controller.ballVy) / speed;
      final trail = Paint()
        ..color = Colors.white.withValues(alpha: 0.3 * speedFactor)
        ..strokeWidth = radius * 0.7
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        ballScreen -
            direction * radius * (1.5 + 4.5 * speedFactor),
        ballScreen - direction * radius * 0.4,
        trail,
      );
    }

    final glow = Paint()
      ..color = Colors.white.withValues(alpha: 0.22 + speedFactor * 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.6);
    canvas.drawCircle(ballScreen, radius * 1.15, glow);

    // Classic panel ball: white base + spinning black pentagons.
    canvas.drawCircle(
      ballScreen,
      radius,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      ballScreen,
      radius,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.14,
    );

    final direction = Offset(controller.ballVx, controller.ballVy);
    final baseAngle = speed > 1e-3 ? atan2(direction.dy, direction.dx) : 0.0;
    final spin = speedFactor * 1.1;

    void paintPentagon(Offset center, double angle, double size) {
      final path = Path();
      for (var i = 0; i < 5; i++) {
        final a = angle + i * 2 * pi / 5 + pi / 2;
        final p = center + Offset(cos(a), sin(a)) * size;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF11151F));
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // Center panel + a ring of petals rotating with the ball's travel.
    paintPentagon(ballScreen, baseAngle + spin * 1.8, radius * 0.38);
    for (var i = 0; i < 5; i++) {
      final a = baseAngle + i * 2 * pi / 5 + spin * 1.2;
      final orbit = Offset(cos(a), sin(a)) * radius * 0.62;
      paintPentagon(ballScreen + orbit, a, radius * 0.24);
    }
  }

  void _paintEffects(Canvas canvas) {
    for (final fx in effects) {
      if (fx.elapsed >= fx.life) continue;
      final progress = (fx.elapsed / fx.life).clamp(0.0, 1.0);
      final fade = 1 - progress;
      final center = viewport.worldToScreen(fx.x, fx.y);

      switch (fx.kind) {
        case FutbolFxKind.kick:
          final radius = viewport.worldDeltaToScreen(30) * (0.3 + progress);
          canvas.drawCircle(
            center,
            radius,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.8 * fade)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6 * fade + 2,
          );
          canvas.drawCircle(
            center,
            radius * 0.5,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.5 * fade)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8),
          );
        case FutbolFxKind.bounce:
          for (var i = 0; i < 8; i++) {
            final angle = i * pi / 4 + progress * 1.2;
            final dist = viewport.worldDeltaToScreen(26) * progress;
            canvas.drawCircle(
              center + Offset(cos(angle), sin(angle)) * dist,
              viewport.worldDeltaToScreen(5) * (1 - fade * 0.6),
              Paint()..color = Colors.white.withValues(alpha: 0.7 * fade),
            );
          }
        case FutbolFxKind.goal:
          final radius = viewport.worldDeltaToScreen(30 + progress * 120);
          canvas.drawCircle(
            center,
            radius,
            Paint()
              ..color = fx.color.withValues(alpha: 0.7 * fade)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 8 * fade,
          );
          canvas.drawCircle(
            center,
            radius * 0.6,
            Paint()
              ..color = fx.color.withValues(alpha: 0.3 * fade)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 24),
          );
          for (var i = 0; i < 12; i++) {
            final angle = i * pi / 6 + progress * 2;
            final dist = viewport.worldDeltaToScreen(90) * progress;
            canvas.drawCircle(
              center + Offset(cos(angle), sin(angle)) * dist,
              viewport.worldDeltaToScreen(7) * (1 - progress * 0.5),
              Paint()..color = Colors.white.withValues(alpha: fade),
            );
          }
      }
    }
  }

  void _paintScoreboard(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'RED ${frame.redScore} : ${frame.blueScore} BLUE',
        style: TextStyle(
          color: Colors.white,
          fontSize: max(15, size.width * 0.022),
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final y = max(8.0, viewport.playRect.top - painter.height - 8);
    painter.paint(
      canvas,
      Offset((size.width - painter.width) / 2, y),
    );
  }

  @override
  bool shouldRepaint(covariant FutbolArenaPainter oldDelegate) => true;
}