import 'package:flutter/material.dart';

/// The BlueLink Party app logo: the Android launcher icon (the blue emblem on
/// its light tile), loaded from the asset bundle so the in-app logo is exactly
/// the icon users see on their home screen. Drop it inside a rounded container
/// with `clipBehavior: Clip.antiAlias` to match the launcher's squircle.
class AppLauncherIcon extends StatelessWidget {
  const AppLauncherIcon({super.key, this.size});

  /// When set, the icon is drawn at a fixed square size; otherwise it fills
  /// the parent's constraints.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/icon/ic_launcher.png',
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
    if (size == null) return image;
    return SizedBox.square(dimension: size, child: image);
  }
}
