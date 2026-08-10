import 'dart:collection';
import 'dart:math';

import 'package:flutter/painting.dart';

import '../../../data/models/team.dart';
import '../../matrix_arena/domain/futbol_pitch.dart';
import '../../matrix_arena/domain/matrix_grid.dart';
import '../../matrix_arena/domain/matrix_snapshots.dart';
import '../../matrix_arena/domain/matrix_world.dart';
import '../../matrix_arena/game/matrix_sync_adapter.dart';
import '../../matrix_arena/game/matrix_viewport.dart';
import '../domain/futbol_ball.dart';
import 'futbol_interpolation.dart';
import 'futbol_walk_animator.dart';

class FutbolRules {
  const FutbolRules({
    this.playerSpeed = 260,
    this.playerAccel = 1800,
    this.playerRadius = 26,
    this.ballRadius = 14,
    this.kickImpulse = 560,
    this.kickCooldown = 0.35,
    this.kickRange = 48,
    this.tackleRestitution = 0.6,
    this.tackleTransfer = 6,
    this.ballDrag = 0.85,
    this.wallRestitution = 0.9,
    this.postRadius = 7,
    this.calibrationSeconds = 4,
    this.countdownSeconds = 3,
    this.celebrationSeconds = 1.8,
    this.matchDurationSeconds = 120,
    this.scoreLimit = 5,
    this.maxBallSpeed = 950,
  });

  final double playerSpeed;
  final double playerAccel;
  final double playerRadius;
  final double ballRadius;
  final double kickImpulse;
  final double kickCooldown;
  final double kickRange;
  final double tackleRestitution;
  final double tackleTransfer;
  final double ballDrag;
  final double wallRestitution;
  final double postRadius;
  final double calibrationSeconds;
  final double countdownSeconds;
  final double celebrationSeconds;
  final double matchDurationSeconds;
  final int scoreLimit;
  final double maxBallSpeed;
}

class FutbolMatchController {
  FutbolMatchController({
    required this.matrix,
    required this.deviceCount,
    required this.isHost,
    this.deviceIndex = 0,
    this.rules = const FutbolRules(),
    this.adapter = const NoopMatrixSyncAdapter(),
    this.teams,
  }) : pitch = FutbolPitch(matrix: matrix) {
    _buildPlayers();
    _positionAtKickOff();
  }

  final TileMatrix matrix;
  final int deviceCount;
  final bool isHost;
  final int deviceIndex;
  final FutbolRules rules;
  final MatrixSyncAdapter adapter;
  final FutbolPitch pitch;

  /// Actual team per roster index (device index). Device indices follow the
  /// roster order (red slots first, then blue), so index parity does *not*
  /// imply team. Length must equal [deviceCount]. When null, falls back to
  /// alternating parity for the dev labs and solo bots that seat teams
  /// alternately.
  final List<Team>? teams;

  final List<MatrixWorldAvatar> _players = [];
  final Map<int, MatrixInput> _inputs = {};
  final FutbolInterpolation _interpolation = FutbolInterpolation();

  /// Run-cycle animation state for the rendered players. Advanced every step
  /// so the sprite feet swing only while a player is actually moving.
  final FutbolWalkAnimator walk = FutbolWalkAnimator();

  late FutbolBall _ball;
  FutbolMatchPhase _phase = FutbolMatchPhase.calibrating;
  double _phaseTimer = 0;
  double _celebrationTimer = 0;
  int _redScore = 0;
  int _blueScore = 0;
  int? _scoredBy;
  bool _kickOff = true;
  bool _winnerDecided = false;
  double _matchClock = 0;
  double _snapshotClock = 0;
  int _snapshotSeq = 0;
  bool _paused = false;
  final List<double> _kickCooldown = [];

  FutbolMatchPhase get phase => _phase;
  double get phaseTimer => _phaseTimer;
  double get matchClock => _matchClock;
  int get redScore => _redScore;
  int get blueScore => _blueScore;
  int? get scoredBy => _scoredBy;
  bool get isCelebrating => _celebrationTimer > 0;
  bool get isMatchOver => _phase == FutbolMatchPhase.finished;

  /// True while the host has frozen the shared match for every device.
  bool get isPaused => _paused;
  int? get winnerIndex {
    if (!_winnerDecided) return null;
    if (_redScore == _blueScore) return null;
    return _redScore > _blueScore ? 0 : 1;
  }

