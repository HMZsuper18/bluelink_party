import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/game_phase.dart';
import '../../../data/models/match_config.dart';
import '../../../data/models/player_slot.dart';
import '../../../data/models/team.dart';
import '../domain/match_player.dart';
import '../domain/match_projectile.dart';
import '../sync/game_snapshot.dart';
import '../sync/game_sync_adapter.dart';
import 'game_event.dart';
import 'game_state.dart';

class GameBloc extends Bloc<GameEvent, GameState> {
  GameBloc({GameSyncAdapter? sync})
      : _sync = sync ?? NoopGameSyncAdapter(localPlayerId: ''),
        super(const GameState()) {
    on<MatchStarted>(_onMatchStarted);
    on<CountdownTick>(_onCountdownTick);
    on<CountdownFinished>(_onCountdownFinished);
    on<PlayerInputChanged>(_onPlayerInputChanged);
    on<MatchTick>(_onMatchTick);
    on<MatchOver>(_onMatchOver);
    on<PauseMatch>(_onPauseMatch);
    on<PlayerReadyChanged>(_onPlayerReadyChanged);
    on<ResumeMatch>(_onResumeMatch);
    on<RestartMatch>(_onRestartMatch);
    on<ReturnToLobby>(_onReturnToLobby);
    on<RemoteInputApplied>(_onRemoteInputApplied);
    on<RemoteStateApplied>(_onRemoteStateApplied);

    _syncSub = _sync.events.listen(_onSyncEvent);
  }

  static const Duration _countdownInterval = Duration(seconds: 1);
  static const Duration _matchTickInterval = Duration(milliseconds: 50);

  /// Cadence the host re-broadcasts the frozen paused state so every device
  /// reliably converges on the same `isPaused: true` frame (UDP can drop the
  /// single broadcast that otherwise follows a pause request).
  static const Duration _pauseBroadcastInterval = Duration(milliseconds: 250);

  static const double _playerSpeed = 240;
  static const double _projectileSpeed = 900;
  static const double _projectileRadius = 5;
  static const double _projectileDamage = 25;
  static const double _projectileLife = 3;
  static const double _fireCooldown = 0.38;

  static const double _buffRadiusFactor = 1.4;
  static const int _buffHealthBonus = 50;
  static const double _buffDamageMultiplier = 1.5;

  final GameSyncAdapter _sync;
  StreamSubscription<GameSyncEvent>? _syncSub;

  Timer? _countdownTimer;
  Timer? _matchTimer;
  Timer? _pauseTimer;

  MatchConfig? _activeConfig;
  String _localPlayerId = '';
  double _moveX = 0;
  double _moveY = 0;
  bool _firing = false;
  int _projectileSeq = 0;

  final Map<String, ({double moveX, double moveY, bool firing})> _remoteInputs =
      {};
  final Map<String, double> _fireCooldowns = {};

  /// The host owns the authoritative simulation; clients are replicas.
  bool get _isAuthoritative => _sync.isHost;

  /// Exposed for the sync-status overlay: hosts run/author the world and
  /// broadcast; clients replay the host's snapshots.
  bool get isAuthoritative => _isAuthoritative;

  void _onSyncEvent(GameSyncEvent event) {
    switch (event) {
      case RemoteInputEvent e:
        add(RemoteInputApplied(
          playerId: e.playerId,
          moveX: e.moveX,
          moveY: e.moveY,
          firing: e.firing,
        ));
      case RemoteReadyEvent e:
        add(PlayerReadyChanged(e.playerId, ready: e.ready));
      case RemoteCommandEvent e:
        switch (e.command) {
          case GameCommand.pause:
            add(const PauseMatch());
          case GameCommand.resume:
            add(const ResumeMatch());
          case GameCommand.restart:
            add(const RestartMatch());
          case GameCommand.quit:
            add(const ReturnToLobby());
        }
      case RemoteSnapshotEvent e:
        add(RemoteStateApplied(e.snapshot));
    }
  }

  @override
  void onTransition(transition) {
    super.onTransition(transition);
    final next = transition.nextState;
    if (_isAuthoritative && next.phase != GamePhase.lobby) {
      _sync.broadcastSnapshot(_snapshotOf(next));
    }
  }

