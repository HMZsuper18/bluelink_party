import 'package:equatable/equatable.dart';

import 'game_mode.dart';
import 'player_slot.dart';
import 'team.dart';

/// Immutable snapshot of the whole lobby, shared between host and clients over
/// the wire. Groups [PlayerSlot] seats per [Team] (Red / Blue).
class LobbyRoom extends Equatable {
  const LobbyRoom({
    required this.hostIp,
    required this.lobbyName,
    required this.selectedMode,
    required this.teams,
    this.roomCode = '',
    this.revision = 0,
  });

  final String hostIp;
  final String lobbyName;
  final String roomCode;
  final GameMode selectedMode;

  /// Both teams present, each holding exactly [Team.capacity] seats.
  final Map<Team, List<PlayerSlot>> teams;
  final int revision;

  int get filledSlots => teams.values
      .expand((slots) => slots)
      .where((s) => s.isFilled)
      .length;

  List<PlayerSlot> slotsOf(Team team) => teams[team] ?? const [];

  PlayerSlot? slotAt(Team team, int seat) {
    final slots = teams[team];
    if (slots == null || seat < 0 || seat >= slots.length) return null;
    return slots[seat];
  }

  /// The empty seat indices on [team], in order.
  List<int> emptySeats(Team team) {
    return [
      for (var i = 0; i < Team.capacity; i++)
        if (!(slotAt(team, i)?.isFilled ?? true)) i,
    ];
  }

  Team? teamOf(String playerId) {
    for (final team in Team.all) {
      for (final slot in slotsOf(team)) {
        if (slot.isFilled && slot.playerId == playerId) return team;
      }
    }
    return null;
  }

  Map<String, String> get playerNames => {
        for (final team in Team.all)
          for (final slot in slotsOf(team))
            if (slot.isFilled && slot.playerId != null)
              slot.playerId!: slot.playerName ?? 'Unknown',
      };

  LobbyRoom copyWith({
    String? hostIp,
    String? lobbyName,
    String? roomCode,
    GameMode? selectedMode,
    Map<Team, List<PlayerSlot>>? teams,
    int? revision,
  }) {
    return LobbyRoom(
      hostIp: hostIp ?? this.hostIp,
      lobbyName: lobbyName ?? this.lobbyName,
      roomCode: roomCode ?? this.roomCode,
      selectedMode: selectedMode ?? this.selectedMode,
      teams: teams ?? this.teams,
      revision: revision ?? this.revision + 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'hostIp': hostIp,
        'lobbyName': lobbyName,
        'roomCode': roomCode,
        'selectedMode': GameModeSelection(selectedMode).toJson(),
        'teams': {
          for (final entry in teams.entries)
            entry.key.key: [for (final slot in entry.value) slot.toJson()],
        },
        'revision': revision,
      };

  factory LobbyRoom.fromJson(Map<String, dynamic> json) {
    final rawTeams = json['teams'] as Map<String, dynamic>? ?? {};
    return LobbyRoom(
      hostIp: json['hostIp'] as String? ?? '',
      lobbyName: json['lobbyName'] as String? ?? 'BlueLink Party Lobby',
      roomCode: json['roomCode'] as String? ?? '',
      selectedMode: GameModeSelection.fromJson(
        json['selectedMode'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ).mode,
      teams: {
        for (final entry in rawTeams.entries)
          Team.fromTag(entry.key): [
            for (final raw in (entry.value as List<dynamic>? ?? const []))
              PlayerSlot.fromJson(raw as Map<String, dynamic>),
          ],
      },
      revision: json['revision'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [hostIp, lobbyName, roomCode, selectedMode, teams, revision];
}

/// A lobby discovered on the network by a scanning client.
class DiscoveredLobby extends Equatable {
  const DiscoveredLobby({
    required this.hostIp,
    required this.hostPort,
    required this.lobbyName,
    required this.roomCode,
    required this.mode,
    required this.filledSlots,
    required this.hostName,
  });

  final String hostIp;
  final int hostPort;
  final String lobbyName;
  final String roomCode;
  final GameMode mode;
  final int filledSlots;
  final String hostName;

  @override
  List<Object?> get props =>
      [hostIp, hostPort, lobbyName, roomCode, mode, filledSlots, hostName];
}