  double get ballX => _ball.x;
  double get ballY => _ball.y;
  double get ballVx => _ball.vx;
  double get ballVy => _ball.vy;

  List<MatrixWorldAvatar> get players => UnmodifiableListView(_players);

  /// The slice of the arena this device's camera shows. Slices always tile
  /// the whole pitch, so devices placed side by side reproduce the full
  /// arena: a lone player (1v1 or the outnumbered defender in 2v1) sees their
  /// team's whole vertical half; teammates split their team's column into
  /// stacked quarters (2v1 and 2v2).
  MatrixTileLayout get localTile => sliceFor(deviceIndex);

  /// Team-based slice for [deviceIndex]: red owns the left column, blue the
  /// right. Uses the roster's real team list when provided, else alternating
  /// parity (which matches the geometric row-major grid for the dev labs).
  MatrixTileLayout sliceFor(int deviceIndex) {
    final red = _isRed(deviceIndex);
    var redCount = 0;
    for (var i = 0; i < deviceCount; i++) {
      if (_isRed(i)) redCount++;
    }
    final teamCount = red ? redCount : deviceCount - redCount;
    final column = red ? 0 : 1;

    if (teamCount == 1) {
      // 1v1 or a lone defender: the whole team half, spanning full height.
      return MatrixTileLayout(
        deviceIndex: deviceIndex,
        column: column,
        row: 0,
        columns: 2,
        rows: 1,
        tileWidth: matrix.worldWidth / 2,
        tileHeight: matrix.worldHeight,
      );
    }

    // Teammates split the team's column top/bottom so all slices tile.
    final teamIndexes = [
      for (var i = 0; i < deviceCount; i++)
        if (_isRed(i) == red) i,
    ];
    final order = teamIndexes.indexOf(deviceIndex);
    return MatrixTileLayout(
      deviceIndex: deviceIndex,
      column: column,
      row: order,
      columns: 2,
      rows: 2,
      tileWidth: matrix.worldWidth / 2,
      tileHeight: matrix.worldHeight / 2,
    );
  }

  /// The device's actual team: from the roster's team list when provided, else
  /// alternating parity (red for even indices) for the dev labs / solo bots.
  ///
  /// Negative indices are goalkeepers, encoded as red (-2) / blue (-1) in
  /// [_addOutnumberedKeeper]; they always fall through to the parity fallback,
  /// which intentionally preserves that encoding.
  Team _teamOf(int deviceIndex) {
    if (teams != null && deviceIndex >= 0 && deviceIndex < teams!.length) {
      return teams![deviceIndex];
    }
    return deviceIndex.isEven ? Team.red : Team.blue;
  }

  bool _isRed(int deviceIndex) => _teamOf(deviceIndex) == Team.red;

  MatrixViewportCamera camera(Size screenSize) {
    return MatrixViewportCamera(tile: localTile, screenSize: screenSize);
  }

  void _buildPlayers() {
    _players.clear();
    _kickCooldown.clear();
    for (var i = 0; i < deviceCount; i++) {
      _players.add(MatrixWorldAvatar(
        deviceIndex: i,
        name: 'P${i + 1}',
        x: 0,
        y: 0,
        hp: 1,
        maxHp: 1,
      ));
      _kickCooldown.add(0);
    }
    _addOutnumberedKeeper();
  }

  /// When teams are unbalanced (e.g. 2v1 with 3 devices), give the outnumbered
  /// side a goalkeeper that only slides along its goal line to track the ball.
  void _addOutnumberedKeeper() {
    var redCount = 0;
    for (var i = 0; i < deviceCount; i++) {
      if (_isRed(i)) redCount++;
    }
    final blueCount = deviceCount - redCount;
    if (redCount == blueCount) return;

    final keeperIsRed = redCount < blueCount;
    _players.add(MatrixWorldAvatar(
      deviceIndex: keeperIsRed ? -2 : -1,
      name: 'GK',
      x: 0,
      y: 0,
      hp: 1,
      maxHp: 1,
    )..isGoalkeeper = true);
    _kickCooldown.add(0);
  }

