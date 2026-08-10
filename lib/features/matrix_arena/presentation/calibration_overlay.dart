import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/matrix_grid.dart';
import '../game/matrix_viewport.dart';

class CalibrationOverlay extends StatelessWidget {
  const CalibrationOverlay({
    super.key,
    required this.viewport,
    required this.tile,
    required this.phaseLabel,
    required this.countdown,
    this.positionLabel,
    this.positionColor,
    this.matrix,
    this.deviceIndex,
  });

  final MatrixViewportCamera viewport;
  final MatrixTileLayout tile;
  final String phaseLabel;
  final double countdown;
  final String? positionLabel;
  final Color? positionColor;

  /// When set, a mini-map of the full device formation is drawn with the
  /// current device highlighted ("this is where your screen goes").
  final TileMatrix? matrix;
  final int? deviceIndex;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: CalibrationBorderPainter(
          viewport: viewport,
          tile: tile,
          phaseLabel: phaseLabel,
          countdown: countdown,
          positionLabel: positionLabel,
          positionColor: positionColor,
          matrix: matrix,
          deviceIndex: deviceIndex,
        ),
      ),
    );
  }
}

class CalibrationBorderPainter extends CustomPainter {
  const CalibrationBorderPainter({
    required this.viewport,
    required this.tile,
    required this.phaseLabel,
    required this.countdown,
    this.positionLabel,
    this.positionColor,
    this.matrix,
    this.deviceIndex,
  });

