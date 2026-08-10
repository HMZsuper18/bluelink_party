import 'package:equatable/equatable.dart';

import '../../../data/models/lobby_room.dart';
import '../../../data/models/match_event.dart';
import '../../../data/models/team.dart';
import '../../game/sync/game_sync_adapter.dart';
import '../../matrix_arena/game/matrix_arena_controller.dart';
import '../../matrix_futbol/game/futbol_match_controller.dart';

enum NetworkRole { idle, scanning, hosting, client }

/// UI-facing state of the lobby dashboard. Immutable; rebuilt by the bloc on
/// every network/Wi-Fi/UI event.
class LobbyState extends Equatable {
  const LobbyState({
    this.playerId = '',
    this.playerName = '',
    this.profileLoaded = false,
    this.role = NetworkRole.idle,
    this.room,
    this.rttMs = const {},
    this.hostRttMs,
    this.ssid = '',
    this.isWifi = false,
    this.foundLobbies = const [],
    this.connecting = const {},
    this.error,
    this.matchReady = false,
    this.matchEvent,
    this.gameSync,
    this.matrixController,
    this.futbolController,
  });

  final String playerId;
  final String playerName;
  final bool profileLoaded;
  final NetworkRole role;

  /// Authoritative lobby room (null before hosting/joining).
  final LobbyRoom? room;

  /// Average latency (ms) per filled player, keyed by player id.
  final Map<String, int> rttMs;

  /// Client's own round-trip latency to the host (ms).
  final int? hostRttMs;

  final String ssid;
  final bool isWifi;

  /// Lobbies discovered during the last scan.
  final List<DiscoveredLobby> foundLobbies;

  /// Teams with a claim request currently in flight.
  final Set<Team> connecting;

  final String? error;
  final bool matchReady;

  /// Last host-driven game transition (countdown, in-game, result).
  final MatchEvent? matchEvent;

  /// Live game sync gateway to pass to [GameScreen]. Lifecycle owned by the
  /// lobby bloc; intentionally excluded from equality so UI rebuilds are cheap.
  final GameSyncAdapter? gameSync;

  /// Matrix arena controller for Screen Shift matches. Lifecycle owned by the
  /// lobby bloc, like [gameSync].
  final MatrixArenaController? matrixController;

  /// Pixel Futbol match controller. Lifecycle owned by the lobby bloc, like
  /// [gameSync].
  final FutbolMatchController? futbolController;

  bool get matchInProgress => matchEvent != null;

  int get filledSlots => room?.filledSlots ?? 0;
  bool get isHost => role == NetworkRole.hosting;
  bool get isClient => role == NetworkRole.client;
  bool get isScanning => role == NetworkRole.scanning;

  int? get averageLatencyMs {
    final values = rttMs.values.where((v) => v >= 0).toList();
    if (values.isEmpty) return null;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }

  bool get canStartMatch {
    if (!isHost || room == null) return false;
    return room!.filledSlots >= room!.selectedMode.minPlayers;
  }

  LobbyState copyWith({
    String? playerId,
    String? playerName,
    bool? profileLoaded,
    NetworkRole? role,
    LobbyRoom? room,
    bool clearRoom = false,
    Map<String, int>? rttMs,
    int? hostRttMs,
    bool clearHostRtt = false,
    String? ssid,
    bool? isWifi,
    List<DiscoveredLobby>? foundLobbies,
    Set<Team>? connecting,
    String? error,
    bool clearError = false,
    bool? matchReady,
    MatchEvent? matchEvent,
    bool clearMatchEvent = false,
    GameSyncAdapter? gameSync,
    MatrixArenaController? matrixController,
    bool clearMatrix = false,
    FutbolMatchController? futbolController,
    bool clearFutbol = false,
  }) {
    return LobbyState(
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,
      profileLoaded: profileLoaded ?? this.profileLoaded,
      role: role ?? this.role,
      room: clearRoom ? null : (room ?? this.room),
      rttMs: rttMs ?? this.rttMs,
      hostRttMs: clearHostRtt ? null : (hostRttMs ?? this.hostRttMs),
      ssid: ssid ?? this.ssid,
      isWifi: isWifi ?? this.isWifi,
      foundLobbies: foundLobbies ?? this.foundLobbies,
      connecting: connecting ?? this.connecting,
      error: clearError ? null : (error ?? this.error),
      matchReady: matchReady ?? this.matchReady,
      matchEvent: clearMatchEvent ? null : (matchEvent ?? this.matchEvent),
      gameSync: gameSync ?? this.gameSync,
      matrixController:
          clearMatrix ? null : (matrixController ?? this.matrixController),
      futbolController: clearFutbol
          ? null
          : (futbolController ?? this.futbolController),
    );
  }

  @override
  List<Object?> get props => [
        playerId,
        playerName,
        profileLoaded,
        role,
        room,
        rttMs,
        hostRttMs,
        ssid,
        isWifi,
        foundLobbies,
        connecting,
        error,
        matchReady,
        matchEvent,
        gameSync,
        matrixController,
        futbolController,
      ];
}
