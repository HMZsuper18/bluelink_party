import 'package:equatable/equatable.dart';

import '../../../data/models/game_mode.dart';
import '../../../data/models/lobby_room.dart';
import '../../../data/models/match_event.dart';
import '../../../data/models/team.dart';
import '../../../data/repositories/wifi_info_repository.dart';
import '../../../network/client_service.dart';
import '../../../network/host_service.dart';

sealed class LobbyEvent extends Equatable {
  const LobbyEvent();

  @override
  List<Object?> get props => const [];
}

/// Loads the persisted player identity into the state.
class LoadProfile extends LobbyEvent {
  const LoadProfile();
}

/// Persists and applies the entered player name.
class SavePlayerName extends LobbyEvent {
  const SavePlayerName(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Starts the local UDP listener and advertises a lobby as the host.
class CreateLobby extends LobbyEvent {
  const CreateLobby();
}

/// Broadcasts a discovery probe and waits for host OFFER responses.
class ScanForLobbies extends LobbyEvent {
  const ScanForLobbies();
}

/// Aborts an in-progress scan.
class CancelScan extends LobbyEvent {
  const CancelScan();
}

/// Joins a lobby discovered during the scan.
class JoinDiscovered extends LobbyEvent {
  const JoinDiscovered(this.lobby);

  final DiscoveredLobby lobby;

  @override
  List<Object?> get props => [lobby];
}

/// Claims a seat on a specific team.
class ClaimSlot extends LobbyEvent {
  const ClaimSlot(this.team);

  final Team team;

  @override
  List<Object?> get props => [team];
}

/// Releases the current player's seat.
class ReleaseSlot extends LobbyEvent {
  const ReleaseSlot();

  @override
  List<Object?> get props => const [];
}

/// Removes another member from the lobby (any in-room player can kick).
class KickMember extends LobbyEvent {
  const KickMember(this.playerId);

  final String playerId;

  @override
  List<Object?> get props => [playerId];
}

/// Host-only: changes the active game mode and syncs to clients.
class SelectMode extends LobbyEvent {
  const SelectMode(this.mode);

  final GameMode mode;

  @override
  List<Object?> get props => [mode];
}

/// Host-only: attempts to start the match once the minimum slots are filled.
class StartMatch extends LobbyEvent {
  const StartMatch();
}

/// Re-syncs the current network session (ping peers, push state).
class RefreshNetwork extends LobbyEvent {
  const RefreshNetwork();
}

/// Leaves the current session and returns to idle.
class Disconnect extends LobbyEvent {
  const Disconnect();
}

/// Clears transient notices (error, match-ready banner).
class ClearNotice extends LobbyEvent {
  const ClearNotice();
}

// ---------------------------------------------------------------------------
// Internal events bridging the network / platform streams into the bloc.
// ---------------------------------------------------------------------------

class WifiStatusChanged extends LobbyEvent {
  const WifiStatusChanged(this.status);

  final WifiStatus status;

  @override
  List<Object?> get props => [status];
}

class HostSnapshotReceived extends LobbyEvent {
  const HostSnapshotReceived(this.snapshot);

  final HostSnapshot snapshot;

  @override
  List<Object?> get props => [snapshot];
}

class ClientSnapshotReceived extends LobbyEvent {
  const ClientSnapshotReceived(this.snapshot);

  final ClientSnapshot snapshot;

  @override
  List<Object?> get props => [snapshot];
}

class ServiceError extends LobbyEvent {
  const ServiceError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class MatchEventReceived extends LobbyEvent {
  const MatchEventReceived(this.event);

  final MatchEvent event;

  @override
  List<Object?> get props => [event];
}

/// Clears the active match session and returns to the lobby dashboard.
class ReturnToLobby extends LobbyEvent {
  const ReturnToLobby();
}
