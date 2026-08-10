import 'dart:async';
import 'dart:math';

import '../../../data/models/game_mode.dart';
import '../../../data/models/game_phase.dart';
import '../../../data/models/match_event.dart';
import '../../../data/models/team.dart';
import '../../../network/client_service.dart';
import '../../../network/protocol.dart';
import '../../features/game/bloc/game_bloc.dart';
import '../../features/game/bloc/game_event.dart';
import '../../features/game/domain/match_player.dart';
import '../../features/game/sync/game_sync_adapter.dart';
import '../../features/matrix_arena/domain/matrix_grid.dart';
import '../../features/matrix_arena/domain/matrix_snapshots.dart';
import '../../features/matrix_arena/game/matrix_arena_controller.dart';
import '../../features/matrix_arena/game/matrix_transport_sync.dart';
import '../../features/matrix_futbol/game/futbol_interpolation.dart';
import '../../features/matrix_futbol/game/futbol_match_controller.dart';
import '../../features/matrix_futbol/game/futbol_sync_adapter.dart';
import 'device_profile.dart';

/// One simulated rival device. It is a real [ClientService] joined to the
/// user's real lobby over loopback UDP, so every protocol edit in the app
/// applies here. During a match it mirrors the same controllers/sync
/// adapters a real client device would run and feeds bot input through the
/// same network channel a human thumb does.
class AppBot {
  AppBot({
    required this.client,
    required this.name,
    required this.profile,
  }) : playerId = client.playerId;

  final ClientService client;
  final String name;
  final String playerId;
  final VirtualDeviceProfile profile;

  bool joined = false;
  GameMode? mode;
  int deviceIndex = -1;

  MatrixArenaController? matrixController;
  MatrixClientTransport? _matrixTransport;

  FutbolMatchController? futbolController;
  FutbolClientTransport? _futbolTransport;

  GameBloc? battleBloc;
  ClientGameSyncAdapter? _battleAdapter;

  MatchEvent? lastEvent;
  bool get hasMirror =>
      matrixController != null ||
      futbolController != null ||
      battleBloc != null;

  void attachMatrixMirror({
    required TileMatrix matrix,
    required int deviceCount,
    required int deviceIndex,
    required MatrixClientTransport transport,
  }) {
    _disposeMirror();
    _matrixTransport = transport;
    matrixController = MatrixArenaController(
      matrix: matrix,
      deviceCount: deviceCount,
      isHost: false,
      deviceIndex: deviceIndex,
      adapter: transport,
      calibrationDuration: 6,
      countdownDuration: 0,
      random: Random(playerId.hashCode & 0x7fffffff),
    );
    transport.attach(matrixController!);
  }

  void attachFutbolMirror({
    required TileMatrix matrix,
    required int deviceCount,
    required int deviceIndex,
    required FutbolClientTransport transport,
  }) {
    _disposeMirror();
    _futbolTransport = transport;
    futbolController = FutbolMatchController(
      matrix: matrix,
      deviceCount: deviceCount,
      isHost: false,
      deviceIndex: deviceIndex,
      adapter: transport,
    );
    transport.attach(futbolController!);
  }

  void attachBattleMirror(ClientGameSyncAdapter adapter) {
    _disposeMirror();
    _battleAdapter = adapter;
    battleBloc = GameBloc(sync: adapter);
  }

  /// Runs one tick of bot intelligence on the mirrored world, sending input
  /// exactly like a real player device would.
  void step(double dt) {
    final matrix = matrixController;
    if (matrix != null && matrix.phase != MatrixMatchPhase.calibrating) {
      final frame = matrix.renderFrame();
      final players = frame.players;
      if (players.isNotEmpty) {
        final me = frame.players[deviceIndex % players.length];
        final enemy = frame.players[(deviceIndex + 1) % players.length];
        final dx = enemy.x - me.x;
        final dy = enemy.y - me.y;
        final dist = sqrt(dx * dx + dy * dy);
        final aimX = dist == 0 ? 0 : dx / dist;
        final aimY = dist == 0 ? 0 : dy / dist;
        final wander = Random(playerId.hashCode).nextDouble();
        matrix.setLocalInput(
          moveX: aimX * 0.85 + sin(wander + deviceIndex) * 0.3,
          moveY: aimY * 0.85 + cos(wander + deviceIndex) * 0.3,
          firing: true,
        );
      }
      matrix.step(dt);
      return;
    }

    final futbol = futbolController;
    if (futbol != null &&
        futbol.phase != FutbolMatchPhase.calibrating) {
      final frame = futbol.renderFrame();
      final controller = futbol;
      final myIndex = deviceIndex;
      final myPlayer = frame.players[myIndex];
      final isHome = myIndex.isEven;

      var targetX = frame.ballX;
      var targetY = frame.ballY;
      if (frame.phase != FutbolMatchPhase.playing) {
        targetX = controller.matrix.worldWidth * (isHome ? 0.24 : 0.76);
        targetY = controller.matrix.worldHeight / 2;
      }

      final px = myPlayer.x;
      final py = myPlayer.y;
      final dx = targetX - px;
      final dy = targetY - py;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 1e-3) {
        controller.setLocalInput(
          moveX: dx / dist,
          moveY: dy / dist,
          firing: dist < 70 && futbol.phase == FutbolMatchPhase.playing,
        );
      }
      futbol.step(dt);
      return;
    }

