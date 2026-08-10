import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

// Standalone sprite painters for the Pixel Futbol players. Shared between the
// in-game [FutbolArenaPainter] and the offline image generators
// (`tool/render_futbol_player.dart`, `tool/render_app_icon.dart`) so rendered
// art never drifts from what players see on screen.

/// Turf gradient used for the pitch base, shared with the offline image
/// generator so the hero backdrop matches the in-game pitch.
const Color futbolPitchTop = Color(0xFF1B5E20);
const Color futbolPitchBottom = Color(0xFF14532A);

/// Paints an outfield player at [center] with a body of [radius] (screen
/// units), wearing [teamColor] and facing toward [yaw].
///
/// Top-down view: the head sits centered on the round jersey, and while the
/// player runs ([stride] > 0) two feet swing along the facing axis — one steps
/// forward while the other drops back, driven by [walkPhase]. At rest the feet
/// tuck under the body so the sprite is clean.
void paintOutfieldPlayer(
  Canvas canvas,
  Offset center,
  double radius,
  Color teamColor,
  double yaw, {
  double walkPhase = 0,
  double stride = 0,
}) {
  final facing = Offset(cos(yaw), sin(yaw));
  final sideDir = Offset(-facing.dy, facing.dx);

  // Shadow on the turf.
  canvas.drawOval(
    Rect.fromCenter(
      center: center + Offset(2, radius * 0.55),
      width: radius * 1.8,
      height: radius * 0.8,
    ),
    Paint()..color = Colors.black.withValues(alpha: 0.25),
  );

  // Feet swing under the body and peek out front/back while running. Drawn
  // before the body so they stay hidden beneath it at rest.
  if (stride > 0.01) {
    final footPaint = Paint()..color = const Color(0xFF1C2333);
    final amplitude = radius * (0.55 + 0.4 * stride);
    for (final side in [-1.0, 1.0]) {
      canvas.drawCircle(
        center +
            facing * (sin(walkPhase) * amplitude * side) +
            sideDir * side * radius * 0.24,
        radius * 0.2,
        footPaint,
      );
    }
  }

  // Arms peeking out from the sides of the jersey.
  for (final side in [-1.0, 1.0]) {
    canvas.drawCircle(
      center + sideDir * side * radius * 0.88,
      radius * 0.18,
      Paint()..color = teamColor,
    );
  }

  // Jersey: a round kit with a white trim ring.
  final bodyRect = Rect.fromCenter(
    center: center,
    width: radius * 1.6,
    height: radius * 1.6,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(bodyRect, Radius.circular(radius * 0.75)),
    Paint()..color = teamColor,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      bodyRect.inflate(-radius * 0.1),
      Radius.circular(radius * 0.6),
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.1,
  );

  // Head centered on the jersey: skin tone with a hair cap in team color at
  // the back, and a skin arc toward the facing side.
  final head = center;
  canvas.drawCircle(
    head,
    radius * 0.5,
    Paint()..color = const Color(0xFFF2C58F),
  );
  canvas.drawCircle(
    head - facing * radius * 0.15,
    radius * 0.5,
    Paint()..color = teamColor,
  );
  canvas.drawArc(
    Rect.fromCircle(center: head, radius: radius * 0.5),
    pi + yaw - 1.0,
    2.0,
    false,
    Paint()
      ..color = const Color(0xFFF2C58F)
      ..style = PaintingStyle.fill,
  );
}

/// Paints the football pitch backdrop used by the app icon ([paintAppIcon])
/// and the launcher icon's adaptive background layer: turf gradient, mowing
/// stripes, halfway line, centre circle and a soft vignette.
void paintAppPitch(Canvas canvas, Size size) {
  // Base pitch gradient.
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [futbolPitchTop, futbolPitchBottom],
      ).createShader(Offset.zero & size),
  );

  // Faint mowing stripes.
  final stripe = Paint()..color = Colors.white.withValues(alpha: 0.05);
  final stripeWidth = size.width / 16;
  for (var x = 0.0; x < size.width; x += stripeWidth * 2) {
    canvas.drawRect(
      Rect.fromLTWH(x, 0, stripeWidth, size.height),
      stripe,
    );
  }

  // Field markings: halfway line, centre circle and centre spot.
  final mark = Paint()
    ..color = Colors.white.withValues(alpha: 0.38)
    ..style = PaintingStyle.stroke
    ..strokeWidth = size.width * 0.006;
  canvas.drawLine(
    Offset(size.width / 2, 0),
    Offset(size.width / 2, size.height),
    mark,
  );
  canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * 0.24, mark);
  canvas.drawCircle(
    Offset(size.width / 2, size.height / 2),
    size.width * 0.012,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..style = PaintingStyle.fill,
  );

  // Soft vignette for depth.
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = RadialGradient(
        radius: 1.1,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.24),
        ],
        stops: const [0.6, 1.0],
      ).createShader(Offset.zero & size),
  );
}

/// Paints the player-based launcher icon design rendered by
/// `tool/render_app_icon.dart`: a football pitch backdrop with an outfield
/// player in the P1 kit caught mid-stride facing up the pitch.
void paintAppIcon(
  Canvas canvas,
  Size size, {
  double playerRadiusFraction = 0.30,
  double walkPhase = pi / 2,
}) {
  paintAppPitch(canvas, size);

  // Player mid-stride in the P1 kit.
  paintOutfieldPlayer(
    canvas,
    Offset(size.width / 2, size.height / 2),
    size.width * playerRadiusFraction,
    AppColors.p1,
    -pi / 2,
    walkPhase: walkPhase,
    stride: 1,
  );
}

/// Paints a goalkeeper as a rounded kit block with gloved hands flanking the
/// body. [halfWidth] / [halfHeight] are the half-extents of the kit in screen
/// units.
void paintGoalkeeper(
  Canvas canvas,
  Offset center,
  double halfWidth,
  double halfHeight,
  Color teamColor,
) {
  final rect = Rect.fromCenter(
    center: center,
    width: halfWidth * 2,
    height: halfHeight * 2,
  );

  final shadow = Paint()..color = Colors.black.withValues(alpha: 0.3);
  canvas.drawOval(
    Rect.fromCenter(
      center: center + Offset(2, halfHeight * 0.7),
      width: halfWidth * 2.4,
      height: halfHeight * 0.9,
    ),
    shadow,
  );

  // Gloved hands flanking the body.
  final gloveOut = Offset(halfWidth * 0.7, -halfHeight * 0.25);
  final glovePaint = Paint()..color = const Color(0xFFF2F3F7);
  canvas.drawCircle(
    center + Offset(-gloveOut.dx, gloveOut.dy),
    halfWidth * 0.45,
    glovePaint,
  );
  canvas.drawCircle(center + gloveOut, halfWidth * 0.45, glovePaint);

  final glaze = Paint()
    ..color = Colors.black26
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);
  canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), glaze);

  final body = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [teamColor, teamColor.withValues(alpha: 0.6)],
    ).createShader(rect);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(6)),
    body,
  );

  // Jersey stripe.
  canvas.drawLine(
    rect.centerLeft + Offset(0, -halfHeight * 0.4),
    rect.centerRight + Offset(0, -halfHeight * 0.4),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = halfWidth * 0.35,
  );

  final trim = Paint()
    ..color = Colors.white
    ..strokeWidth = 3
    ..style = PaintingStyle.stroke;
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(6)),
    trim,
  );
}
