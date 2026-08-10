import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/acrylic.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/lobby_room.dart';
import '../../../../data/models/player_slot.dart';
import '../../../../data/models/team.dart';
import '../team_theme.dart';

/// A single Red or Blue team card showing its up-to-two seats.
class TeamCard extends StatelessWidget {
  const TeamCard({
    super.key,
    required this.team,
    required this.room,
    required this.rttMs,
    required this.connecting,
    required this.myPlayerId,
    required this.interactive,
    required this.onJoin,
    required this.onKick,
  });

  final Team team;
  final LobbyRoom room;
  final Map<String, int> rttMs;
  final bool connecting;
  final String myPlayerId;
  final bool interactive;
  final VoidCallback onJoin;
  final void Function(String playerId) onKick;

  Color get _color => teamColor(team);

  @override
  Widget build(BuildContext context) {
    final filled = room.slotsOf(team).where((s) => s.isFilled).length;
    final full = filled >= Team.capacity;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _color.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(filled, full),
                const SizedBox(height: 12),
                for (var seat = 0; seat < Team.capacity; seat++) ...[
                  _seat(seat),
                  if (seat != Team.capacity - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int filled, bool full) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(teamIcon(team), size: 18, color: _color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${team.name.toUpperCase()} TEAM',
            style: const TextStyle(
              fontSize: 13,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          '$filled/${Team.capacity}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: full ? _color : AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _seat(int seat) {
    final slot = room.slotAt(team, seat);
    final empty = slot?.isFilled != true;
    final isMine = slotIsMine(slot, myPlayerId);
    final firstEmpty = room.emptySeats(team).isNotEmpty
        ? room.emptySeats(team).first
        : null;
    final myTeam = room.teamOf(myPlayerId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: empty
            ? AppColors.inactiveSlotDarker.withValues(alpha: 0.6)
            : _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: empty ? AppColors.border : _color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: empty
          ? _emptySeat(
              showAction: interactive && team != myTeam && seat == firstEmpty)
          : _filledSeat(slot!, isMine),
    );
  }

  Widget _emptySeat({required bool showAction}) {
    return Row(
      children: [
        Icon(Icons.person_outline_rounded,
            size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Empty seat',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
        if (showAction)
          GlassButton(
            label: 'Change',
            compact: true,
            background: _color.withValues(alpha: 0.14),
            onPressed: connecting ? null : onJoin,
          ),
        if (connecting) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }

  Widget _filledSeat(PlayerSlot slot, bool isMine) {
    final rtt = rttMs[slot.playerId];
    return Row(
      children: [
        Icon(Icons.person_rounded, size: 16, color: _color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            slot.playerName ?? 'Player',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (rtt != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '$rtt ms',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        if (isMine)
          const GlassBadge(label: 'You', color: AppColors.textPrimary)
        else
          GlassBadge(
            label: slot.isHost ? 'Host' : 'In',
            color: _color,
            background: _color.withValues(alpha: 0.14),
          ),
        if (!isMine && !slot.isHost && interactive)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: IconButton(
              icon: const Icon(
                Icons.person_remove_alt_1_rounded,
                size: 16,
                color: AppColors.danger,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              tooltip: 'Kick ${slot.playerName ?? 'member'}',
              onPressed: () => onKick(slot.playerId!),
            ),
          ),
      ],
    );
  }
}