  void _positionAtKickOff() {
    for (var i = 0; i < _players.length; i++) {
      final player = _players[i];
      final spot = player.isGoalkeeper
          ? _goalkeeperSpot(player)
          : pitch.kickoffPlayer(i, red: _isRed(i), slice: sliceFor(i));
      player.spawnAt(nextX: spot.dx, nextY: spot.dy);
      player.vx = 0;
      player.vy = 0;
    }
    _ball = FutbolBall(
      x: pitch.centerX,
      y: pitch.centerY,
      radius: rules.ballRadius,
      drag: rules.ballDrag,
      wallRestitution: rules.wallRestitution,
      maxSpeed: rules.maxBallSpeed,
    );
    _kickOff = true;
    _celebrationTimer = 0;
    _scoredBy = null;
  }

  /// Goalkeeper start position: standing on its goal line. Red defends the
  /// left goal (x=0), blue the right goal (x = worldWidth).
  Offset _goalkeeperSpot(MatrixWorldAvatar keeper) {
    final isRed = _isRed(keeper.deviceIndex);
    final x = isRed
        ? pitch.goalInset + rules.playerRadius * 0.8
        : pitch.worldWidth - (pitch.goalInset + rules.playerRadius * 0.8);
    return Offset(x, pitch.centerY);
  }

  void placeBall(double x, double y) {
    _ball.reset(x, y);
  }

  void start() {
    if (!isHost) return;
    _paused = false;
    _snapshotSeq = 0;
    _snapshotClock = 0;
    _phase = FutbolMatchPhase.calibrating;
    _phaseTimer = rules.calibrationSeconds;
    _broadcastSnapshot();
  }

  void step(double dt) {
    if (dt <= 0) return;
    _interpolation.advanceLocalClock(dt * 1000);
    walk.advance(dt, renderFrame().players, maxSpeed: rules.playerSpeed);
    if (!isHost) return;

    if (_paused) {
      // Keep streaming the frozen world (and the paused phase flag) so every
      // device converges on the same still frame and shows the pause overlay.
      _snapshotClock += dt;
      if (_snapshotClock >= 0.25) {
        _snapshotClock = 0;
        _broadcastSnapshot();
        _broadcastPhase();
      }
      return;
    }

    _matchClock += dt;

    switch (_phase) {
      case FutbolMatchPhase.calibrating:
        _phaseTimer -= dt;
        if (_phaseTimer <= 0) {
          _phase = FutbolMatchPhase.countdown;
          _phaseTimer = rules.countdownSeconds;
          _broadcastPhase();
        }
        break;
      case FutbolMatchPhase.countdown:
        _phaseTimer -= dt;
        if (_phaseTimer <= 0) {
          _startPlay();
        }
        break;
      case FutbolMatchPhase.playing:
        if (_celebrationTimer > 0) {
          _celebrationTimer -= dt;
          if (_celebrationTimer <= 0) {
            _positionAtKickOff();
            _kickOff = true;
          }
        } else {
          _simulate(dt);
        }
        break;
      case FutbolMatchPhase.finished:
        break;
    }

    _snapshotClock += dt;
    if (_snapshotClock >= 0.05) {
      _snapshotClock = 0;
      _broadcastSnapshot();
    }
  }

  void _startPlay() {
    _phase = FutbolMatchPhase.playing;
    _broadcastSnapshot();
  }

  void _simulate(double dt) {
    _applyPlayerMotion(dt);
    _simulateGoalkeepers(dt);
    _resolvePlayerCollisions();
    _reanchorGoalkeepers();
    _resolveBallContacts(dt);
    _ball.step(dt);
    _resolveOuterWalls();
    _resolveGoalPosts();
    _detectGoals();
    _checkMatchEnd();
  }

  void _reanchorGoalkeepers() {
    for (final keeper in _players) {
      if (!keeper.isGoalkeeper) continue;
      final spot = _goalkeeperSpot(keeper);
      keeper.x = spot.dx;
    }
  }

