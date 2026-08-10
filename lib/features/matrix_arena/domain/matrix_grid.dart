import 'dart:ui';

/// A single device's slice of the shared world: which grid cell it owns plus
/// an optional overridden slice size/offset. Used for non-rectangular
/// formations like the 3-player triangle, where the bottom device spans the
/// full row so every part of the world stays covered by a camera.
class MatrixDeviceSlot {
  const MatrixDeviceSlot(
    this.column,
    this.row, {
    this.offsetX = 0,
    this.offsetY = 0,
    this.width,
    this.height,
  });

  final int column;
  final int row;
  final double offsetX;
  final double offsetY;

  /// Width/height override for the slice; defaults to the matrix tile size.
  final double? width;
  final double? height;
}

class MatrixGridArrangement {
  const MatrixGridArrangement({
    required this.columns,
    required this.rows,
    this.slots,
  });

  final int columns;
  final int rows;

  /// Explicit per-device slots. Defaults to row-major order over the
  /// [columns] x [rows] grid when null.
  final List<MatrixDeviceSlot>? slots;

  int get count => slots?.length ?? columns * rows;

  bool isValidTile(int column, int row) {
    return column >= 0 &&
        column < columns &&
        row >= 0 &&
        row < rows;
  }

  MatrixDeviceSlot slotForIndex(int index) {
    final slots = this.slots;
    if (slots != null) return slots[index];
    return MatrixDeviceSlot(index % columns, index ~/ columns);
  }

  int indexOfTile(int column, int row) {
    final slots = this.slots;
    if (slots != null) {
      return slots.indexWhere(
        (s) => s.column == column && s.row == row,
      );
    }
    return row * columns + column;
  }
}

class MatrixTileLayout {
  const MatrixTileLayout({
    required this.deviceIndex,
    required this.column,
    required this.row,
    required this.columns,
    required this.rows,
    required this.tileWidth,
    required this.tileHeight,
    this.tileUnitWidth,
    this.tileUnitHeight,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  final int deviceIndex;
  final int column;
  final int row;
  final int columns;
  final int rows;

  /// This slice's rendered size (may be overridden, e.g. the 3-player bottom
  /// device spans the full row).
  final double tileWidth;
  final double tileHeight;

  /// The grid's nominal unit tile size. Defaults to [tileWidth]/[tileHeight]
  /// for ordinary slices; used to compute the world boundary for seam
  /// detection so an overridden full-width slice still reports no side
  /// neighbors.
  final double? tileUnitWidth;
  final double? tileUnitHeight;

  final double offsetX;
  final double offsetY;

  double get _unitWidth => tileUnitWidth ?? tileWidth;
  double get _unitHeight => tileUnitHeight ?? tileHeight;

  double get left => column * _unitWidth + offsetX;
  double get top => row * _unitHeight + offsetY;
  double get right => left + tileWidth;
  double get bottom => top + tileHeight;
  double get centerX => left + tileWidth / 2;
  double get centerY => top + tileHeight / 2;

  Rect get tileRect => Rect.fromLTWH(left, top, tileWidth, tileHeight);

  // Neighbors are derived from the tile's actual geometry against the world
  // boundary, so slots with a width/height override (e.g. the 3-player bottom
  // device spanning the full row) report the same seams a player can
  // physically see.
  bool get hasLeftNeighbor => left > 0;
  bool get hasRightNeighbor => right < columns * _unitWidth;
  bool get hasTopNeighbor => top > 0;
  bool get hasBottomNeighbor => bottom < rows * _unitHeight;

  bool overlapsPoint(double x, double y) {
    return x >= left && x <= right && y >= top && y <= bottom;
  }
}

class TileMatrix {
  const TileMatrix({
    this.tileWidth = 1000,
    this.tileHeight = 600,
    required this.columns,
    required this.rows,
    this.slots,
  });

  final double tileWidth;
  final double tileHeight;
  final int columns;
  final int rows;

  /// Explicit per-device slots; defaults to row-major when null.
  final List<MatrixDeviceSlot>? slots;

  int get deviceCount => slots?.length ?? columns * rows;

  double get worldWidth => columns * tileWidth;
  double get worldHeight => rows * tileHeight;

  Rect get worldRect =>
      Rect.fromLTWH(0, 0, worldWidth, worldHeight);

  MatrixTileLayout layoutForIndex(int index) {
    final slot = slots?[index] ?? MatrixDeviceSlot(
          index % columns,
          index ~/ columns,
        );
    return MatrixTileLayout(
      deviceIndex: index,
      column: slot.column,
      row: slot.row,
      columns: columns,
      rows: rows,
      tileWidth: slot.width ?? tileWidth,
      tileHeight: slot.height ?? tileHeight,
      tileUnitWidth: tileWidth,
      tileUnitHeight: tileHeight,
      offsetX: slot.offsetX,
      offsetY: slot.offsetY,
    );
  }
}

class MatrixLayoutManager {
  const MatrixLayoutManager({
    this.tileWidth = 1000,
    this.tileHeight = 600,
  });

  final double tileWidth;
  final double tileHeight;

  MatrixGridArrangement gridForPlayerCount(int playerCount) {
    return switch (playerCount) {
      2 => const MatrixGridArrangement(columns: 2, rows: 1),
      3 => MatrixGridArrangement(
          columns: 2,
          rows: 2,
          slots: [
            const MatrixDeviceSlot(0, 0),
            const MatrixDeviceSlot(1, 0),
            // The lone bottom device spans the full row so every part of the
            // world stays covered by a camera.
            MatrixDeviceSlot(0, 1, width: tileWidth * 2, height: tileHeight),
          ],
        ),
      4 => const MatrixGridArrangement(columns: 2, rows: 2),
      _ => throw ArgumentError(
          'ScreenShift matrix supports 2, 3 or 4 players, got $playerCount',
        ),
    };
  }

  TileMatrix matrixForPlayerCount(int playerCount) {
    final grid = gridForPlayerCount(playerCount);
    return TileMatrix(
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      columns: grid.columns,
      rows: grid.rows,
      slots: grid.slots,
    );
  }

  MatrixTileLayout tileForDevice(int deviceIndex, int playerCount) {
    return matrixForPlayerCount(playerCount).layoutForIndex(deviceIndex);
  }
}