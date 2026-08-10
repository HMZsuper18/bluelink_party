import 'lobby_room.dart';
import 'player_slot.dart';
import 'team.dart';

/// Pure, socket-free lobby rules so the networking services stay thin and the
/// logic is unit-testable.
abstract final class LobbyRules {
  static const int maxPlayers = 4;

  /// Attempts to assign [playerId]/[playerName] to [requestedTeam] (or the
  /// first team with a free seat when null/full). Returns the updated room
  /// plus the assigned team/seat, or null when the lobby is full.
  ///
  /// A player (including the host) holds at most one seat. If they already
  /// occupy a seat, requesting the same team is a no-op, while requesting a
  /// different team moves them over only when that team has a free seat.
  static ({LobbyRoom room, Team team, int seat})? assignSlot({
    required LobbyRoom room,
    required String playerId,
    required String playerName,
    bool isHost = false,
    Team? requestedTeam,
  }) {
    final currentTeam = room.teamOf(playerId);
    if (currentTeam != null) {
      if (requestedTeam == null || requestedTeam == currentTeam) {
        final currentSeat = room
            .slotsOf(currentTeam)
            .indexWhere((s) => s.playerId == playerId);
        if (currentSeat < 0) return null;
        return (room: room, team: currentTeam, seat: currentSeat);
      }

      // Switching teams is allowed only when the requested team has a seat
      // free; otherwise the player keeps their current seat.
      if (room.emptySeats(requestedTeam).isEmpty) return null;
      final released = releaseSlot(room: room, playerId: playerId);
      if (released == null) return null;
      return _assignNew(
        released,
        playerId: playerId,
        playerName: playerName,
        isHost: isHost,
        requestedTeam: requestedTeam,
      );
    }

    return _assignNew(
      room,
      playerId: playerId,
      playerName: playerName,
      isHost: isHost,
      requestedTeam: requestedTeam,
    );
  }

  /// Assigns a player that currently holds no seat.
  static ({LobbyRoom room, Team team, int seat})? _assignNew(
    LobbyRoom room, {
    required String playerId,
    required String playerName,
    required bool isHost,
    Team? requestedTeam,
  }) {
    if (room.filledSlots >= maxPlayers) return null;

    var target = requestedTeam;
    int? seat;
    if (target != null) {
      final empty = room.emptySeats(target);
      if (empty.isNotEmpty) seat = empty.first;
    }
    if (target == null || seat == null) {
      for (final team in Team.all) {
        final empty = room.emptySeats(team);
        if (empty.isNotEmpty) {
          target = team;
          seat = empty.first;
          break;
        }
      }
    }
    if (target == null || seat == null) return null;

    final teams = Map<Team, List<PlayerSlot>>.from(room.teams);
    teams[target] = List<PlayerSlot>.from(teams[target] ?? const []);
    teams[target]![seat] = PlayerSlot(
      team: target,
      seat: seat,
      playerId: playerId,
      playerName: playerName,
      isHost: isHost,
    );

    return (room: room.copyWith(teams: teams), team: target, seat: seat);
  }

  /// Releases the seat owned by [playerId], if any.
  static LobbyRoom? releaseSlot({
    required LobbyRoom room,
    required String playerId,
  }) {
    final team = room.teamOf(playerId);
    if (team == null) return null;

    final teams = Map<Team, List<PlayerSlot>>.from(room.teams);
    teams[team] = List<PlayerSlot>.from(teams[team] ?? const []);
    final seatIndex = teams[team]!.indexWhere((s) => s.playerId == playerId);
    if (seatIndex < 0) return null;
    teams[team]![seatIndex] = PlayerSlot(team: team, seat: seatIndex);

    return room.copyWith(teams: teams);
  }

  /// Whether the host may start a match for this room.
  static bool canStart({required LobbyRoom room}) {
    return room.filledSlots >= room.selectedMode.minPlayers;
  }
}
