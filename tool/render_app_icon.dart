// Renders the BlueLink Party launcher icon set into
// `android/app/src/main/res/mipmap-*/`.
//
// The icon reuses the shared in-game player sprite
// (`lib/features/matrix_futbol/presentation/futbol_player_sprite.dart`) and the
// pitch backdrop painted by the same code that generates the README hero art,
// so the launcher icon is exactly what the game looks like — and matches the
// in-app [FutbolLauncherIcon] logo.
//
// Writes:
//   * legacy `ic_launcher.png` (48 / 72 / 96 / 144 / 192) — full-bleed square
//   * adaptive `ic_launcher_adaptive_back.png` + `_fore.png` (108 / 162 / 216 /
//     324 / 432) — pitch behind, player kept inside the 66dp safe zone
//
// Run with:
//   flutter test tool/render_app_icon.dart
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bluelink_party/core/theme/app_colors.dart';
import 'package:bluelink_party/features/matrix_futbol/presentation/futbol_player_sprite.dart';

/// Each density folder maps to its icon size in px.
const Map<String, int> _legacySizes = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// Adaptive layers are 108dp canvas (foreground art confined to the center
/// 66dp safe zone) at each density.
const Map<String, int> _adaptiveSizes = {
  'mdpi': 108,
  'hdpi': 162,
  'xhdpi': 216,
  'xxhdpi': 324,
  'xxxhdpi': 432,
};

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final res = Directory('android/app/src/main/res');

  // Legacy: full-bleed square, player slightly larger for a bolder silhouette.
  for (final entry in _legacySizes.entries) {
    final dir = Directory('${res.path}/mipmap-${entry.key}')
      ..createSync(recursive: true);
    await _writePng(
      File('${dir.path}/ic_launcher.png'),
      entry.value,
      (canvas, size) => paintAppIcon(canvas, Size.square(size)),
    );
  }

  // Adaptive: pitch as the background layer, player only (transparent) sized
  // to the 66dp safe zone in the foreground layer.
  for (final entry in _adaptiveSizes.entries) {
    final dir = Directory('${res.path}/mipmap-${entry.key}')
      ..createSync(recursive: true);
    await _writePng(
      File('${dir.path}/ic_launcher_adaptive_back.png'),
      entry.value,
      (canvas, size) => paintAppPitch(canvas, Size.square(size)),
    );
    await _writePng(
      File('${dir.path}/ic_launcher_adaptive_fore.png'),
      entry.value,
      (canvas, size) => paintOutfieldPlayer(
        canvas,
        Offset(size / 2, size / 2),
        size * 0.24,
        AppColors.p1,
        -pi / 2,
        walkPhase: pi / 2,
        stride: 1,
      ),
    );
  }

  stdout.writeln('Launcher icon set written to ${res.path}/mipmap-*/');
}

/// Records [paint] at its native pixel size (1:1) and writes it to [out].
/// Each icon is recorded at its target resolution — `Picture.toImage` does not
/// reliably downscale a larger recording in the test renderer.
Future<void> _writePng(
  File out,
  int size,
  void Function(Canvas canvas, double size) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
  );
  paint(canvas, size.toDouble());
  final picture = recorder.endRecording();

  final image = await picture.toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('Failed to encode PNG for ${out.path}');
  }
  out.writeAsBytesSync(bytes.buffer.asUint8List());
  stdout.writeln('Wrote ${out.path} ($size x $size)');
}
