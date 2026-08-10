import 'dart:math';

import 'package:flutter/painting.dart';

import '../../matrix_arena/domain/matrix_snapshots.dart';

/// Drives the Pixel Futbol players' run cycle from the motion actually being
/// rendered, so the animated feet appear (and alternate front/back along the
/// facing axis) only while a player is moving, and tuck back under the body
/// when it stops.
///
/// The controller advances this every simulation step with the current render
/// frame, so it works identically on the host (live positions) and on clients
/// (interpolated positions) without touching the wire protocol.
class FutbolWalkAnimator {
  /// World units travelled per full stride cycle (two steps).
  static const double _strideLength = 80;

  final Map<int, Offset> _lastPosition = {};
  final Map<int, double> _phase = {};
  final Map<int, double> _stride = {};

  void advance(
    double dt,
    List<MatrixPlayerSnapshot> players, {
    double maxSpeed = 260,
  }) {
    if (dt <= 0) return;
    for (final player in players) {
      if (player.isGoalkeeper) continue;
      final position = Offset(player.x, player.y);
      final last = _lastPosition[player.deviceIndex];
      _lastPosition[player.deviceIndex] = position;
      if (last == null) continue;

      // Clamp to the maximum a player could physically travel this frame so a
      // teleport (e.g. the kick-off reset after a goal) cannot register as a
      // full sprint and flash the feet.
      final moved =
          min((position - last).distance, maxSpeed * dt).toDouble();
      final currentStride = _stride[player.deviceIndex] ?? 0;
      if (moved > 0.001) {
        _phase[player.deviceIndex] =
            (_phase[player.deviceIndex] ?? 0) + moved / _strideLength * 2 * pi;
        final target = (moved / dt / maxSpeed).clamp(0.0, 1.0);
        _stride[player.deviceIndex] = _approach(currentStride, target, dt * 6);
      } else {
        _stride[player.deviceIndex] = _approach(currentStride, 0, dt * 6);
      }
    }
  }

  /// Run-cycle angle in radians, 0..2pi. Only meaningful while moving.
  double phaseFor(int deviceIndex) => _phase[deviceIndex] ?? 0;

  /// How hard the player is running, 0 (idle) .. 1 (full sprint).
  double strideFor(int deviceIndex) => _stride[deviceIndex] ?? 0;

  double _approach(double current, double target, double maxDelta) {
    if (current < target) return min(current + maxDelta, target);
    if (current > target) return max(current - maxDelta, target);
    return current;
  }
}
