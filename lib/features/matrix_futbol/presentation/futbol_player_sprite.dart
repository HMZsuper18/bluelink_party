import 'dart:math';

import 'package:flutter/material.dart';

// Standalone sprite painters for the Pixel Futbol players. Shared between the
// in-game [FutbolArenaPainter] and the offline image generator
// (`tool/render_futbol_player.dart`) so rendered art never drifts from what
// players see on screen.

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
