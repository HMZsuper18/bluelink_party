import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({
    super.key,
    required this.onChanged,
    this.size = 140,
    this.knobSize = 52,
    this.dragRadius = 56,
  });

  final ValueChanged<Offset> onChanged;
  final double size;
  final double knobSize;
  final double dragRadius;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _knobOffset = Offset.zero;
  Offset _origin = Offset.zero;
  bool _active = false;

  void _handleStart(DragStartDetails details) {
    setState(() {
      _active = true;
      _origin = details.localPosition;
      _knobOffset = Offset.zero;
    });
    widget.onChanged(Offset.zero);
  }

  void _handleUpdate(DragUpdateDetails details) {
    final delta = details.localPosition - _origin;
    final distance = delta.distance;
    final clamped = distance > widget.dragRadius
        ? delta * (widget.dragRadius / distance)
        : delta;
    setState(() => _knobOffset = clamped);
    final normalized = clamped / widget.dragRadius;
    widget.onChanged(
      Offset(
        normalized.dx.clamp(-1.0, 1.0),
        normalized.dy.clamp(-1.0, 1.0),
      ),
    );
  }

  void _handleEnd() {
    if (!_active) return;
    setState(() {
      _active = false;
      _knobOffset = Offset.zero;
    });
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _handleStart,
      onPanUpdate: _handleUpdate,
      onPanEnd: (_) => _handleEnd(),
      onPanCancel: _handleEnd,
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface.withValues(alpha: 0.45),
                border: Border.all(color: AppColors.borderStrong),
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 90),
              alignment: Alignment(_knobOffset.dx / (widget.size / 2),
                  _knobOffset.dy / (widget.size / 2)),
              curve: Curves.easeOut,
              child: Container(
                width: widget.knobSize,
                height: widget.knobSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: _active ? 1 : 0.7),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}