  void _onMatchStarted(MatchStarted event, Emitter<GameState> emit) {
    _stopMatchTimers();
    _resetLocalInput();
    _localPlayerId = event.localPlayerId;
    _activeConfig = event.event.config;
    final config = event.event.config;
    emit(state.copyWith(
      phase: GamePhase.countdown,
      config: config,
      remainingSeconds: config.countdownSeconds,
      elapsedMs: 0,
      redScore: 0,
      blueScore: 0,
      clearOutcome: true,
      isPaused: false,
      readyPlayerIds: const <String>{},
      players: const <MatchPlayer>[],
      projectiles: const <MatchProjectile>[],
    ));
    if (_isAuthoritative) {
      _countdownTimer = Timer.periodic(_countdownInterval, (_) {
        add(const CountdownTick());
      });
    }
  }

  void _onCountdownTick(CountdownTick event, Emitter<GameState> emit) {
    if (state.phase != GamePhase.countdown) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }
    final next = state.remainingSeconds - 1;
    if (next <= 0) {
      add(const CountdownFinished());
    } else {
      emit(state.copyWith(remainingSeconds: next));
    }
  }

  void _onCountdownFinished(CountdownFinished event, Emitter<GameState> emit) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final config = state.config;
    final players = _spawnPlayers(config);
    emit(state.copyWith(
      phase: GamePhase.inGame,
      remainingSeconds: 0,
      matchDurationMs: (config?.matchDuration ?? const Duration(seconds: 90)).inMilliseconds,
      players: players,
      projectiles: const <MatchProjectile>[],
    ));
    if (_isAuthoritative) {
      _startMatchTimer();
    }
  }

  List<MatchPlayer> _spawnPlayers(MatchConfig? config) {
    final width = config?.viewportWidth ?? MatchConfig.defaultViewportWidth;
    final height = config?.viewportHeight ?? MatchConfig.defaultViewportHeight;
    final slots = config?.players ?? const <PlayerSlot>[];
    final random = Random(config?.seed ?? 0);

    var players = <MatchPlayer>[];
    if (slots.isEmpty) {
      players = _spawnDefaultRoster(width, height, random);
    } else {
      for (var i = 0; i < slots.length; i++) {
        final slot = slots[i];
        final playerId = slot.playerId ?? 'p$i';
        players.add(
          _matchPlayerFromSlot(
            playerId: playerId,
            slot: slot,
            width: width,
            height: height,
            jitter: random.nextDouble(),
          ),
        );
      }
    }

    if (players.isEmpty) return players;

    final localIndex = _localPlayerId.isEmpty
        ? 0
        : players.indexWhere((p) => p.id == _localPlayerId);
    final local = localIndex < 0 ? 0 : localIndex;
    players[local] = players[local].copyWith(isLocal: true);

    return _applyHandicap(players);
  }

  List<MatchPlayer> _spawnDefaultRoster(
    double width,
    double height,
    Random random,
  ) {
    return [
      _matchPlayerAt(
        id: 'red0',
        name: 'Red 0',
        team: Team.red,
        x: width * (0.16 + 0.02 * random.nextDouble()),
        y: height * 0.35,
        facingX: 1,
        facingY: 0,
      ),
      _matchPlayerAt(
        id: 'red1',
        name: 'Red 1',
        team: Team.red,
        x: width * (0.16 + 0.02 * random.nextDouble()),
        y: height * 0.65,
        facingX: 1,
        facingY: 0,
      ),
      _matchPlayerAt(
        id: 'blue0',
        name: 'Blue 0',
        team: Team.blue,
        x: width * (0.84 - 0.02 * random.nextDouble()),
        y: height * 0.35,
        facingX: -1,
        facingY: 0,
      ),
      _matchPlayerAt(
        id: 'blue1',
        name: 'Blue 1',
        team: Team.blue,
        x: width * (0.84 - 0.02 * random.nextDouble()),
        y: height * 0.65,
        facingX: -1,
        facingY: 0,
      ),
    ];
  }

  MatchPlayer _matchPlayerFromSlot({
    required String playerId,
    required PlayerSlot slot,
    required double width,
    required double height,
    required double jitter,
  }) {
    final isRed = slot.team == Team.red;
    final seatOffset = slot.seat % 2 == 0 ? 0.0 : 0.3;
    return _matchPlayerAt(
      id: playerId,
      name: slot.playerName ?? 'Player',
      team: slot.team,
      x: isRed
          ? width * (0.16 + 0.02 * jitter)
          : width * (0.84 - 0.02 * jitter),
      y: height * (0.35 + seatOffset),
      facingX: isRed ? 1 : -1,
      facingY: 0,
    );
  }

  MatchPlayer _matchPlayerAt({
    required String id,
    required String name,
    required Team team,
    required double x,
    required double y,
    required double facingX,
    required double facingY,
  }) {
    return MatchPlayer(
      id: id,
      name: name,
      team: team,
      x: x,
      y: y,
      facingX: facingX,
      facingY: facingY,
      isLocal: false,
    );
  }

  List<MatchPlayer> _applyHandicap(List<MatchPlayer> players) {
    final redCount = players.where((p) => p.team == Team.red).length;
    final blueCount = players.where((p) => p.team == Team.blue).length;
    if (redCount == blueCount) return players;

    final buffed = redCount < blueCount ? Team.red : Team.blue;
    return [
      for (final p in players)
        if (p.team == buffed)
          p.copyWith(
            hp: p.hp + _buffHealthBonus,
            maxHp: p.maxHp + _buffHealthBonus,
            radius: p.radius * _buffRadiusFactor,
            damageMultiplier: _buffDamageMultiplier,
          )
        else
          p,
    ];
  }

  void _onPlayerInputChanged(
    PlayerInputChanged event,
    Emitter<GameState> emit,
  ) {
    if (!_isAuthoritative) {
      _sync.sendInput(
        moveX: event.moveX,
        moveY: event.moveY,
        firing: event.firing,
      );
      return;
    }
    _moveX = event.moveX;
    _moveY = event.moveY;
    _firing = event.firing;
  }

  void _onMatchTick(MatchTick event, Emitter<GameState> emit) {
    if (state.phase != GamePhase.inGame || !_isAuthoritative) return;
    if (state.isPaused) return;
    final tickMs = _matchTickInterval.inMilliseconds;
    final tickSeconds = tickMs / 1000;

    var players = <MatchPlayer>[];
    var projectiles = List<MatchProjectile>.from(state.projectiles);

    for (final p in state.players) {
      final isLocal = p.isLocal;
      final input = isLocal
          ? (moveX: _moveX, moveY: _moveY, firing: _firing)
          : (_remoteInputs[p.id] ?? (moveX: 0.0, moveY: 0.0, firing: false));

      var next = p;
      final mag = sqrt(input.moveX * input.moveX + input.moveY * input.moveY);
      if (mag > 0.001 && p.alive) {
        final nx = input.moveX / mag;
        final ny = input.moveY / mag;
        next = p.copyWith(
          x: p.x + nx * _playerSpeed * tickSeconds,
          y: p.y + ny * _playerSpeed * tickSeconds,
          facingX: nx,
          facingY: ny,
        );
      }
      final clamped = _clampPlayer(next);

      var cooldown = _fireCooldowns[p.id] ?? 0;
      if (clamped.alive && input.firing && cooldown <= 0) {
        projectiles = [...projectiles, _makeProjectile(clamped)];
        cooldown = _fireCooldown;
      } else if (cooldown > 0) {
        cooldown = max(0, cooldown - tickSeconds);
      }
      _fireCooldowns[p.id] = cooldown;

      players.add(clamped);
    }

    players = _resolvePlayerCollisions(players);

    final moved = <MatchProjectile>[];
    for (final pr in projectiles) {
      moved.add(
        pr.copyWith(
          x: pr.x + pr.vx * tickSeconds,
          y: pr.y + pr.vy * tickSeconds,
          life: pr.life - tickSeconds,
        ),
      );
    }
    final arena = _arena();
    projectiles = moved
        .where((pr) => pr.life > 0 && _insideArena(pr, arena))
        .toList();

    var redScore = state.redScore;
    var blueScore = state.blueScore;
    final remaining = <MatchProjectile>[];
    for (final pr in projectiles) {
      MatchPlayer? defender;
      for (final p in players) {
        if (!p.alive || p.team == pr.ownerTeam) continue;
        if (_overlaps(p, pr)) {
          defender = p;
          break;
        }
      }
      if (defender == null) {
        remaining.add(pr);
        continue;
      }
      final hit = defender;
      final nhp = max(0, hit.hp - pr.damage.round());
      final index = players.indexWhere((p) => p.id == hit.id);
      players[index] = hit.copyWith(hp: nhp, alive: nhp > 0);
    }
    projectiles = remaining;

    final elapsedMs = state.elapsedMs + tickMs;
    final redAlive = players.where((p) => p.team == Team.red && p.alive).length;
    final blueAlive =
        players.where((p) => p.team == Team.blue && p.alive).length;
    final localTeam = players.firstWhere((p) => p.isLocal).team;

    if (elapsedMs >= state.matchDurationMs) {
      _stopMatchTimers();
      emit(state.copyWith(
        phase: GamePhase.matchResult,
        outcome: MatchOutcome.draw,
        elapsedMs: elapsedMs,
        players: players,
        projectiles: projectiles,
        redScore: redScore,
        blueScore: blueScore,
      ));
      return;
    }

    if (redAlive == 0 || blueAlive == 0) {
      _stopMatchTimers();
      final winnerTeam = redAlive > 0 ? Team.red : Team.blue;
      if (winnerTeam == Team.red) {
        redScore++;
      } else {
        blueScore++;
      }
      final won = localTeam == winnerTeam;
      emit(state.copyWith(
        phase: GamePhase.matchResult,
        outcome: won ? MatchOutcome.victory : MatchOutcome.defeat,
        elapsedMs: elapsedMs,
        players: players,
        projectiles: projectiles,
        redScore: redScore,
        blueScore: blueScore,
      ));
      return;
    }

    emit(state.copyWith(
      elapsedMs: elapsedMs,
      players: players,
      projectiles: projectiles,
      redScore: redScore,
      blueScore: blueScore,
    ));
  }

  MatchProjectile _makeProjectile(MatchPlayer p) {
    final offset = p.radius + _projectileRadius + 2;
    return MatchProjectile(
      id: 'proj_${p.id}_${++_projectileSeq}',
      ownerTeam: p.team,
      x: p.x + p.facingX * offset,
      y: p.y + p.facingY * offset,
      vx: p.facingX * _projectileSpeed,
      vy: p.facingY * _projectileSpeed,
      life: _projectileLife,
      damage: _projectileDamage * p.damageMultiplier,
    );
  }

  MatchPlayer _clampPlayer(MatchPlayer p) {
    final arena = _arena();
    final minX = arena.left + p.radius;
    final minY = arena.top + p.radius;
    final maxX = arena.right - p.radius;
    final maxY = arena.bottom - p.radius;
    return p.copyWith(
      x: p.x.clamp(minX, maxX),
      y: p.y.clamp(minY, maxY),
    );
  }

  ({double left, double top, double right, double bottom}) _arena() {
    final config = state.config;
    final width = config?.viewportWidth ?? MatchConfig.defaultViewportWidth;
    final height = config?.viewportHeight ?? MatchConfig.defaultViewportHeight;

    final maxWidthFraction = 0.84;
    final maxHeightFraction = 0.76;
    const aspect = 4 / 3;

    var fieldWidth = width * maxWidthFraction;
    var fieldHeight = fieldWidth / aspect;
    if (fieldHeight > height * maxHeightFraction) {
      fieldHeight = height * maxHeightFraction;
      fieldWidth = fieldHeight * aspect;
    }

    final left = (width - fieldWidth) / 2;
    final top = (height - fieldHeight) / 2;
    return (
      left: left,
      top: top,
      right: left + fieldWidth,
      bottom: top + fieldHeight,
    );
  }

  bool _insideArena(
    MatchProjectile pr,
    ({double left, double top, double right, double bottom}) arena,
  ) {
    final r = _projectileRadius;
    return pr.x - r >= arena.left &&
        pr.x + r <= arena.right &&
        pr.y - r >= arena.top &&
        pr.y + r <= arena.bottom;
  }

  bool _overlaps(MatchPlayer defender, MatchProjectile projectile) {
    final hitRadius = defender.hitboxSize / 2;
    final r = _projectileRadius;
    final dx = defender.x - projectile.x;
    final dy = defender.y - projectile.y;
    final minDist = hitRadius + r;
    return dx * dx + dy * dy <= minDist * minDist;
  }

  /// Pushes overlapping players apart so bodies cannot pass through each
  /// other. A couple of relaxation passes settle stacked ships.
  List<MatchPlayer> _resolvePlayerCollisions(List<MatchPlayer> players) {
    var result = List<MatchPlayer>.from(players);
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < result.length; i++) {
        for (var j = i + 1; j < result.length; j++) {
          final a = result[i];
          final b = result[j];
          if (!a.alive || !b.alive) continue;
          final dx = b.x - a.x;
          final dy = b.y - a.y;
          final dist = sqrt(dx * dx + dy * dy);
          final minDist = a.hitboxSize / 2 + b.hitboxSize / 2;
          if (dist >= minDist || dist == 0) continue;
          final overlap = (minDist - dist) / 2;
          final nx = dx / dist;
          final ny = dy / dist;
          result[i] = _clampPlayer(
            a.copyWith(x: a.x - nx * overlap, y: a.y - ny * overlap),
          );
          result[j] = _clampPlayer(
            b.copyWith(x: b.x + nx * overlap, y: b.y + ny * overlap),
          );
        }
      }
    }
    return result;
  }

  void _onPauseMatch(PauseMatch event, Emitter<GameState> emit) {
    if (!_isAuthoritative) {
      _sync.sendCommand(GameCommand.pause);
      emit(state.copyWith(
        isPaused: true,
        readyPlayerIds: const <String>{},
      ));
      return;
    }
    if (state.phase != GamePhase.inGame || state.isPaused) return;
    _matchTimer?.cancel();
    _matchTimer = null;
    emit(state.copyWith(
      isPaused: true,
      readyPlayerIds: const <String>{},
    ));
    _startPauseBroadcast();
  }

  void _onPlayerReadyChanged(
    PlayerReadyChanged event,
    Emitter<GameState> emit,
  ) {
    if (!_isAuthoritative) {
      _sync.sendReady(
        playerId: _sync.localPlayerId,
        ready: event.ready,
      );
      return;
    }
    if (!state.isPaused) return;
    final ids = Set<String>.from(state.readyPlayerIds);
    if (event.ready) {
      ids.add(event.playerId);
    } else {
      ids.remove(event.playerId);
    }
    // Stay paused once everyone is ready so Resume / Quit can be chosen
    // deliberately — auto-resuming made Quit unreachable on the host.
    emit(state.copyWith(readyPlayerIds: ids));
  }

  void _onResumeMatch(ResumeMatch event, Emitter<GameState> emit) {
    if (!_isAuthoritative) {
      _sync.sendCommand(GameCommand.resume);
      return;
    }
    if (!state.isPaused || !state.allPlayersReady) return;
    _stopPauseBroadcast();
    emit(state.copyWith(
      isPaused: false,
      readyPlayerIds: const <String>{},
    ));
    _startMatchTimer();
  }

  void _onRestartMatch(RestartMatch event, Emitter<GameState> emit) {
    if (state.isPaused && !state.allPlayersReady) return;
    if (!_isAuthoritative) {
      _sync.sendCommand(GameCommand.restart);
      return;
    }
    _stopMatchTimers();
    _resetLocalInput();
    final config = _activeConfig;
    if (config == null) {
      emit(state.copyWith(
        phase: GamePhase.lobby,
        clearOutcome: true,
      ));
      return;
    }
    emit(state.copyWith(
      phase: GamePhase.countdown,
      config: config,
      remainingSeconds: config.countdownSeconds,
      elapsedMs: 0,
      clearOutcome: true,
      isPaused: false,
      readyPlayerIds: const <String>{},
      players: const <MatchPlayer>[],
      projectiles: const <MatchProjectile>[],
    ));
    _countdownTimer = Timer.periodic(_countdownInterval, (_) {
      add(const CountdownTick());
    });
  }

  void _startMatchTimer() {
    _matchTimer?.cancel();
    _matchTimer = Timer.periodic(_matchTickInterval, (_) {
      add(const MatchTick());
    });
  }

  /// Keeps pushing the frozen paused snapshot until the host resumes, so no
  /// device can stay behind on an old, still-moving frame.
  void _startPauseBroadcast() {
    _pauseTimer?.cancel();
    _pauseTimer = Timer.periodic(_pauseBroadcastInterval, (_) {
      if (!state.isPaused) return;
      _sync.broadcastSnapshot(_snapshotOf(state));
    });
  }

  void _stopPauseBroadcast() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
  }

  void _onRemoteInputApplied(
    RemoteInputApplied event,
    Emitter<GameState> emit,
  ) {
    if (!_isAuthoritative) return;
    if (event.playerId == _localPlayerId) return;
    _remoteInputs[event.playerId] = (
      moveX: event.moveX,
      moveY: event.moveY,
      firing: event.firing,
    );
  }

  void _onRemoteStateApplied(
    RemoteStateApplied event,
    Emitter<GameState> emit,
  ) {
    if (_isAuthoritative) return;
    _stopMatchTimers();
    final s = event.snapshot;
    final players = [
      for (final p in s.players)
        p.toMatch(isLocal: p.id == _sync.localPlayerId),
    ];
    emit(GameState(
      phase: s.phase,
      config: state.config,
      remainingSeconds: s.remainingSeconds,
      elapsedMs: s.elapsedMs,
      matchDurationMs: s.matchDurationMs,
      redScore: s.redScore,
      blueScore: s.blueScore,
      isPaused: s.isPaused,
      readyPlayerIds: {...s.readyPlayerIds},
      outcome: s.phase == GamePhase.matchResult
          ? _outcomeForLocal(players)
          : s.outcome,
      players: players,
      projectiles: [
        for (final pr in s.projectiles) pr.toMatch(),
      ],
    ));
  }

  /// The host ends a match from its own seat; every device must resolve the
  /// result for its own team instead of copying whoever's snapshot arrived.
  MatchOutcome _outcomeForLocal(List<MatchPlayer> players) {
    final redAlive = players.where((p) => p.team == Team.red && p.alive).length;
    final blueAlive = players.where((p) => p.team == Team.blue && p.alive).length;
    if (redAlive > 0 && blueAlive > 0) return MatchOutcome.draw;
    if (redAlive == 0 && blueAlive == 0) return MatchOutcome.draw;
    final winner = redAlive > 0 ? Team.red : Team.blue;
    final local = players.where((p) => p.isLocal).firstOrNull;
    if (local == null) return MatchOutcome.draw;
    return local.team == winner
        ? MatchOutcome.victory
        : MatchOutcome.defeat;
  }

  GameSnapshot _snapshotOf(GameState state) {
    return GameSnapshot(
      phase: state.phase,
      remainingSeconds: state.remainingSeconds,
      elapsedMs: state.elapsedMs,
      matchDurationMs: state.matchDurationMs,
      redScore: state.redScore,
      blueScore: state.blueScore,
      isPaused: state.isPaused,
      readyPlayerIds: state.readyPlayerIds.toList(growable: false),
      outcome: state.outcome,
      players: [
        for (final p in state.players) GamePlayerSnapshot.fromMatch(p),
      ],
      projectiles: [
        for (final pr in state.projectiles)
          GameProjectileSnapshot.fromMatch(pr),
      ],
    );
  }

  void _onMatchOver(MatchOver event, Emitter<GameState> emit) {
    _stopMatchTimers();
    emit(state.copyWith(
      phase: GamePhase.matchResult,
      outcome: event.outcome,
    ));
  }

  void _onReturnToLobby(ReturnToLobby event, Emitter<GameState> emit) {
    if (state.isPaused && !state.allPlayersReady) return;
    if (!_isAuthoritative) {
      _sync.sendCommand(GameCommand.quit);
      // Fall through and leave locally; the host mirrors this for everyone else.
    }
    _stopMatchTimers();
    _resetLocalInput();
    final next = state.copyWith(
      phase: GamePhase.lobby,
      clearConfig: true,
      clearOutcome: true,
      remainingSeconds: 0,
      elapsedMs: 0,
      redScore: 0,
      blueScore: 0,
      isPaused: false,
      readyPlayerIds: const <String>{},
      players: const <MatchPlayer>[],
      projectiles: const <MatchProjectile>[],
    );
    emit(next);
    if (_isAuthoritative) {
      // onTransition skips lobby frames; push one so clients leave too.
      _sync.broadcastSnapshot(_snapshotOf(next));
    }
  }

  void _stopMatchTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _matchTimer?.cancel();
    _matchTimer = null;
    _stopPauseBroadcast();
  }

  void _resetLocalInput() {
    _moveX = 0;
    _moveY = 0;
    _firing = false;
    _remoteInputs.clear();
    _fireCooldowns.clear();
  }

  @override
  Future<void> close() async {
    _stopMatchTimers();
    await _syncSub?.cancel();
    return super.close();
  }
}