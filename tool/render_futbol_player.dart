// Renders PNG art of the Pixel Futbol player into `images/`.
//
// The render uses the shared in-game painter
// (`lib/features/matrix_futbol/presentation/futbol_player_sprite.dart`), so
// the image is exactly what players look like from above on the pitch.
//
// Run with:
//   flutter test tool/render_futbol_player.dart
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bluelink_party/core/theme/app_colors.dart';
import 'package:bluelink_party/features/matrix_futbol/presentation/futbol_player_sprite.dart';

const double _canvas = 1024;
const double _playerRadius = 170;

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final outDir = Directory('images')..createSync(recursive: true);

  // Outfield player in the P1 kit, from above, facing up the pitch, caught
  // mid-stride so the alternating footsteps are visible.
  await _render(File('${outDir.path}/futbol_player.png'), (canvas) {
    paintOutfieldPlayer(
      canvas,
      const Offset(_canvas / 2, 560),
      _playerRadius,
      AppColors.p1,
      -pi / 2,
      walkPhase: pi / 2,
      stride: 1,
    );
  });

  stdout.writeln('Player art written to ${outDir.path}/');
}Future<void> _render(File out, void Function(Canvas canvas) paintContent) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, _canvas, _canvas));

  _paintPitchBackdrop(canvas);
  paintContent(canvas);

  final picture = recorder.endRecording();
  final image = await picture.toImage(_canvas.toInt(), _canvas.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('Failed to encode PNG for ${out.path}');
  }
  out.writeAsBytesSync(bytes.buffer.asUint8List());
  stdout.writeln('Wrote ${out.path}');
}

void _paintPitchBackdrop(Canvas canvas) {
  final bounds = Offset.zero & const Size(_canvas, _canvas);

  // Base pitch gradient, shared with FutbolArenaPainter._paintPitchBase.
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [futbolPitchTop, futbolPitchBottom],
      ).createShader(bounds),
  );

  // Faint mowing stripes.
  final stripe = Paint()..color = Colors.white.withValues(alpha: 0.045);
  for (var x = 0; x < _canvas; x += 128) {
    canvas.drawRect(
      Rect.fromLTWH(x.toDouble(), 0, 64, _canvas),
      stripe,
    );
  }

  // Subtle field markings: halfway line, center circle and centre spot.
  final mark = Paint()
    ..color = Colors.white.withValues(alpha: 0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4;
  canvas.drawLine(
    Offset(_canvas / 2, 0),
    Offset(_canvas / 2, _canvas),
    mark,
  );
  canvas.drawCircle(Offset(_canvas / 2, _canvas / 2), _canvas * 0.24, mark);
  canvas.drawCircle(Offset(_canvas / 2, _canvas / 2), 8, mark);

  // Soft vignette for depth.
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = RadialGradient(
        radius: 1.1,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.35),
        ],
        stops: const [0.55, 1.0],
      ).createShader(bounds),
  );
}