  final MatrixViewportCamera viewport;
  final MatrixTileLayout tile;
  final String phaseLabel;
  final double countdown;
  final String? positionLabel;
  final Color? positionColor;
  final TileMatrix? matrix;
  final int? deviceIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final play = viewport.playRect;

    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, play.top),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, play.bottom, size.width, size.height),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, play.top, play.left, play.bottom),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTRB(play.right, play.top, size.width, play.bottom),
      dim,
    );

    final pulse = 0.5 + 0.5 * sin(countdown * 5);
    final glow = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.6 + pulse * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRect(play.inflate(4), glow);

    final framePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(play, framePaint);

    if (tile.hasLeftNeighbor) {
      _paintSeamArrow(canvas, Alignment.centerLeft, Alignment.centerLeft, true);
    }
    if (tile.hasRightNeighbor) {
      _paintSeamArrow(canvas, Alignment.centerRight, Alignment.centerRight, false);
    }
    if (tile.hasTopNeighbor) {
      _paintSeamArrow(canvas, Alignment.topCenter, Alignment.topCenter, true);
    }
    if (tile.hasBottomNeighbor) {
      _paintSeamArrow(canvas, Alignment.bottomCenter, Alignment.bottomCenter, false);
    }

    _paintLabel(canvas, size);
    _paintArrangementMap(canvas, size);
  }

  /// Mini-map of the whole device formation. Each device's slice is drawn as
  /// a tile inside a world-shaped box; the current device is highlighted with
  /// its slot color so players know exactly where to hold their screen.
  void _paintArrangementMap(Canvas canvas, Size size) {
    final matrix = this.matrix;
    final deviceIndex = this.deviceIndex;
    if (matrix == null || deviceIndex == null) return;

    const boxWidth = 120.0;
    const boxHeight = 84.0;
    final worldAspect = matrix.worldWidth / matrix.worldHeight;
    final mapW = min(boxWidth, boxHeight * worldAspect);
    final mapH = min(boxHeight, boxWidth / worldAspect);
    final map = Rect.fromLTWH(
      size.width - mapW - 16,
      size.height - mapH - 16,
      mapW,
      mapH,
    );

    final bg = Paint()
      ..color = AppColors.surfaceRaised.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(map.inflate(10), const Radius.circular(10)),
      bg,
    );
    final border = Paint()
      ..color = AppColors.borderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(map.inflate(10), const Radius.circular(10)),
      border,
    );

    final world = Rect.fromLTWH(
      map.left + map.width * 0.06,
      map.top + map.height * 0.10,
      map.width * 0.88,
      map.height * 0.62,
    );

    final baseFill = Paint()..style = PaintingStyle.fill;
    final localStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    for (var i = 0; i < matrix.deviceCount; i++) {
      final tile = matrix.layoutForIndex(i);
      final rect = Rect.fromLTWH(
        world.left + tile.left / matrix.worldWidth * world.width,
        world.top + tile.top / matrix.worldHeight * world.height,
        tile.tileWidth / matrix.worldWidth * world.width,
        tile.tileHeight / matrix.worldHeight * world.height,
      ).deflate(1.2);
      final color = SlotVisuals.colorOf(i);
      final isLocal = i == deviceIndex;
      baseFill.color = isLocal
          ? color.withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.14);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        baseFill,
      );
      if (isLocal) {
        localStroke.color = Colors.white;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          localStroke,
        );
      }
      _paintMapNumber(canvas, rect, i + 1, isLocal ? color : Colors.white70);
    }

    _paintMapCaption(
      canvas,
      'YOUR SCREEN: ${deviceIndex + 1}',
      Offset(size.width - mapW - 16, map.bottom + 2),
      isCentered: true,
    );
  }

  void _paintMapNumber(Canvas canvas, Rect rect, int number, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        rect.center.dx - textPainter.width / 2,
        rect.center.dy - textPainter.height / 2,
      ),
    );
  }

  void _paintMapCaption(
    Canvas canvas,
    String text,
    Offset position, {
    bool isCentered = false,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = isCentered ? position.dx - textPainter.width / 2 : position.dx;
    textPainter.paint(canvas, Offset(dx, position.dy));
  }

  void _paintSeamArrow(
    Canvas canvas,
    Alignment edge,
    Alignment direction,
    bool pointingOut,
  ) {
    final play = viewport.playRect;
    final center = play.center;
    final offset = Offset(
      edge.x * play.width / 2,
      edge.y * play.height / 2,
    );
    final origin = center + offset;

    final sign = pointingOut ? 1.0 : -1.0;
    final dirX = edge.x * sign;
    final dirY = edge.y * sign;

    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final tip = origin + Offset(dirX, dirY) * 26;
    final perpendicular = Offset(-dirY, dirX);
    final baseA = origin + perpendicular * 9;
    final baseB = origin - perpendicular * 9;

    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseA.dx, baseA.dy)
      ..lineTo(baseB.dx, baseB.dy)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
  }

  void _paintLabel(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: phaseLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final position = Offset(
      viewport.playRect.center.dx - textPainter.width / 2,
      viewport.playRect.top - 40,
    );
    final safeTop = position.dy.clamp(8.0, size.height - 40);
    textPainter.paint(canvas, Offset(position.dx, safeTop));

    if (positionLabel != null && positionColor != null) {
      final center = viewport.playRect.center;
      final labelPainter = TextPainter(
        text: TextSpan(
          text: positionLabel,
          style: TextStyle(
            color: positionColor,
            fontSize: 42,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            shadows: [
              Shadow(
                color: positionColor!.withValues(alpha: 0.55),
                blurRadius: 24,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(
          center.dx - labelPainter.width / 2,
          center.dy - labelPainter.height / 2,
        ),
      );

      final subPainter = TextPainter(
        text: TextSpan(
          text: 'HOLD YOUR DEVICE IN THIS POSITION',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      subPainter.paint(
        canvas,
        Offset(
          center.dx - subPainter.width / 2,
          center.dy + 56,
        ),
      );
      return;
    }

    final countdownText = TextPainter(
      text: TextSpan(
        text: countdown <= 0 ? '' : countdown.ceil().toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 96,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final countdownPosition = Offset(
      viewport.playRect.center.dx - countdownText.width / 2,
      viewport.playRect.center.dy - countdownText.height / 2,
    );
    countdownText.paint(canvas, countdownPosition);
  }

  @override
  bool shouldRepaint(covariant CalibrationBorderPainter oldDelegate) {
    return oldDelegate.countdown != countdown ||
        oldDelegate.phaseLabel != phaseLabel ||
        oldDelegate.positionLabel != positionLabel ||
        oldDelegate.positionColor != positionColor;
  }
}