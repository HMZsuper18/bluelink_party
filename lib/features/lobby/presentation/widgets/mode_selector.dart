import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/game_mode.dart';

/// Segmented selector between the two game modes. Only the host can change it;
/// clients see the active mode read-only.
class ModeSelector extends StatelessWidget {
  const ModeSelector({
    super.key,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final GameMode? selected;
  final bool enabled;
  final void Function(GameMode) onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final mode in GameMode.values) ...[
          Expanded(child: _modeTile(mode)),
          if (mode != GameMode.values.last) const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _modeTile(GameMode mode) {
    final active = mode == selected;
    final accent = switch (mode) {
      GameMode.battleSync => AppColors.p1,
      GameMode.pixelFutbol => AppColors.p3,
      GameMode.screenShift => AppColors.p2,
    };
    final icon = switch (mode) {
      GameMode.battleSync => Icons.swipe_rounded,
      GameMode.pixelFutbol => Icons.sports_soccer_rounded,
      GameMode.screenShift => Icons.grid_view_rounded,
    };

    return Material(
      color: active
          ? accent.withValues(alpha: 0.12)
          : AppColors.inactiveSlotDarker.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? () => onSelected(mode) : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? accent.withValues(alpha: 0.6) : AppColors.border,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? accent : AppColors.textMuted,
              ),
              const SizedBox(height: 8),
              Text(
                mode.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color:
                      active ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                mode.subtitle,
                style: const TextStyle(
                    fontSize: 10.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Text(
                'Min ${mode.minPlayers} players',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: active ? accent : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
