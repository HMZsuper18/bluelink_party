import 'dart:math';

import 'package:flutter/painting.dart';

import '../../matrix_arena/domain/matrix_grid.dart';

class FutbolPitch {
  FutbolPitch({
    required this.matrix,
    this.goalHalfHeight = 120,
    this.goalInset = 26,
    this.wallPadding = 10,
  });

  final TileMatrix matrix;
  final double goalHalfHeight;
  final double goalInset;
  final double wallPadding;

  double get worldWidth => matrix.worldWidth;
  double get worldHeight => matrix.worldHeight;

  Rect get bounds => Rect.fromLTWH(0, 0, worldWidth, worldHeight);

  double get centerX => worldWidth / 2;
  double get centerY => worldHeight / 2;

  Offset get leftGoalCenter => Offset(0, centerY);
  Offset get rightGoalCenter => Offset(worldWidth, centerY);

  double get leftGoalTop => centerY - goalHalfHeight;
  double get leftGoalBottom => centerY + goalHalfHeight;
  double get rightGoalTop => centerY - goalHalfHeight;
  double get rightGoalBottom => centerY + goalHalfHeight;

  Offset get leftPostTop => Offset(0, leftGoalTop);
  Offset get leftPostBottom => Offset(0, leftGoalBottom);
  Offset get rightPostTop => Offset(worldWidth, rightGoalTop);
  Offset get rightPostBottom => Offset(worldWidth, rightGoalBottom);

  double get penaltyBoxDepth => min(worldWidth * 0.10, 190);
  double get penaltyBoxHalfWidth => goalHalfHeight + 70;

  Rect get leftPenaltyBox => Rect.fromLTRB(
        0,
        centerY - penaltyBoxHalfWidth,
        penaltyBoxDepth,
        centerY + penaltyBoxHalfWidth,
      );

  Rect get rightPenaltyBox => Rect.fromLTRB(
        worldWidth - penaltyBoxDepth,
        centerY - penaltyBoxHalfWidth,
        worldWidth,
        centerY + penaltyBoxHalfWidth,
      );

  Rect get leftGoalMouth => Rect.fromLTRB(
        -goalInset,
        leftGoalTop,
        0,
        leftGoalBottom,
      );

  Rect get rightGoalMouth => Rect.fromLTRB(
        worldWidth,
        rightGoalTop,
        worldWidth + goalInset,
        rightGoalBottom,
      );

  Offset kickoffBall() => Offset(centerX, centerY);

  /// Kick-off position for the device at [deviceIndex]. [red] is the device's
  /// actual team, so a red player always lines up on the left half and a blue
  /// player on the right — independent of roster order or device index. The
  /// optional [slice] (the device's camera slice) positions the player inside
  /// the slice they can see, defaulting to the geometric grid tile.
  Offset kickoffPlayer(
    int deviceIndex, {
    required bool red,
    MatrixTileLayout? slice,
  }) {
    final s = slice ?? matrix.layoutForIndex(deviceIndex);
    final column = s.column;
    final row = s.row;
    final laneX = red ? 0.24 : 0.76;
    final spread = matrix.deviceCount == 2 ? 0.0 : 0.06;
    final x = worldWidth * (laneX + (column.isEven ? 0.0 : spread));
    final vertical = (row - (matrix.rows - 1) / 2);
    return Offset(x, centerY + vertical * worldHeight * 0.18);
  }

  Offset clampPlayer(Offset position) {
    return Offset(
      position.dx.clamp(wallPadding, worldWidth - wallPadding),
      position.dy.clamp(wallPadding, worldHeight - wallPadding),
    );
  }
}