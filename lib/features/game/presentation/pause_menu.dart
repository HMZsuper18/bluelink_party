import 'package:flutter/material.dart';

import '../../../core/theme/acrylic.dart';
import '../../../core/theme/app_colors.dart';

/// The circular glass pause button floating in a game screen's corner while
/// the match is live. Matches the visual language of the other HUD chrome.
class PauseMenuButton extends StatelessWidget {
  const PauseMenuButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x14FFFFFF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(
            Icons.pause_rounded,
            color: AppColors.textPrimary,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// One seat shown in the ready-gated pause menu (Pixel Futbol / shared HUD).
class PauseReadySeat {
  const PauseReadySeat({
    required this.name,
    required this.accent,
    required this.ready,
    required this.isLocal,
  });

  final String name;
  final Color accent;
  final bool ready;
  final bool isLocal;
}

/// Full-screen pause menu shown on every device while the host has frozen the
/// shared match.
///
/// When [seats] is non-null (Pixel Futbol), each device readies on its own
/// screen. Resume unlocks for everyone once all seats are ready; Restart and
/// Quit are host-only. When [seats] is null (Screen Shift), any device may
/// resume or quit.
class PauseMenuOverlay extends StatelessWidget {
  const PauseMenuOverlay({
    super.key,
    required this.onResume,
    required this.onQuit,
    this.onRestart,
    this.onToggleLocalReady,
    this.seats,
    this.isHost = true,
    this.title = 'Paused',
  });

  final VoidCallback onResume;
  final VoidCallback onQuit;
  final VoidCallback? onRestart;
  final VoidCallback? onToggleLocalReady;
  final List<PauseReadySeat>? seats;
  final bool isHost;
  final String title;

  @override
  Widget build(BuildContext context) {
    final readySeats = seats;
    if (readySeats == null) {
      return _simpleMenu();
    }
    return _readyMenu(readySeats);
  }

  Widget _simpleMenu() {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: GlassPanel(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.pause_circle_filled_rounded,
              color: AppColors.textPrimary,
              size: 46,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'The match is frozen on every device',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            GlassButton(
              label: 'Resume',
              icon: Icons.play_arrow_rounded,
              onPressed: onResume,
            ),
            const SizedBox(height: 10),
            GlassButton(
              label: 'Quit to Lobby',
              icon: Icons.exit_to_app_rounded,
              color: AppColors.danger,
              onPressed: onQuit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _readyMenu(List<PauseReadySeat> readySeats) {
    final readyCount = readySeats.where((s) => s.ready).length;
    final total = readySeats.length;
    final allReady = total > 0 && readyCount == total;
    final canHostAct = allReady && isHost;

    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              allReady
                  ? 'Everyone is ready'
                  : 'Each player readies on their own device',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            for (final seat in readySeats) ...[
              _PauseReadyRow(
                seat: seat,
                onToggle: seat.isLocal ? onToggleLocalReady : null,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '$readyCount / $total ready',
              style: TextStyle(
                fontSize: 12,
                color: allReady ? AppColors.success : AppColors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              !allReady
                  ? 'Waiting for the other players…\nResume unlocks for everyone; Restart and Quit are host-only'
                  : isHost
                      ? 'Resume the match, restart, or quit to the lobby'
                      : 'Waiting for the host to resume, restart, or quit…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: allReady ? AppColors.success : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                GlassButton(
                  label: 'Resume',
                  icon: Icons.play_arrow_rounded,
                  onPressed: allReady ? onResume : null,
                ),
                GlassButton(
                  label: 'Restart',
                  icon: Icons.refresh_rounded,
                  onPressed: canHostAct ? onRestart : null,
                ),
                GlassButton(
                  label: 'Quit',
                  icon: Icons.exit_to_app_rounded,
                  color: AppColors.danger,
                  onPressed: canHostAct ? onQuit : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PauseReadyRow extends StatelessWidget {
  const _PauseReadyRow({
    required this.seat,
    required this.onToggle,
  });

  final PauseReadySeat seat;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        seat.ready ? seat.accent : AppColors.borderStrong;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: seat.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${seat.name}${seat.isLocal ? ' (you)' : ''}',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          seat.ready ? 'READY' : 'WAITING',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: seat.ready ? AppColors.success : AppColors.textMuted,
          ),
        ),
        if (onToggle != null) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.touch_app_rounded,
            size: 14,
            color: seat.ready ? AppColors.success : AppColors.textMuted,
          ),
        ],
      ],
    );

    if (onToggle == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: content,
      );
    }

    return Material(
      color: const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: content,
        ),
      ),
    );
  }
}
