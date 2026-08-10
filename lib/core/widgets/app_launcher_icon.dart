import 'package:flutter/material.dart';

/// The BlueLink Party app logo: the transparent launcher-icon emblem, drawn on
/// top of a contrasting frame (supplied by the parent container). The emblem is
/// the same art as the Android launcher icon's foreground layer, so the in-app
/// logo and the home-screen icon stay identical.
class AppLauncherIcon extends StatelessWidget {
  const AppLauncherIcon({super.key, this.size});

  /// When set, the icon is drawn at a fixed square size; otherwise it fills
  /// the parent's constraints.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/icon/ic_launcher_emblem.png',
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
    if (size == null) return image;
    return SizedBox.square(dimension: size, child: image);
  }
}
