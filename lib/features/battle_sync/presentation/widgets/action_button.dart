import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.onPressedChanged,
    this.size = 84,
    this.label = 'FIRE',
    this.color = AppColors.danger,
  });

  final ValueChanged<bool> onPressedChanged;
  final double size;
  final String label;
  final Color color;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    widget.onPressedChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed
              ? widget.color.withValues(alpha: 0.9)
              : widget.color.withValues(alpha: 0.55),
          border: Border.all(
            color: Colors.white.withValues(alpha: _pressed ? 0.7 : 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _pressed ? 0.6 : 0.3),
              blurRadius: _pressed ? 22 : 10,
              spreadRadius: _pressed ? 4 : 0,
            ),
          ],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}