import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/player_slot.dart';
import '../../../data/models/team.dart';

/// Presentation-layer mapping from a team to its muted accent color.
Color teamColor(Team team) {
  switch (team) {
    case Team.red:
      return AppColors.p2;
    case Team.blue:
      return AppColors.p1;
  }
}

IconData teamIcon(Team team) {
  switch (team) {
    case Team.red:
      return Icons.sports_martial_arts_rounded;
    case Team.blue:
      return Icons.water_drop_rounded;
  }
}

String slotPlayerName(PlayerSlot? slot) =>
    slot?.isFilled == true ? (slot!.playerName ?? 'Player') : '—';

bool slotIsMine(PlayerSlot? slot, String myPlayerId) =>
    slot != null && slot.isFilled && slot.playerId == myPlayerId;
