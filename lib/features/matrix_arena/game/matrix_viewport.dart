import 'dart:math';

import 'package:flutter/painting.dart';

import '../domain/matrix_grid.dart';

class MatrixViewportCamera {
  MatrixViewportCamera({
    required this.tile,
    required this.screenSize,
    this.tileMargin = 0,
  }) {
    _fit();
  }

  final MatrixTileLayout tile;
  final Size screenSize;
  final double tileMargin;

  late double _scale;
  late Rect _portrait;

  double get scale => _scale;

  Rect get playRect => _portrait;

  Offset worldToScreen(double worldX, double worldY) {
    return Offset(
      _portrait.left + (worldX - tile.left) * _scale,
      _portrait.top + (worldY - tile.top) * _scale,
    );
  }

  double worldDeltaToScreen(double worldDelta) => worldDelta * _scale;

  bool isVisibleOnScreen(Offset screenPoint, double margin) {
    return screenPoint.dx >= _portrait.left - margin &&
        screenPoint.dx <= _portrait.right + margin &&
        screenPoint.dy >= _portrait.top - margin &&
        screenPoint.dy <= _portrait.bottom + margin;
  }

  bool overlapsPlayable({required double left, required double top, required double right, required double bottom}) {
    return right >= _portrait.left &&
        left <= _portrait.right &&
        bottom >= _portrait.top &&
        top <= _portrait.bottom;
  }

  void _fit() {
    final tileWidth = tile.tileWidth;
    final tileHeight = tile.tileHeight;
    final availableWidth = screenSize.width - tileMargin * 2;
    final availableHeight = screenSize.height - tileMargin * 2;
    _scale = min(
      availableWidth / tileWidth,
      availableHeight / tileHeight,
    );
    final scaledWidth = tileWidth * _scale;
    final scaledHeight = tileHeight * _scale;
    final left = tileMargin + (availableWidth - scaledWidth) / 2;
    final top = tileMargin + (availableHeight - scaledHeight) / 2;
    _portrait = Rect.fromLTWH(left, top, scaledWidth, scaledHeight);
  }
}

class MatrixControlZones {
  const MatrixControlZones({
    required this.joystickRect,
    required this.fireRect,
    required this.healthBarsRect,
    required this.tileIndicatorRect,
  });

  final Rect joystickRect;
  final Rect fireRect;
  final Rect? healthBarsRect;
  final Rect? tileIndicatorRect;

  bool get usesSideControls => joystickRect.left <= fireRect.left;

  static MatrixControlZones compute({
    required Size screenSize,
    required Rect playRect,
    required EdgeInsets padding,
    double minControlWidth = 110,
  }) {
    final leftStrip = playRect.left - padding.left;
    final rightStrip = screenSize.width - playRect.right - padding.right;
    final topStrip = playRect.top - padding.top;
    final bottomStrip = screenSize.height - playRect.bottom - padding.bottom;

    Rect? joystick;
    Rect? fire;
    Rect? health;

    if (leftStrip >= minControlWidth) {
      joystick = Rect.fromLTWH(
        padding.left + 16,
        screenSize.height / 2 - 70,
        140,
        140,
      );
    } else if (leftStrip >= 56) {
      joystick = Rect.fromLTWH(
        padding.left + 10,
        screenSize.height / 2 - 60,
        120,
        120,
      );
    }

    if (rightStrip >= minControlWidth) {
      fire = Rect.fromLTWH(
        screenSize.width - padding.right - 16 - 96,
        screenSize.height / 2 - 48,
        96,
        96,
      );
    } else if (rightStrip >= 56) {
      fire = Rect.fromLTWH(
        screenSize.width - padding.right - 10 - 76,
        screenSize.height / 2 - 38,
        76,
        76,
      );
    }

    if (topStrip >= 44) {
      health = Rect.fromLTRB(
        playRect.left,
        padding.top + 12,
        playRect.right,
        padding.top + 46,
      );
    }

    // Fallback: when the arena letterboxes the screen (e.g. portrait phones)
    // there is no strip to dock controls in, so pin them to the screen bottom
    // corners exactly like Battle Sync instead of floating them at the
    // arena's mid-screen bottom edge.
    final joystickFallback = Rect.fromLTWH(
      padding.left + 16,
      screenSize.height - padding.bottom - 16 - 140,
      140,
      140,
    );
    final fireFallback = Rect.fromLTWH(
      screenSize.width - padding.right - 16 - 84,
      screenSize.height - padding.bottom - 16 - 84,
      84,
      84,
    );
    final healthFallback = Rect.fromLTRB(
      playRect.left + 8,
      playRect.top + 8,
      playRect.right - 8,
      playRect.top + 40,
    );

    Rect? tileIndicator;
    if (bottomStrip >= 26 && playRect.bottom + 12 < screenSize.height - 8) {
      tileIndicator = Rect.fromLTRB(
        playRect.left,
        playRect.bottom + 14,
        playRect.left + 148,
        playRect.bottom + 14 + 24,
      );
    }

    return MatrixControlZones(
      joystickRect: joystick ?? joystickFallback,
      fireRect: fire ?? fireFallback,
      healthBarsRect: health ?? healthFallback,
      tileIndicatorRect: tileIndicator,
    );
  }
}