    final battle = battleBloc;
    if (battle != null) {
      final state = battle.state;
      if (state.phase == GamePhase.inGame && state.players.isNotEmpty) {
        MatchPlayer? me;
        for (final p in state.players) {
          if (p.id == playerId) {
            me = p;
            break;
          }
        }
        if (me != null) {
          final myPlayer = me;
          MatchPlayer? enemy;
          for (final p in state.players) {
            if (p.team != myPlayer.team && p.alive) {
              enemy = p;
              break;
            }
          }
          enemy ??= state.players.firstWhere(
            (p) => p.team != myPlayer.team,
            orElse: () => state.players.first,
          );
          final dx = enemy.x - myPlayer.x;
          final dy = enemy.y - myPlayer.y;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist > 1e-3) {
            _battleAdapter?.sendInput(
              moveX: dx / dist,
              moveY: dy / dist,
              firing: true,
            );
          }
        }
      }
    }
  }

  void _disposeMirror() {
    _matrixTransport?.dispose();
    _matrixTransport = null;
    matrixController?.dispose();
    matrixController = null;
    _futbolTransport?.dispose();
    _futbolTransport = null;
    futbolController?.dispose();
    futbolController = null;
    _battleAdapter?.dispose();
    _battleAdapter = null;
    battleBloc?.close();
    battleBloc = null;
  }

  void dispose() {
    _disposeMirror();
    client.dispose();
  }
}

/// The whole-app bot neighbourhood: real client devices that join the user's
/// real lobby (whenever the user hosts one), pick the free seats, and follow
/// the host into whatever match mode the user chooses.
class AppBotSwarm {
  AppBotSwarm({required this.botCount, this.requiredLobbyName});

  final int botCount;

  /// When set, bots only join a lobby whose name matches (used by loopback
  /// tests so a swarm never intrudes into other concurrent test lobbies).
  final String? requiredLobbyName;

  final List<AppBot> bots = [];
  bool _disposed = false;
  Timer? _discoveryTimer;

  int get joinedCount => bots.where((b) => b.joined).length;

  Future<void> start() async {
    final sizes = VirtualDeviceProfile.defaults;
    for (var i = 0; i < botCount; i++) {
      final client = ClientService(
        playerId: 'bot-${i + 1}',
        playerName: 'Bot ${i + 1}',
      );
      bots.add(AppBot(
        client: client,
        name: 'Bot ${i + 1}',
        profile: sizes[(i + 1) % sizes.length],
      ));
    }
    _discoveryTimer = Timer.periodic(
      const Duration(milliseconds: 1800),
      (_) => _pollLobby(),
    );
  }

  Future<void> _pollLobby() async {
    if (_disposed) return;
    for (final bot in bots.where((b) => !b.joined)) {
      try {
        final found = await bot.client.discover();
        if (found.isEmpty) continue;
        final wanted = found.where((l) =>
            requiredLobbyName == null || l.lobbyName == requiredLobbyName);
        if (wanted.isEmpty) continue;
        final lobby = wanted.length > 1
            ? wanted.firstWhere(
                (l) => l.hostPort != NetConstants.hostPort,
                orElse: () => wanted.first,
              )
            : wanted.first;
        final error = await bot.client.join(lobby).timeout(
              const Duration(seconds: 6),
            );
        if (error != null) continue;
        final botIndex = bots.indexOf(bot);
        final teamErr = await bot.client
            .claimSlot(botIndex.isEven ? Team.blue : Team.red)
            .timeout(const Duration(seconds: 6));
        if (teamErr != null) continue;
        bot.joined = true;
        bot.client.matchEvents.listen((event) {
          if (_disposed) return;
          _onMatchEvent(bot, event);
        });
      } catch (_) {
        // Next poll will retry.
      }
    }
  }

  void _onMatchEvent(AppBot bot, MatchEvent event) {
    if (event.phase != GamePhase.countdown) return;
    if (bot.lastEvent == event) return;
    bot.lastEvent = event;
    final mode = event.config.mode;
    final rosterIds = [
      for (final slot in event.config.players) slot.playerId ?? '',
    ];
    final deviceIndex = rosterIds.indexOf(bot.playerId);
    final matrix = MatrixLayoutManager()
        .matrixForPlayerCount(event.config.players.length);
    bot.mode = mode;
    bot.deviceIndex = deviceIndex < 0 ? 0 : deviceIndex;

    switch (mode) {
      case GameMode.screenShift:
        final transport = MatrixClientTransport(
          bot.client,
          localPlayerId: bot.playerId,
          deviceIndex: bot.deviceIndex,
        );
        bot.attachMatrixMirror(
          matrix: matrix,
          deviceCount: event.config.players.length,
          deviceIndex: bot.deviceIndex,
          transport: transport,
        );
      case GameMode.pixelFutbol:
        final transport = FutbolClientTransport(
          bot.client,
          playerId: bot.playerId,
          deviceIndex: bot.deviceIndex,
        );
        bot.attachFutbolMirror(
          matrix: matrix,
          deviceCount: event.config.players.length,
          deviceIndex: bot.deviceIndex,
          transport: transport,
        );
      case GameMode.battleSync:
        bot.attachBattleMirror(
          ClientGameSyncAdapter(bot.client, localPlayerId: bot.playerId),
        );
        bot.battleBloc?.add(MatchStarted(
          event,
          localPlayerId: bot.playerId,
        ));
    }
  }

  /// Advances all bot devices (AI + mirror interpolation). Call from any
  /// persistent ticker, match or not.
  void tick(double dt) {
    for (final bot in bots) {
      bot.step(dt);
    }
  }

  void dispose() {
    _disposed = true;
    _discoveryTimer?.cancel();
    for (final bot in bots) {
      bot.dispose();
    }
    bots.clear();
  }
}