import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// A frosted-glass container using [BackdropFilter] blur + a thin translucent
/// border, in the Windows 10 Acrylic style. Panels are flat and matte: no
/// shadows, no neon, no strong highlight.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.blur = 18,
    this.tint = const Color(0x0FFFFFFF),
    this.borderColor = AppColors.border,
    this.borderWidth = 1,
    this.backgroundColor = const Color(0x0AFFFFFF),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final double blur;
  final Color tint;
  final Color borderColor;
  final double borderWidth;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Padding(
            padding: padding,
            child: tint == Colors.transparent ? child : child,
          ),
        ),
      ),
    );
  }
}

/// Frosted background wrapper for the whole screen: a charcoal gradient under
/// a full-bleed blur so panels read as "glass over a dark surface".
class AcrylicBackdrop extends StatelessWidget {
  const AcrylicBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF12141F),
                  AppColors.background,
                  Color(0xFF0A0B10),
                ],
              ),
            ),
          ),
          RepaintBoundary(child: child),
        ],
      ),
    );
  }
}

/// A small rounded status pill with a flat matte tint.
class GlassBadge extends StatelessWidget {
  const GlassBadge({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.textSecondary,
    this.background = const Color(0x14FFFFFF),
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final Color background;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: color,
      fontSize: compact ? 10 : 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 11 : 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}

/// A flat, matte action button with a soft hover ripple.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.textPrimary,
    this.background = const Color(0x14FFFFFF),
    this.expanded = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color background;
  final bool expanded;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final fg = disabled ? AppColors.textMuted : color;
    final bg = disabled ? const Color(0x0AFFFFFF) : background;

    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: compact ? 15 : 17, color: fg),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 12 : 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 18,
            vertical: compact ? 9 : 13,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: disabled ? AppColors.border : AppColors.borderStrong,
            ),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}
