import '../../matrix_arena/domain/matrix_snapshots.dart';

enum FutbolMatchPhase { calibrating, countdown, playing, finished }

MatrixMatchPhase matrixPhaseForFutbol(FutbolMatchPhase phase) => switch (phase) {
      FutbolMatchPhase.calibrating => MatrixMatchPhase.calibrating,
      FutbolMatchPhase.countdown => MatrixMatchPhase.countdown,
      FutbolMatchPhase.playing => MatrixMatchPhase.playing,
      FutbolMatchPhase.finished => MatrixMatchPhase.finished,
    };

FutbolMatchPhase futbolPhaseFromMatrix(MatrixMatchPhase phase) =>
    switch (phase) {
      MatrixMatchPhase.calibrating => FutbolMatchPhase.calibrating,
      MatrixMatchPhase.countdown => FutbolMatchPhase.countdown,
      MatrixMatchPhase.playing => FutbolMatchPhase.playing,
      MatrixMatchPhase.finished => FutbolMatchPhase.finished,
    };

FutbolMatchPhase futbolPhaseFromKey(String key) => switch (key) {
      'countdown' => FutbolMatchPhase.countdown,
      'playing' => FutbolMatchPhase.playing,
      'finished' => FutbolMatchPhase.finished,
      _ => FutbolMatchPhase.calibrating,
    };

String futbolPhaseKey(FutbolMatchPhase phase) => switch (phase) {
      FutbolMatchPhase.calibrating => 'calibrating',
      FutbolMatchPhase.countdown => 'countdown',
      FutbolMatchPhase.playing => 'playing',
      FutbolMatchPhase.finished => 'finished',
    };

class FutbolRenderFrame {
  const FutbolRenderFrame({
    required this.players,
    this.ballX = 0,
    this.ballY = 0,
    this.phase = FutbolMatchPhase.calibrating,
    this.redScore = 0,
    this.blueScore = 0,
    this.celebration = false,
    this.celebrationSeconds = 0,
    this.scoredBy = 0,
    this.kickOff = false,
    this.ageMs = 0,
  });

  final List<MatrixPlayerSnapshot> players;
  final double ballX;
  final double ballY;
  final FutbolMatchPhase phase;
  final int redScore;
  final int blueScore;
  final bool celebration;
  final double celebrationSeconds;
  final int scoredBy;
  final bool kickOff;
  final double ageMs;
}

class FutbolInterpolation {
  static const int maxSnapshots = 12;
  static const double renderDelayMs = 80;

  final List<MatrixWorldSnapshot> _snapshots = [];
  double _localClockMs = 0;

  void push(MatrixWorldSnapshot snapshot) {
    _snapshots.add(snapshot);
    if (_snapshots.length > maxSnapshots) {
      _snapshots.removeAt(0);
    }
  }

  void advanceLocalClock(double deltaMs) {
    _localClockMs += deltaMs;
  }

  void reset() {
    _snapshots.clear();
    _localClockMs = 0;
  }

  int get bufferedCount => _snapshots.length;

  FutbolRenderFrame sample({
    List<MatrixPlayerSnapshot>? basePlayers,
    FutbolMatchPhase phase = FutbolMatchPhase.playing,
  }) {
    if (_snapshots.isEmpty) {
      return FutbolRenderFrame(
        players: basePlayers ?? const [],
        phase: phase,
      );
    }

    final renderTime = _localClockMs - renderDelayMs;
    final newest = _snapshots.last;
    final newestFutbol = newest.futbol;
    MatrixWorldSnapshot? older;

    for (var i = _snapshots.length - 2; i >= 0; i--) {
      if (_snapshots[i].timeStamp <= renderTime) {
        older = _snapshots[i];
        break;
      }
    }

    List<MatrixPlayerSnapshot> players;
    double ballX;
    double ballY;
    double ageMs;

    if (older == null) {
      players = newest.players;
      ballX = newestFutbol?.ballX ?? 0;
      ballY = newestFutbol?.ballY ?? 0;
      ageMs = renderTime - newest.timeStamp;
    } else {
      final span = newest.timeStamp - older.timeStamp;
      final factor = span <= 0
          ? 1.0
          : ((renderTime - older.timeStamp) / span).clamp(0.0, 1.0);

      players = <MatrixPlayerSnapshot>[];
      for (final newPlayer in newest.players) {
        final oldPlayer = _matchPlayer(older, newPlayer.deviceIndex);
        players.add(oldPlayer == null
            ? newPlayer
            : MatrixPlayerSnapshot(
                deviceIndex: newPlayer.deviceIndex,
                name: newPlayer.name,
                x: _lerp(oldPlayer.x, newPlayer.x, factor),
                y: _lerp(oldPlayer.y, newPlayer.y, factor),
                facingYaw:
                    _lerpAngle(oldPlayer.facingYaw, newPlayer.facingYaw, factor),
                hp: newPlayer.hp,
                maxHp: newPlayer.maxHp,
                alive: newPlayer.alive,
                kills: newPlayer.kills,
                tileX: newPlayer.tileX,
                tileY: newPlayer.tileY,
                columns: newPlayer.columns,
                rows: newPlayer.rows,
              ));
      }

      final oldFutbol = older.futbol;
      ballX = oldFutbol == null || newestFutbol == null
          ? (newestFutbol?.ballX ?? 0)
          : _lerp(oldFutbol.ballX, newestFutbol.ballX, factor);
      ballY = oldFutbol == null || newestFutbol == null
          ? (newestFutbol?.ballY ?? 0)
          : _lerp(oldFutbol.ballY, newestFutbol.ballY, factor);
      ageMs = renderTime - older.timeStamp;
    }

    return FutbolRenderFrame(
      players: players,
      ballX: ballX,
      ballY: ballY,
      phase: phase,
      redScore: newestFutbol?.redScore ?? 0,
      blueScore: newestFutbol?.blueScore ?? 0,
      celebration: newestFutbol?.celebration ?? false,
      celebrationSeconds: newestFutbol?.celebrationSeconds ?? 0,
      scoredBy: newestFutbol?.scoredBy ?? 0,
      kickOff: newestFutbol?.kickOff ?? false,
      ageMs: ageMs,
    );
  }

  MatrixPlayerSnapshot? _matchPlayer(
    MatrixWorldSnapshot snapshot,
    int deviceIndex,
  ) {
    for (final player in snapshot.players) {
      if (player.deviceIndex == deviceIndex) return player;
    }
    return null;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  double _lerpAngle(double a, double b, double t) {
    var delta = (b - a) % (2 * 3.141592653589793);
    if (delta > 3.141592653589793) delta -= 2 * 3.141592653589793;
    if (delta < -3.141592653589793) delta += 2 * 3.141592653589793;
    return a + delta * t;
  }
}