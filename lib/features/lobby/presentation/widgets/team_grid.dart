import 'package:flutter/material.dart';

import '../../../../data/models/lobby_room.dart';
import '../../../../data/models/team.dart';
import 'team_card.dart';

/// The two side-by-side team cards: Red on the left, Blue on the right.
class TeamGrid extends StatelessWidget {
  const TeamGrid({
    super.key,
    required this.room,
    required this.rttMs,
    required this.connecting,
    required this.myPlayerId,
    required this.interactive,
    required this.onJoin,
    required this.onKick,
  });

  final LobbyRoom room;
  final Map<String, int> rttMs;
  final Set<Team> connecting;
  final String myPlayerId;
  final bool interactive;
  final void Function(Team) onJoin;
  final void Function(String playerId) onKick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (index, team) in Team.all.indexed) ...[
          Expanded(
            child: TeamCard(
              team: team,
              room: room,
              rttMs: rttMs,
              connecting: connecting.contains(team),
              myPlayerId: myPlayerId,
              interactive: interactive,
              onJoin: () => onJoin(team),
              onKick: onKick,
            ),
          ),
          if (index != Team.all.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}
