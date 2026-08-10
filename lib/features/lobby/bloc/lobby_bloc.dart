import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/game_mode.dart';
import '../../../data/models/game_phase.dart';
import '../../../data/models/match_config.dart';
import '../../../data/models/match_event.dart';
import '../../../data/models/team.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/wifi_info_repository.dart';
import '../../../network/client_service.dart';
import '../../../network/host_service.dart';
import '../../../network/protocol.dart';
import '../../game/sync/game_sync_adapter.dart';
import '../../matrix_arena/domain/matrix_grid.dart';
import '../../matrix_arena/game/matrix_arena_controller.dart';
import '../../matrix_arena/game/matrix_transport_sync.dart';
import '../../matrix_futbol/game/futbol_match_controller.dart';
import '../../matrix_futbol/game/futbol_sync_adapter.dart';
import 'lobby_event.dart';
import 'lobby_state.dart';

/// Orchestrates the dashboard: owns the profile, Wi-Fi polling, and the active
/// host/client UDP services, and translates raw network events into immutable
/// [LobbyState] values for the UI layer.
class LobbyBloc extends Bloc<LobbyEvent, LobbyState>
    with WidgetsBindingObserver {
  LobbyBloc({ProfileRepository? profile, PlatformBridge? bridge})
      : _profile = profile ?? ProfileRepository(),
        _bridge = bridge ?? PlatformBridge(),
        super(const LobbyState()) {
    WidgetsBinding.instance.addObserver(this);
    _bridge.startPolling();
    _wifiSub = _bridge.statusStream
        .listen((status) => add(WifiStatusChanged(status)));

    on<LoadProfile>(_onLoadProfile);
    on<SavePlayerName>(_onSaveName);
    on<CreateLobby>(_onCreateLobby);
    on<ScanForLobbies>(_onScanForLobbies);
    on<CancelScan>(_onCancelScan);
    on<JoinDiscovered>(_onJoinDiscovered);
    on<ClaimSlot>(_onClaimSlot);
    on<ReleaseSlot>(_onReleaseSlot);
    on<KickMember>(_onKickMember);
    on<SelectMode>(_onSelectMode);
    on<StartMatch>(_onStartMatch);
    on<RefreshNetwork>(_onRefreshNetwork);
    on<Disconnect>(_onDisconnect);
    on<ClearNotice>(_onClearNotice);
    on<ReturnToLobby>(_onReturnToLobby);

    on<WifiStatusChanged>(_onWifiStatus);
    on<HostSnapshotReceived>(_onHostSnapshot);
    on<ClientSnapshotReceived>(_onClientSnapshot);
    on<ServiceError>(_onServiceError);
    on<MatchEventReceived>(_onMatchEventReceived);

    add(const LoadProfile());
  }

  final ProfileRepository _profile;
  final PlatformBridge _bridge;

  HostService? _host;
  ClientService? _client;

  /// Live gateway wired to whichever service is commanding the current match.
  GameSyncAdapter? _gameSync;

  /// Live Screen Shift controller (host-authoritative; clients mirror).
  MatrixArenaController? _matrixController;

  /// Live Pixel Futbol controller (host-authoritative; clients mirror).
  FutbolMatchController? _futbolController;

  StreamSubscription<HostSnapshot>? _hostSnapSub;
  StreamSubscription<String>? _hostErrSub;
  StreamSubscription<MatchEvent>? _hostMatchSub;
  StreamSubscription<ClientSnapshot>? _clientSnapSub;
  StreamSubscription<String>? _clientErrSub;
  StreamSubscription<MatchEvent>? _clientMatchSub;
  StreamSubscription<WifiStatus>? _wifiSub;

  // -- profile -------------------------------------------------------------

  Future<void> _onLoadProfile(
    LoadProfile event,
    Emitter<LobbyState> emit,
  ) async {
    final id = await _profile.loadPlayerId();
    final name = await _profile.loadPlayerName();
    emit(state.copyWith(playerId: id, playerName: name, profileLoaded: true));
  }

  Future<void> _onSaveName(
    SavePlayerName event,
    Emitter<LobbyState> emit,
  ) async {
    final trimmed = event.name.trim();
    await _profile.savePlayerName(trimmed);
    if (state.isHost && _host != null) {
      _host!.rename(trimmed);
    } else if (state.isClient && _client != null) {
      _client!.rename(trimmed);
    }
    emit(state.copyWith(playerName: trimmed));
  }

  // -- host ----------------------------------------------------------------

  Future<void> _onCreateLobby(
    CreateLobby event,
    Emitter<LobbyState> emit,
  ) async {
    if (state.playerId.isEmpty) return;
    await _teardownServices();

    final name = state.playerName.trim().isEmpty
        ? 'Player'
        : state.playerName.trim();
    final host = HostService(
      bridge: _bridge,
      playerId: state.playerId,
      playerName: name,
    );
    _host = host;
    _hostSnapSub = host.snapshots.listen((s) => add(HostSnapshotReceived(s)));
    _hostErrSub = host.errors.listen((m) => add(ServiceError(m)));
    _hostMatchSub = host.matchEvents.listen((e) => add(MatchEventReceived(e)));

    try {
      await host.startHosting(lobbyName: '$name\'s Lobby');
    } on Exception {
      await _teardownServices();
      if (!isClosed) {
        emit(state.copyWith(
          error: 'Could not start the lobby. Is the port already in use?',
        ));
      }
      return;
    }

    if (!isClosed) {
      emit(state.copyWith(
        role: NetworkRole.hosting,
        foundLobbies: const [],
        connecting: const {},
      ));
    }
  }

  void _onHostSnapshot(
    HostSnapshotReceived event,
    Emitter<LobbyState> emit,
  ) {
    if (isClosed) return;
    final snapshot = event.snapshot;
    final rtts = <String, int>{};
    for (final team in Team.all) {
      for (final slot in snapshot.room.slotsOf(team)) {
        if (!slot.isFilled || slot.playerId == state.playerId) continue;
        final rtt = snapshot.rttMsByPlayerId[slot.playerId];
        if (rtt != null && slot.playerId != null) rtts[slot.playerId!] = rtt;
      }
    }
    emit(state.copyWith(
      room: snapshot.room,
      rttMs: rtts,
      connecting: const {},
    ));
  }

  // -- client --------------------------------------------------------------

  Future<void> _onScanForLobbies(
    ScanForLobbies event,
    Emitter<LobbyState> emit,
  ) async {
    await _teardownServices();

    final client = ClientService(
      playerId: state.playerId,
      playerName: state.playerName,
    );
    _client = client;
    _clientSnapSub = client.snapshots.listen((s) => add(ClientSnapshotReceived(s)));
    _clientErrSub = client.errors.listen((m) => add(ServiceError(m)));
    _clientMatchSub = client.matchEvents.listen((e) => add(MatchEventReceived(e)));

    emit(state.copyWith(
      role: NetworkRole.scanning,
      foundLobbies: const [],
      clearRoom: true,
    ));

    final found = await client.discover();
    if (isClosed || state.role != NetworkRole.scanning) return;

    if (found.isEmpty) {
      emit(state.copyWith(
        role: NetworkRole.idle,
        error: 'No BlueLink Party rooms found on this network.',
      ));
      return;
    }

    emit(state.copyWith(foundLobbies: found));
  }

  Future<void> _onCancelScan(
    CancelScan event,
    Emitter<LobbyState> emit,
  ) async {
    await _teardownServices();
    emit(state.copyWith(
      role: NetworkRole.idle,
      foundLobbies: const [],
      clearRoom: true,
    ));
  }

  Future<void> _onJoinDiscovered(
    JoinDiscovered event,
    Emitter<LobbyState> emit,
  ) async {
    final client = _client;
    if (client == null) return;

    final error = await client.join(event.lobby);
    if (isClosed) return;

    if (error != null) {
      emit(state.copyWith(
        role: NetworkRole.idle,
        foundLobbies: const [],
        clearRoom: true,
        error: error,
      ));
      return;
    }

    emit(state.copyWith(
      role: NetworkRole.client,
      foundLobbies: const [],
    ));
  }

  void _onClientSnapshot(
    ClientSnapshotReceived event,
    Emitter<LobbyState> emit,
  ) {
    if (isClosed) return;
    final snapshot = event.snapshot;
    emit(state.copyWith(
      room: snapshot.room,
      hostRttMs: snapshot.rttMsByPlayerId['host'],
      connecting: const {},
    ));
  }

  // -- slots ---------------------------------------------------------------

  Future<void> _onClaimSlot(
    ClaimSlot event,
    Emitter<LobbyState> emit,
  ) async {
    final team = event.team;
    if (state.isHost && _host != null) {
      emit(state.copyWith(connecting: {...state.connecting, team}));
      final error = _host!.claimSlot(team);
      if (!isClosed) {
        emit(state.copyWith(
          connecting: state.connecting.difference({team}),
          error: error,
          clearError: error == null,
        ));
      }
      return;
    }

    if (state.isClient && _client != null) {
      emit(state.copyWith(connecting: {...state.connecting, team}));
      final error = await _client!.claimSlot(team);
      if (!isClosed) {
        emit(state.copyWith(
          connecting: state.connecting.difference({team}),
          error: error,
          clearError: error == null,
        ));
      }
    }
  }

  Future<void> _onReleaseSlot(
    ReleaseSlot event,
    Emitter<LobbyState> emit,
  ) async {
    if (state.isHost && _host != null) {
      final error = _host!.releaseSlot();
      emit(state.copyWith(error: error, clearError: error == null));
      return;
    }
    if (state.isClient && _client != null) {
      final error = _client!.releaseSlot();
      if (!isClosed) {
        emit(state.copyWith(error: error, clearError: error == null));
      }
    }
  }

  void _onKickMember(KickMember event, Emitter<LobbyState> emit) {
    if (state.isHost && _host != null) {
      emit(state.copyWith(error: _host!.kick(event.playerId)));
    } else if (state.isClient && _client != null) {
      _client!.kick(event.playerId);
    }
  }

  // -- lobby controls ------------------------------------------------------

  Future<void> _onSelectMode(
    SelectMode event,
    Emitter<LobbyState> emit,
  ) async {
    if (!state.isHost || _host == null) return;
    _host!.setMode(event.mode);
  }

  Future<void> _onStartMatch(
    StartMatch event,
    Emitter<LobbyState> emit,
  ) async {
    final host = _host;
    final room = state.room;
    if (host == null || room == null) return;

    if (!state.canStartMatch) {
      emit(state.copyWith(
        error:
            'Need ${room.selectedMode.minPlayers} players to start.',
      ));
      return;
    }

    final config = MatchConfig(
      mode: room.selectedMode,
      players: [
        for (final team in Team.all)
          for (final slot in room.slotsOf(team))
            if (slot.isFilled) slot,
      ],
    );
    final startEvent = MatchEvent(phase: GamePhase.countdown, config: config);
    _disposeGameSync();
    if (config.mode == GameMode.screenShift) {
      _matrixController = _buildHostMatrixController(config);
      emit(state.copyWith(matrixController: _matrixController));
    } else if (config.mode == GameMode.pixelFutbol) {
      _futbolController = _buildHostFutbolController(config);
      emit(state.copyWith(futbolController: _futbolController));
    } else {
      _gameSync = HostGameSyncAdapter(_host!, localPlayerId: state.playerId);
      emit(state.copyWith(gameSync: _gameSync));
    }
    host.pushMatchEvent(startEvent);
  }

  MatrixArenaController? _buildHostMatrixController(MatchConfig config) {
    final host = _host;
    if (host == null) return null;
    final rosterIds = [
      for (final slot in config.players) slot.playerId ?? '',
    ];
    final deviceIndex = rosterIds.indexOf(state.playerId);
    final transport = MatrixHostTransport(
      host,
      localPlayerId: state.playerId,
      rosterIds: rosterIds,
    );
    final controller = MatrixArenaController(
      matrix: MatrixLayoutManager()
          .matrixForPlayerCount(config.players.length),
      deviceCount: config.players.length,
      isHost: true,
      deviceIndex: deviceIndex < 0 ? 0 : deviceIndex,
      adapter: transport,
      calibrationDuration: 6,
      countdownDuration: 0,
    );
    transport.attach(controller);
    return controller;
  }

  FutbolMatchController? _buildHostFutbolController(MatchConfig config) {
    final host = _host;
    if (host == null) return null;
    final rosterIds = [
      for (final slot in config.players) slot.playerId ?? '',
    ];
    final deviceIndex = rosterIds.indexOf(state.playerId);
    final transport = FutbolHostTransport(
      host,
      rosterIds: rosterIds,
    );
    final controller = FutbolMatchController(
      matrix: MatrixLayoutManager()
          .matrixForPlayerCount(config.players.length),
      deviceCount: config.players.length,
      isHost: true,
      deviceIndex: deviceIndex < 0 ? 0 : deviceIndex,
      adapter: transport,
      teams: [for (final slot in config.players) slot.team],
    );
    transport.attach(controller);
    return controller;
  }

  void _onMatchEventReceived(
    MatchEventReceived event,
    Emitter<LobbyState> emit,
  ) {
    if (isClosed) return;
    final matchEvent = event.event;
    final isScreenShift = matchEvent.config.mode == GameMode.screenShift;
    final isFutbol = matchEvent.config.mode == GameMode.pixelFutbol;
    if (matchEvent.phase == GamePhase.countdown && state.isClient) {
      final rosterIds = [
        for (final slot in matchEvent.config.players) slot.playerId ?? '',
      ];
      if (isScreenShift && _client != null && _matrixController == null) {
        _matrixController = _buildClientMatrixController(matchEvent.config);
        emit(state.copyWith(matrixController: _matrixController));
      } else if (isFutbol && _client != null && _futbolController == null) {
        _futbolController = _buildClientFutbolController(
          matchEvent.config,
          rosterIds: rosterIds,
        );
        emit(state.copyWith(futbolController: _futbolController));
      } else if (!isScreenShift && !isFutbol && _client != null &&
          _gameSync == null) {
        _gameSync =
            ClientGameSyncAdapter(_client!, localPlayerId: state.playerId);
        emit(state.copyWith(gameSync: _gameSync));
      }
    }
    emit(state.copyWith(matchEvent: matchEvent));
  }

  MatrixArenaController? _buildClientMatrixController(MatchConfig config) {
    final client = _client;
    if (client == null) return null;
    final rosterIds = [
      for (final slot in config.players) slot.playerId ?? '',
    ];
    final deviceIndex = rosterIds.indexOf(state.playerId);
    final transport = MatrixClientTransport(
      client,
      localPlayerId: state.playerId,
      deviceIndex: deviceIndex < 0 ? 0 : deviceIndex,
    );
    final controller = MatrixArenaController(
      matrix: MatrixLayoutManager()
          .matrixForPlayerCount(config.players.length),
      deviceCount: config.players.length,
      isHost: false,
      deviceIndex: deviceIndex < 0 ? 0 : deviceIndex,
      adapter: transport,
      calibrationDuration: 6,
      countdownDuration: 0,
    );
    transport.attach(controller);
    return controller;
  }

  FutbolMatchController? _buildClientFutbolController(
    MatchConfig config, {
    required List<String> rosterIds,
  }) {
    final client = _client;
    if (client == null) return null;
    final deviceIndex = rosterIds.indexOf(state.playerId);
    final transport = FutbolClientTransport(
      client,
      playerId: state.playerId,
      deviceIndex: deviceIndex < 0 ? 0 : deviceIndex,
    );
    final controller = FutbolMatchController(
      matrix: MatrixLayoutManager()
          .matrixForPlayerCount(config.players.length),
      deviceCount: config.players.length,
      isHost: false,
      deviceIndex: deviceIndex < 0 ? 0 : deviceIndex,
      adapter: transport,
      teams: [for (final slot in config.players) slot.team],
    );
    transport.attach(controller);
    return controller;
  }

  Future<void> _onReturnToLobby(
    ReturnToLobby event,
    Emitter<LobbyState> emit,
  ) async {
    _disposeGameSync();
    emit(state.copyWith(
      clearMatchEvent: true,
      clearMatrix: true,
      clearFutbol: true,
    ));
  }

  void _disposeGameSync() {
    _gameSync?.dispose();
    _gameSync = null;
    _matrixController?.dispose();
    _matrixController = null;
    _futbolController?.dispose();
    _futbolController = null;
  }

  Future<void> _onRefreshNetwork(
    RefreshNetwork event,
    Emitter<LobbyState> emit,
  ) async {
    if (state.isHost && _host != null) {
      _host!.refresh();
    } else if (state.isClient && _client != null) {
      _client!.refresh();
    } else {
      await _bridge.refresh();
    }
  }

  Future<void> _onDisconnect(
    Disconnect event,
    Emitter<LobbyState> emit,
  ) async {
    await _teardownServices();
    emit(state.copyWith(
      role: NetworkRole.idle,
      clearRoom: true,
      foundLobbies: const [],
      rttMs: const {},
      clearHostRtt: true,
      connecting: const {},
    ));
  }

  Future<void> _onClearNotice(
    ClearNotice event,
    Emitter<LobbyState> emit,
  ) async {
    emit(state.copyWith(matchReady: false, clearError: true));
  }

  // -- shared --------------------------------------------------------------

  Future<void> _onServiceError(
    ServiceError event,
    Emitter<LobbyState> emit,
  ) async {
    if (isClosed) return;
    if (event.message == NetConstants.kickedMessage) {
      await _teardownServices();
      if (!isClosed) {
        emit(state.copyWith(
          role: NetworkRole.idle,
          error: event.message,
          foundLobbies: const [],
          clearRoom: true,
          rttMs: const {},
          clearHostRtt: true,
          connecting: const {},
        ));
      }
      return;
    }
    emit(state.copyWith(error: event.message));
  }

  void _onWifiStatus(WifiStatusChanged event, Emitter<LobbyState> emit) {
    if (isClosed) return;
    final status = event.status;
    if (status.ssid == state.ssid && status.isWifi == state.isWifi) return;
    emit(state.copyWith(ssid: status.ssid, isWifi: status.isWifi));
  }

  Future<void> _teardownServices() async {
    _disposeGameSync();
    await _hostSnapSub?.cancel();
    await _hostErrSub?.cancel();
    await _hostMatchSub?.cancel();
    await _clientSnapSub?.cancel();
    await _clientErrSub?.cancel();
    await _clientMatchSub?.cancel();
    _hostSnapSub = null;
    _hostErrSub = null;
    _hostMatchSub = null;
    _clientSnapSub = null;
    _clientErrSub = null;
    _clientMatchSub = null;

    final host = _host;
    _host = null;
    if (host != null) await host.dispose();

    final client = _client;
    _client = null;
    if (client != null) await client.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _host?.pause();
      _client?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _host?.resume();
      _client?.resume();
    }
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    await _wifiSub?.cancel();
    await _teardownServices();
    _bridge.dispose();
    return super.close();
  }
}
