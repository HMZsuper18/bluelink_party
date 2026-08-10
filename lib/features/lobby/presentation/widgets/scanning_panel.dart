import 'package:flutter/material.dart';

import '../../../../core/theme/acrylic.dart';
import '../../../../core/theme/app_colors.dart';

/// Shown while the guest scans the network for available rooms.
class ScanningPanel extends StatelessWidget {
  const ScanningPanel({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 14),
          const Text(
            'Searching for rooms...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Looking for BlueLink Party hosts on this Wi-Fi network',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: GlassButton(
              label: 'Cancel',
              compact: true,
              onPressed: onCancel,
            ),
          ),
        ],
      ),
    );
  }
}
