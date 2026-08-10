import 'package:equatable/equatable.dart';

import 'team.dart';

enum ConnectionStatus {
  connected('Connected'),
  connecting('Connecting...'),
  empty('Empty');

  const ConnectionStatus(this.label);

  final String label;
}

/// A single seat on a team (red or blue). Each team has exactly [Team.capacity]
/// seats; empty seats carry no player.
class PlayerSlot extends Equatable {
  const PlayerSlot({
    required this.team,
    required this.seat,
    this.playerId,
    this.playerName,
    this.isHost = false,
  });

  final Team team;
  final int seat;
  final String? playerId;
  final String? playerName;
  final bool isHost;

  bool get isFilled => playerId != null && playerName != null;

  ConnectionStatus get status =>
      isFilled ? ConnectionStatus.connected : ConnectionStatus.empty;

  PlayerSlot copyWith({
    Team? team,
    int? seat,
    String? playerId,
    String? playerName,
    bool? isHost,
    bool clear = false,
  }) {
    return PlayerSlot(
      team: team ?? this.team,
      seat: seat ?? this.seat,
      playerId: clear ? null : (playerId ?? this.playerId),
      playerName: clear ? null : (playerName ?? this.playerName),
      isHost: clear ? false : (isHost ?? this.isHost),
    );
  }

  Map<String, dynamic> toJson() => {
        'team': team.key,
        'seat': seat,
        if (isFilled) 'playerId': playerId,
        if (isFilled) 'playerName': playerName,
        'isHost': isHost,
      };

  factory PlayerSlot.fromJson(Map<String, dynamic> json) {
    return PlayerSlot(
      team: Team.fromTag(json['team'] as String?),
      seat: (json['seat'] as num?)?.toInt() ?? 0,
      playerId: json['playerId'] as String?,
      playerName: json['playerName'] as String?,
      isHost: json['isHost'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [team, seat, playerId, playerName, isHost];
}
