import 'dart:async';
import 'dart:math';

import 'package:flutter/painting.dart';

import '../../../data/models/game_mode.dart';
import '../../../data/models/game_phase.dart';
import '../../../data/models/match_config.dart';
import '../../../data/models/match_event.dart';
import '../../../data/models/player_slot.dart';
import '../../../data/models/team.dart';
import '../../features/game/bloc/game_bloc.dart';
import '../../features/game/bloc/game_event.dart';
import '../../features/game/domain/match_player.dart';
import '../../features/game/sync/game_snapshot.dart';
import '../../features/game/sync/game_sync_adapter.dart';
import '../../features/matrix_arena/demo/matrix_memory_bus.dart';
import '../../features/matrix_arena/domain/matrix_grid.dart';
import '../../features/matrix_arena/domain/matrix_snapshots.dart';
import '../../features/matrix_arena/game/matrix_arena_controller.dart';
import '../../features/matrix_arena/game/matrix_viewport.dart';
import '../../features/matrix_futbol/game/futbol_interpolation.dart';
import '../../features/matrix_futbol/game/futbol_match_controller.dart';
import '../lab/futbol_device_lab.dart' show FutbolMemoryBus;
import 'device_profile.dart';

/// One lane of a solo session (the human device or one bot device).
class SoloDevice {
  SoloDevice({
    required this.name,
    required this.isHuman,
    required this.profile,
    required this.deviceIndex,
    required this.team,
  });

  final String name;
  final bool isHuman;
  final VirtualDeviceProfile profile;
  final int deviceIndex;
  final Team team;

  MatrixArenaController? matrixController;
  FutbolMatchController? futbolController;
}

/// A fully local 1-vs-bots session: the human plays the real game screen
/// (whole-arena view) while [bots] are memory-bus mirrors driven by the same
/// AI the device labs use. No sockets are bound.
class SoloSession {
  SoloSession({
    required this.mode,
    required this.playerCount,
    this.humanDeviceIndex = 0,
    this.seed = 1,
  });

  final GameMode mode;
  final int playerCount;

  /// The human always gets index 0; the bots fill the remaining indexes.
  final int humanDeviceIndex;
  final int seed;

  late TileMatrix matrix;
  late final List<SoloDevice> devices = [];

  // Futbol
  FutbolMemoryBus? _futbolBus;
  FutbolMatchController? _futbolHost;

  // Screen shift
  MatrixMemoryBus? _matrixBus;
  MatrixArenaController? _matrixHost;

  // Battle sync (host GameBloc only; bots are remote players in its sim).
  SoloBattleBus? _battleBus;
  GameBloc? _battleHost;
  MatchEvent? _battleEvent;

  bool _started = false;

  FutbolMatchController? get futbolHost => _futbolHost;
  MatrixArenaController? get matrixHost => _matrixHost;
  GameBloc? get battleHost => _battleHost;
  List<SoloDevice> get bots =>
      devices.where((d) => !d.isHuman).toList();

  bool get isOver {
    final host = _futbolHost;
    if (host != null) return host.isMatchOver;
    final matrix = _matrixHost;
    if (matrix != null) return matrix.isMatchOver;
    final battle = _battleHost;
    if (battle != null && _battleEvent != null) {
      return battle.state.phase == GamePhase.matchResult;
    }
    return false;
  }

  /// In solo play every device sees the whole arena, not its own tile.
  MatrixViewportCamera fullArenaCamera(Size screenSize) {
    final tile = MatrixTileLayout(
      deviceIndex: 0,
      column: 0,
      row: 0,
      columns: 1,
      rows: 1,
      tileWidth: matrix.worldWidth,
      tileHeight: matrix.worldHeight,
    );
    return MatrixViewportCamera(tile: tile, screenSize: screenSize);
  }

  void start() {
    if (_started) return;
    _started = true;
    matrix = MatrixLayoutManager().matrixForPlayerCount(playerCount);
    _buildDevices();
    switch (mode) {
      case GameMode.pixelFutbol:
        _startFutbol();
      case GameMode.screenShift:
        _startMatrix();
      case GameMode.battleSync:
        _startBattle();
    }
  }

