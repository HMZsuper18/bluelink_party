import 'package:flutter/material.dart';

/// Flat, muted palette for the Windows 10 Acrylic / frosted-glass aesthetic.
abstract final class AppColors {
  static const Color background = Color(0xFF0D0E15);
  static const Color surface = Color(0xFF141621);
  static const Color surfaceRaised = Color(0xFF1A1D2A);

  static const Color inactiveSlot = Color(0xFF2A2D3A);
  static const Color inactiveSlotDarker = Color(0xFF1F2230);

  static const Color textPrimary = Color(0xFFF2F3F7);
  static const Color textSecondary = Color(0xFF9BA0B4);
  static const Color textMuted = Color(0xFF5E6478);

  static const Color border = Color(0x14FFFFFF);
  static const Color borderStrong = Color(0x26FFFFFF);

  static const Color accent = Color(0xFF7C8CF5);

  static const Color success = Color(0xFF00C855);
  static const Color warning = Color(0xFFE6C800);
  static const Color danger = Color(0xFFD70055);

  static const Color p1 = Color(0xFF00C8D7);
  static const Color p2 = Color(0xFFD70055);
  static const Color p3 = Color(0xFFE6C800);
  static const Color p4 = Color(0xFF00C855);
}

/// Visual identity mapped to each slot position. Kept in the UI layer so the
/// data models stay decoupled from presentation concerns.
abstract final class SlotVisuals {
  static Color colorOf(int index) {
    switch (index % 4) {
      case 0:
        return AppColors.p1;
      case 1:
        return AppColors.p2;
      case 2:
        return AppColors.p3;
      default:
        return AppColors.p4;
    }
  }
}
