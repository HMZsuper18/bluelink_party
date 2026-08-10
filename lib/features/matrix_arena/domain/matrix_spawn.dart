import 'dart:math';

import 'matrix_grid.dart';
import 'matrix_world.dart';

class MatrixSpawnPoint {
  const MatrixSpawnPoint({
    required this.x,
    required this.y,
    required this.tileIndex,
  });

  final double x;
  final double y;
  final int tileIndex;
}

class MatrixSpawnManager {
  MatrixSpawnManager({
    required this.matrix,
    Random? random,
  }) : _random = random ?? Random();

  final TileMatrix matrix;
  final Random _random;

  MatrixSpawnPoint randomPoint() {
    final x = _random.nextDouble() * matrix.worldWidth;
    final y = _random.nextDouble() * matrix.worldHeight;
    final column = (x ~/ matrix.tileWidth).clamp(0, matrix.columns - 1);
    final row = (y ~/ matrix.tileHeight).clamp(0, matrix.rows - 1);
    return MatrixSpawnPoint(
      x: x,
      y: y,
      tileIndex: matrix.columns * row + column,
    );
  }

  List<MatrixSpawnPoint> spawnAll(int deviceCount) {
    final spawns = <MatrixSpawnPoint>[];
    for (var pass = 0; pass < deviceCount; pass++) {
      var candidate = randomPoint();
      for (var attempt = 0; attempt < 24; attempt++) {
        var tooClose = false;
        for (final other in spawns) {
          final dx = candidate.x - other.x;
          final dy = candidate.y - other.y;
          if (dx * dx + dy * dy < 160 * 160) {
            tooClose = true;
            break;
          }
        }
        if (!tooClose) break;
        candidate = randomPoint();
      }
      spawns.add(candidate);
    }
    return spawns;
  }

  ({double x, double y}) clampedWithinWorld(
    MatrixWorldConfig config,
    double x,
    double y,
  ) {
    final minX = config.wallPadding;
    final minY = config.wallPadding;
    final maxX = matrix.worldWidth - config.wallPadding;
    final maxY = matrix.worldHeight - config.wallPadding;
    return (
      x: x.clamp(minX, maxX),
      y: y.clamp(minY, maxY),
    );
  }
}