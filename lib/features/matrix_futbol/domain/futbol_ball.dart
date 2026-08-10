import 'dart:math';

import 'package:flutter/painting.dart';

class FutbolBall {
  FutbolBall({
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.radius = 14,
    this.drag = 0.85,
    this.wallRestitution = 0.9,
    this.maxSpeed = 900,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double radius;
  final double drag;
  final double wallRestitution;
  final double maxSpeed;

  double get speed => sqrt(vx * vx + vy * vy);

  void reset(double px, double py) {
    x = px;
    y = py;
    vx = 0;
    vy = 0;
  }

  void step(double dt) {
    final damping = exp(-drag * dt);
    vx *= damping;
    vy *= damping;
    x += vx * dt;
    y += vy * dt;
    _clampSpeed();
  }

  void applyImpulse(double dx, double dy) {
    vx += dx;
    vy += dy;
    _clampSpeed();
  }

  void reflect(Offset normal) {
    final nv = vx * normal.dx + vy * normal.dy;
    if (nv >= 0) return;
    vx -= (1 + wallRestitution) * nv * normal.dx;
    vy -= (1 + wallRestitution) * nv * normal.dy;
    _clampSpeed();
  }

  void _clampSpeed() {
    final s = speed;
    if (s > maxSpeed) {
      final scale = maxSpeed / s;
      vx *= scale;
      vy *= scale;
    }
  }
}