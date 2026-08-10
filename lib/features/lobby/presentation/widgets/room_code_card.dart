import 'package:flutter/material.dart';

import '../../../../core/theme/acrylic.dart';
import '../../../../core/theme/app_colors.dart';

/// Shows the active room: a big 4-digit code for the host to share, or a
/// compact joined-room chip for guests.
class RoomCodeCard extends StatelessWidget {
  const RoomCodeCard({
    super.key,
    required this.roomCode,
    required this.filledSlots,
    required this.isHost,
  });

  final String roomCode;
  final int filledSlots;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isHost ? Icons.cast_rounded : Icons.link_rounded,
                size: 18,
                color: isHost ? AppColors.p1 : AppColors.p4,
              ),
              const SizedBox(width: 8),
              Text(
                isHost ? 'YOUR ROOM CODE' : 'JOINED ROOM',
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            roomCode,
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isHost
                ? 'Share this code — others join from the room list'
                : '$filledSlots player${filledSlots == 1 ? '' : 's'} connected',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