  /// Goalkeepers only slide along the goal line (right and left, i.e. y) to
  /// track the ball, all the time, without ever stopping or chasing the ball
  /// forward/backward on the pitch.
  void _simulateGoalkeepers(double dt) {
    for (final keeper in _players) {
      if (!keeper.isGoalkeeper) continue;

      final isRedKeeper = _isRed(keeper.deviceIndex);
      final goalTop = isRedKeeper ? pitch.leftGoalTop : pitch.rightGoalTop;
      final goalBottom = isRedKeeper
          ? pitch.leftGoalBottom
          : pitch.rightGoalBottom;

      final lead = _ball.vy * 0.25;
      final wantedY = (_ball.y + lead).clamp(goalTop, goalBottom);
      final dy = wantedY - keeper.y;
      final speed = rules.playerSpeed * 0.62;
      final maxStep = speed * dt;
      keeper.y += dy.clamp(-maxStep, maxStep);
      keeper.vy = dy == 0 ? 0 : dy / dy.abs() * speed;
      keeper.vx = 0;
      keeper.facingYaw = atan2(_ball.y - keeper.y, _ball.x - keeper.x);
    }
  }

  void _applyPlayerMotion(double dt) {
    for (final player in _players) {
      if (player.isGoalkeeper) continue;
      final input = _inputs[player.deviceIndex];
      if (input == null) continue;
      final magnitude =
          sqrt(input.moveX * input.moveX + input.moveY * input.moveY);
      if (magnitude > 0.001) {
        final targetVx = input.moveX / magnitude * rules.playerSpeed;
        final targetVy = input.moveY / magnitude * rules.playerSpeed;
        player.vx = _approach(
          current: player.vx,
          target: targetVx,
          maxDelta: rules.playerAccel * dt,
        );
        player.vy = _approach(
          current: player.vy,
          target: targetVy,
          maxDelta: rules.playerAccel * dt,
        );
        player.facingYaw = atan2(input.moveY, input.moveX);
      } else {
        player.vx = 0;
        player.vy = 0;
      }
      player.x += player.vx * dt;
      player.y += player.vy * dt;
      final clamped = pitch.clampPlayer(Offset(player.x, player.y));
      player.x = clamped.dx;
      player.y = clamped.dy;
    }
  }

  double _approach({
    required double current,
    required double target,
    required double maxDelta,
  }) {
    if (current < target) return min(current + maxDelta, target);
    if (current > target) return max(current - maxDelta, target);
    return current;
  }

  void _resolvePlayerCollisions() {
    for (var i = 0; i < _players.length; i++) {
      for (var j = i + 1; j < _players.length; j++) {
        final a = _players[i];
        final b = _players[j];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dist = sqrt(dx * dx + dy * dy);
        final minDist = rules.playerRadius * 2;
        if (dist >= minDist || dist < 0.0001) continue;
        final nx = dx / dist;
        final ny = dy / dist;
        final push = (minDist - dist) / 2;
        a.x -= nx * push;
        a.y -= ny * push;
        b.x += nx * push;
        b.y += ny * push;
      }
    }
  }

  void _resolveBallContacts(double dt) {
    for (var i = 0; i < _players.length; i++) {
      if (_kickCooldown[i] > 0) _kickCooldown[i] -= dt;
      final player = _players[i];
      final input = _inputs[i];
      final dx = _ball.x - player.x;
      final dy = _ball.y - player.y;
      final dist = sqrt(dx * dx + dy * dy);

      if (input != null && input.firing && _kickCooldown[i] <= 0) {
        if (dist < rules.kickRange) {
          final kx = cos(player.facingYaw);
          final ky = sin(player.facingYaw);
          _ball.applyImpulse(kx * rules.kickImpulse, ky * rules.kickImpulse);
          _ball.x = player.x + kx * (rules.playerRadius + rules.ballRadius +
              rules.kickRange / 2);
          _ball.y = player.y + ky * (rules.playerRadius + rules.ballRadius +
              rules.kickRange / 2);
          _kickCooldown[i] = rules.kickCooldown;
          continue;
        }
      }

      final minDist = rules.playerRadius + rules.ballRadius;
      if (dist >= minDist) continue;
      if (dist < 0.0001) continue;

      final nx = dx / dist;
      final ny = dy / dist;
      final overlap = minDist - dist;
      _ball.x += nx * overlap;
      _ball.y += ny * overlap;

      final relAlongNormal =
          (_ball.vx - player.vx) * nx + (_ball.vy - player.vy) * ny;
      if (relAlongNormal < 0) {
        final impulse = -(1 + rules.tackleRestitution) * relAlongNormal / 2;
        _ball.vx += impulse * nx;
        _ball.vy += impulse * ny;
      }
      _ball.vx += player.vx * rules.tackleTransfer * dt;
      _ball.vy += player.vy * rules.tackleTransfer * dt;
    }
  }