  void _buildDevices() {
    final sizes = VirtualDeviceProfile.defaults;
    for (var i = 0; i < playerCount; i++) {
      final isHuman = i == humanDeviceIndex;
      devices.add(SoloDevice(
        name: isHuman ? 'You' : 'Bot $i',
        isHuman: isHuman,
        profile: sizes[i % sizes.length],
        deviceIndex: i,
        // Parity maps to arena/futbol teams: odd = blue, even = red. With 3
        // devices the human sits on blue (index 1) against two red bots: 2v1.
        team: i.isEven ? Team.red : Team.blue,
      ));
    }
  }

  FutbolRules _futbolRules() => FutbolRules(
        calibrationSeconds: 1,
        countdownSeconds: 3,
        celebrationSeconds: 1.6,
        matchDurationSeconds: 999,
        scoreLimit: 5,
      );

  void _startFutbol() {
    final bus = FutbolMemoryBus(hostController: null);
    _futbolBus = bus;
    final host = FutbolMatchController(
      matrix: matrix,
      deviceCount: playerCount,
      isHost: true,
      deviceIndex: humanDeviceIndex,
      rules: _futbolRules(),
      adapter: bus,
    );
    _futbolHost = host;
    host.start();
    devices[humanDeviceIndex].futbolController = host;

    for (var i = 0; i < playerCount; i++) {
      if (i == humanDeviceIndex) continue;
      final client = FutbolMatchController(
        matrix: matrix,
        deviceCount: playerCount,
        isHost: false,
        deviceIndex: i,
        rules: _futbolRules(),
        adapter: bus,
      );
      bus.addClient(client);
      devices[i].futbolController = client;
    }
  }

  void _startMatrix() {
    final bus = MatrixMemoryBus(hostController: null, clients: []);
    _matrixBus = bus;
    final host = MatrixArenaController(
      matrix: matrix,
      deviceCount: playerCount,
      isHost: true,
      deviceIndex: humanDeviceIndex,
      adapter: bus,
      calibrationDuration: 1,
      countdownDuration: 1,
      random: Random(seed),
    );
    _matrixHost = host;
    devices[humanDeviceIndex].matrixController = host;

    for (var i = 0; i < playerCount; i++) {
      if (i == humanDeviceIndex) continue;
      final client = MatrixArenaController(
        matrix: matrix,
        deviceCount: playerCount,
        isHost: false,
        deviceIndex: i,
        adapter: bus,
        calibrationDuration: 1,
        countdownDuration: 1,
        random: Random(seed + i),
      );
      bus.addClient(client);
      devices[i].matrixController = client;
    }
  }

  void _startBattle() {
    final config = MatchConfig(
      mode: GameMode.battleSync,
      matchDuration: const Duration(minutes: 3),
      players: [
        for (final device in devices)
          PlayerSlot(
            team: device.team,
            seat: device.team == Team.red
                ? devices.where((d) => d.team == Team.red)
                    .toList()
                    .indexOf(device)
                : 0,
            playerId: device.isHuman ? 'you' : device.name,
            playerName: device.name,
          ),
      ],
    );
    _battleEvent = MatchEvent(phase: GamePhase.countdown, config: config);
    final bus = SoloBattleBus(
      localPlayerId: 'you',
      rosterIds: [
        for (final device in devices)
          device.isHuman ? 'you' : device.name,
      ],
    );
    _battleBus = bus;
    final host = GameBloc(sync: bus);
    _battleHost = host;
    host.add(MatchStarted(_battleEvent!, localPlayerId: 'you'));
  }

  void step(double dt) {
    _futbolHost?.step(dt);
    _matrixHost?.step(dt);
  }

  /// Steps + drives AI only the bot devices; the human's own controller is
  /// driven by their real game screen (its own ticker + joystick).
  void stepBots(double dt) {
    for (final bot in bots) {
      _driveBot(bot, dt);
    }
  }

  void _driveBot(SoloDevice bot, double dt) {
    final futbol = bot.futbolController;
    if (futbol != null && futbol.phase != FutbolMatchPhase.calibrating) {
      final frame = futbol.renderFrame();
      final myIndex = bot.deviceIndex;
      if (frame.players.length <= myIndex) return;
      final myPlayer = frame.players[myIndex];
      final isHome = myIndex.isEven;
      var targetX = frame.ballX;
      var targetY = frame.ballY;
      if (frame.phase != FutbolMatchPhase.playing) {
        targetX = futbol.matrix.worldWidth * (isHome ? 0.24 : 0.76);
        targetY = futbol.matrix.worldHeight / 2;
      }
      final dx = targetX - myPlayer.x;
      final dy = targetY - myPlayer.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 1e-3) {
        futbol.setLocalInput(
          moveX: dx / dist,
          moveY: dy / dist,
          firing: dist < 70 && futbol.phase == FutbolMatchPhase.playing,
        );
      }
      futbol.step(dt);
      return;
    }

