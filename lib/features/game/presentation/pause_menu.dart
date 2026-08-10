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

/// Full-screen pause menu shown on every device while the host has frozen the
/// shared match. Any device can resume; quitting returns to the lobby.
class PauseMenuOverlay extends StatelessWidget {
  const PauseMenuOverlay({
    super.key,
    required this.onResume,
    required this.onQuit,
    this.title = 'Paused',
  });

  final VoidCallback onResume;
  final VoidCallback onQuit;
  final String title;

  @override
  Widget build(BuildContext context) {
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
}