  void _resolveOuterWalls() {
    final ball = _ball;
    if (ball.x - ball.radius < 0) {
      final inGoalMouth =
          ball.y >= pitch.leftGoalTop && ball.y <= pitch.leftGoalBottom;
      if (inGoalMouth) {
        ball.x = -ball.radius;
      } else {
        ball.x = ball.radius;
        ball.reflect(const Offset(1, 0));
      }
    } else if (ball.x + ball.radius > pitch.worldWidth) {
      final inGoalMouth =
          ball.y >= pitch.rightGoalTop && ball.y <= pitch.rightGoalBottom;
      if (inGoalMouth) {
        ball.x = pitch.worldWidth + ball.radius;
      } else {
        ball.x = pitch.worldWidth - ball.radius;
        ball.reflect(const Offset(-1, 0));
      }
    }

    if (ball.y - ball.radius < 0) {
      ball.y = ball.radius;
      ball.reflect(const Offset(0, 1));
    } else if (ball.y + ball.radius > pitch.worldHeight) {
      ball.y = pitch.worldHeight - ball.radius;
      ball.reflect(const Offset(0, -1));
    }
  }

  void _resolveGoalPosts() {
    _bounceOffPost(pitch.leftPostTop);
    _bounceOffPost(pitch.leftPostBottom);
    _bounceOffPost(pitch.rightPostTop);
    _bounceOffPost(pitch.rightPostBottom);
  }

  void _bounceOffPost(Offset post) {
    final dx = _ball.x - post.dx;
    final dy = _ball.y - post.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final minDist = rules.postRadius + rules.ballRadius;
    if (dist >= minDist || dist < 0.0001) return;
    final nx = dx / dist;
    final ny = dy / dist;
    _ball.x = post.dx + nx * minDist;
    _ball.y = post.dy + ny * minDist;
    final nv = _ball.vx * nx + _ball.vy * ny;
    if (nv < 0) {
      _ball.vx -= (1 + rules.wallRestitution) * nv * nx;
      _ball.vy -= (1 + rules.wallRestitution) * nv * ny;
    }
  }

  void _detectGoals() {
    final ball = _ball;
    if (ball.x + ball.radius <= 0) {
      if (_inLeftMouth(ball.y)) {
        _onGoal(scoredForRed: false);
      }
      return;
    }
    if (ball.x - ball.radius >= pitch.worldWidth) {
      if (_inRightMouth(ball.y)) {
        _onGoal(scoredForRed: true);
      }
    }
  }

  bool _inLeftMouth(double y) => y >= pitch.leftGoalTop && y <= pitch.leftGoalBottom;
  bool _inRightMouth(double y) => y >= pitch.rightGoalTop && y <= pitch.rightGoalBottom;

  void _onGoal({required bool scoredForRed}) {
    if (scoredForRed) {
      _redScore += 1;
    } else {
      _blueScore += 1;
    }
    _scoredBy = scoredForRed ? 0 : 1;
    _celebrationTimer = rules.celebrationSeconds;
    _kickOff = false;
    _ball.vx = 0;
    _ball.vy = 0;
    _broadcastSnapshot();
    _checkMatchEnd();
  }

  void _checkMatchEnd() {
    if (_winnerDecided) return;
    final limitReached = rules.scoreLimit > 0 &&
        (_redScore >= rules.scoreLimit || _blueScore >= rules.scoreLimit);
    final timeUp = rules.matchDurationSeconds > 0 &&
        _matchClock >= rules.matchDurationSeconds;
    if (limitReached || timeUp) {
      _winnerDecided = true;
      _phase = FutbolMatchPhase.finished;
    }
  }

  FutbolWorld _wireState({String? phaseKey}) => FutbolWorld(
        ballX: _ball.x,
        ballY: _ball.y,
        ballVx: _ball.vx,
        ballVy: _ball.vy,
        redScore: _redScore,
        blueScore: _blueScore,
        celebration: _celebrationTimer > 0,
        celebrationSeconds: _celebrationTimer,
        scoredBy: _scoredBy ?? 0,
        kickOff: _kickOff,
        phase: phaseKey ?? futbolPhaseKey(_phase),
        paused: _paused,
      );

