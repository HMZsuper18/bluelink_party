import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The first step in the lobby: choose your role. Host creates a 4-digit room,
/// Guest joins one from the available list.
class RoleChoicePanel extends StatelessWidget {
  const RoleChoicePanel({
    super.key,
    required this.onHost,
    required this.onJoin,
  });

  final VoidCallback onHost;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _roleTile(
          title: 'Host a Room',
          subtitle: 'Create a room and get a 4-digit code',
          icon: Icons.add_home_rounded,
          accent: AppColors.p1,
          onTap: onHost,
        ),
        const SizedBox(height: 12),
        _roleTile(
          title: 'Join a Room',
          subtitle: 'Pick a room from the available list',
          icon: Icons.radar_rounded,
          accent: AppColors.accent,
          onTap: onJoin,
        ),
        const SizedBox(height: 14),
        const Text(
          'Both phones must be on the same Wi-Fi network.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _roleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
