import 'package:flutter/material.dart';

import '../../../../core/theme/acrylic.dart';
import '../../../../core/theme/app_colors.dart';
import '../../bloc/lobby_state.dart';

/// In-room action controls: the host starts the match, clients leave.
class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.state,
    required this.onStartMatch,
    required this.onDisconnect,
  });

  final LobbyState state;
  final VoidCallback onStartMatch;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      child: state.isHost ? _hosting() : _client(),
    );
  }

  Widget _hosting() {
    final canStart = state.canStartMatch;
    final remaining = (state.room?.selectedMode.minPlayers ?? 0) - state.filledSlots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassButton(
          label: 'Start Match',
          icon: Icons.play_arrow_rounded,
          background: AppColors.success.withValues(alpha: 0.16),
          onPressed: canStart ? onStartMatch : null,
        ),
        const SizedBox(height: 8),
        Text(
          canStart
              ? '${state.filledSlots}/${state.room!.selectedMode.minPlayers} minimum slots filled — ready to go.'
              : 'Waiting for players… need $remaining more for ${state.room?.selectedMode.label ?? 'this mode'}.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: GlassButton(
            label: 'Disconnect',
            compact: true,
            background: AppColors.danger.withValues(alpha: 0.10),
            onPressed: onDisconnect,
          ),
        ),
      ],
    );
  }

  Widget _client() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassButton(
          label: 'Leave Lobby',
          icon: Icons.logout_rounded,
          background: AppColors.danger.withValues(alpha: 0.10),
          onPressed: onDisconnect,
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap a team to join it. The host controls the game mode.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