    final matrix = bot.matrixController;
    if (matrix != null && matrix.phase != MatrixMatchPhase.calibrating) {
      final frame = matrix.renderFrame();
      final players = frame.players;
      if (players.length < 2) return;
      final me = players[bot.deviceIndex % players.length];
      final enemy = players[(bot.deviceIndex + 1) % players.length];
      final dx = enemy.x - me.x;
      final dy = enemy.y - me.y;
      final dist = sqrt(dx * dx + dy * dy);
      final aimX = dist == 0 ? 0 : dx / dist;
      final aimY = dist == 0 ? 0 : dy / dist;
      final wander = Random(seed * 100 + bot.deviceIndex).nextDouble();
      matrix.setLocalInput(
        moveX: aimX * 0.85 + sin(wander * 6.28 + bot.deviceIndex) * 0.3,
        moveY: aimY * 0.85 + cos(wander * 6.28 + bot.deviceIndex) * 0.3,
        firing: true,
      );
      matrix.step(dt);
      return;
    }

    final bus = _battleBus;
    final battle = _battleHost;
    if (bus != null && battle != null) {
      final state = battle.state;
      if (state.phase == GamePhase.inGame && state.players.isNotEmpty) {
        MatchPlayer? me;
        for (final p in state.players) {
          if (p.id == (bot.isHuman ? 'you' : bot.name)) {
            me = p;
            break;
          }
        }
        if (me != null) {
          final myTeam = me.team;
          final myX = me.x;
          final myY = me.y;
          MatchPlayer? enemy;
          for (final p in state.players) {
            if (p.team != myTeam && p.alive) {
              enemy = p;
              break;
            }
          }
          enemy ??= state.players.firstWhere(
            (p) => p.team != myTeam,
            orElse: () => state.players.first,
          );
          final dx = enemy.x - myX;
          final dy = enemy.y - myY;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist > 1e-3) {
            bus.driveBotInput(
              bot.deviceIndex,
              moveX: dx / dist,
              moveY: dy / dist,
              firing: true,
            );
          }
        }
      }
    }
  }

  void dispose() {
    _futbolBus?.dispose();
    _matrixBus?.dispose();
    _battleBus?.dispose();
    _battleHost?.close();
    for (final device in devices) {
      if (device.matrixController != null) device.matrixController!.dispose();
      if (device.futbolController != null) device.futbolController!.dispose();
    }
    devices.clear();
    _started = false;
  }
}

/// Memory adapter that makes bot players real participants of the host
/// GameBloc sim: their remote inputs are fed straight into the host, exactly
/// like RemoteInputEvents from a wire client would be. The host reports
/// itself authoritative because it IS the simulation.
class SoloBattleBus implements GameSyncAdapter {
  SoloBattleBus({required this.localPlayerId, required List<String> rosterIds})
      : _rosterIds = List.of(rosterIds);

  @override
  final String localPlayerId;
  final List<String> _rosterIds;

  final StreamController<GameSyncEvent> _sink =
      StreamController<GameSyncEvent>.broadcast();

  /// Called by the solo session AI to move a bot player.
  void driveBotInput(
    int botIndex, {
    required double moveX,
    required double moveY,
    bool firing = true,
  }) {
    _sink.add(RemoteInputEvent(
      playerId: _rosterIds[botIndex],
      moveX: moveX,
      moveY: moveY,
      firing: firing,
    ));
  }

  @override
  bool get isHost => true;

  @override
  Stream<GameSyncEvent> get events => _sink.stream;

  @override
  void broadcastSnapshot(GameSnapshot snapshot) {}

  @override
  void sendInput({required double moveX, required double moveY, required bool firing}) {}

  @override
  void sendReady({required String playerId, required bool ready}) {}

  @override
  void sendCommand(GameCommand command) {}

  @override
  void dispose() {
    _sink.close();
  }
}