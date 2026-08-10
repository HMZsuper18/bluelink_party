import 'package:flutter/material.dart';

import 'futbol_player_sprite.dart';

/// The BlueLink Party app logo: the same pitch-and-player art used for the
/// Android launcher icon (`tool/render_app_icon.dart`), painted live so it
/// scales to any spot in the UI. Drop it inside a rounded container with
/// `clipBehavior: Clip.antiAlias` to match the launcher's squircle corners.
class FutbolLauncherIcon extends StatelessWidget {
  const FutbolLauncherIcon({super.key, this.size});

  /// When set, the icon is drawn at a fixed square size; otherwise it fills
  /// the parent's constraints.
  final double? size;

  @override
  Widget build(BuildContext context) {
    const child = CustomPaint(painter: _FutbolLauncherIconPainter());
    if (size == null) return child;
    return SizedBox.square(dimension: size, child: child);
  }
}

class _FutbolLauncherIconPainter extends CustomPainter {
  const _FutbolLauncherIconPainter();

  @override
  void paint(Canvas canvas, Size size) => paintAppIcon(canvas, size);

  @override
  bool shouldRepaint(covariant _FutbolLauncherIconPainter oldDelegate) => false;
}