  List<MatrixPlayerSnapshot> _playerSnapshots() {
    return [
      for (final player in _players)
        MatrixPlayerSnapshot(
          deviceIndex: player.deviceIndex,
          name: player.name,
          x: player.x,
          y: player.y,
          facingYaw: player.facingYaw,
          hp: 1,
          maxHp: 1,
          alive: true,
          kills: 0,
          tileX: player.isGoalkeeper
              ? 0
              : sliceFor(player.deviceIndex).column,
          tileY: player.isGoalkeeper
              ? 0
              : sliceFor(player.deviceIndex).row,
          columns: matrix.columns,
          rows: matrix.rows,
          isGoalkeeper: player.isGoalkeeper,
        ),
    ];
  }

  void _broadcastSnapshot() {
    if (!isHost) return;
    adapter.sendSnapshot(MatrixWorldSnapshot(
      seq: _snapshotSeq++,
      timeStamp: _matchClock * 1000,
      players: _playerSnapshots(),
      projectiles: const [],
      futbol: _wireState(),
    ));
  }

  void _broadcastPhase() {
    if (!isHost) return;
    adapter.sendPhase(MatrixPhaseMessage(
      phase: matrixPhaseForFutbol(_phase),
      remainingSeconds: _phaseTimer,
      winnerIndex: winnerIndex,
      paused: _paused,
    ));
  }

  void setLocalInput({
    required double moveX,
    required double moveY,
    required bool firing,
  }) {
    final input = MatrixInput(
      deviceIndex: deviceIndex,
      moveX: moveX,
      moveY: moveY,
      firing: firing,
    );
    _inputs[deviceIndex] = input;
    if (!isHost) {
      adapter.sendInput(input);
    }
  }

  void applyRemoteInput(MatrixInput input) {
    if (!isHost) return;
    if (input.deviceIndex < 0 || input.deviceIndex >= _players.length) return;
    _inputs[input.deviceIndex] = input;
  }

  void applyRemotePhase(MatrixPhaseMessage phase) {
    if (isHost) return;
    _phase = futbolPhaseFromMatrix(phase.phase);
    _phaseTimer = phase.remainingSeconds;
    _paused = phase.paused;
    if (phase.phase == MatrixMatchPhase.finished) {
      _winnerDecided = true;
    }
  }

  /// Host only: freeze the match for every device. Clients converge on the
  /// frozen frame through the continuing snapshot stream and show the pause
  /// overlay once they receive the paused phase flag.
  void pause() {
    if (!isHost || _paused) return;
    _paused = true;
    _broadcastPhase();
  }

  /// Host only: unfreeze the shared match.
  void resume() {
    if (!isHost || !_paused) return;
    _paused = false;
    _broadcastPhase();
  }

  /// Any device: pause/resume the shared match. The host applies the request
  /// directly; clients forward it over the game-command channel.
  void requestPause(bool paused) {
    if (isHost) {
      if (paused) {
        pause();
      } else {
        resume();
      }
    } else {
      adapter.requestPause(paused);
    }
  }

  void applyRemoteSnapshot(MatrixWorldSnapshot snapshot) {
    if (isHost) return;
    _interpolation.push(snapshot);
    final futbol = snapshot.futbol;
    if (futbol == null) return;
    _phase = futbolPhaseFromKey(futbol.phase);
    _paused = futbol.paused;
    _redScore = futbol.redScore;
    _blueScore = futbol.blueScore;
    _scoredBy = futbol.scoredBy;
    _kickOff = futbol.kickOff;
    _celebrationTimer = futbol.celebration
        ? max(futbol.celebrationSeconds, 0.05)
        : 0;
  }

  FutbolRenderFrame renderFrame() {
    if (isHost) {
      return FutbolRenderFrame(
        players: _playerSnapshots(),
        ballX: _ball.x,
        ballY: _ball.y,
        phase: _phase,
        redScore: _redScore,
        blueScore: _blueScore,
        celebration: _celebrationTimer > 0,
        celebrationSeconds: _celebrationTimer,
        scoredBy: _scoredBy ?? 0,
        kickOff: _kickOff,
      );
    }
    return _interpolation.sample(
      basePlayers: _playerSnapshots(),
      phase: _phase,
    );
  }

  void dispose() {
    adapter.dispose();
  }
}