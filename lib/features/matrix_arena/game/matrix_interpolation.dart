import '../domain/matrix_snapshots.dart';

class MatrixInterpolationFrame {
  const MatrixInterpolationFrame({
    required this.players,
    required this.projectiles,
    required this.ageMs,
  });

  final List<MatrixPlayerSnapshot> players;
  final List<MatrixProjectileSnapshot> projectiles;
  final double ageMs;
}

class MatrixSnapshotBuffer {
  static const int _maxSnapshots = 12;
  static const double _renderDelayMs = 80;

  final List<MatrixWorldSnapshot> _snapshots = [];
  double _localClockMs = 0;

  void push(MatrixWorldSnapshot snapshot) {
    _snapshots.add(snapshot);
    if (_snapshots.length > _maxSnapshots) {
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

  MatrixInterpolationFrame sample({
    List<MatrixPlayerSnapshot>? basePlayers,
  }) {
    if (_snapshots.isEmpty) {
      return MatrixInterpolationFrame(
        players: basePlayers ?? const [],
        projectiles: const [],
        ageMs: 0,
      );
    }

    final renderTime = _localClockMs - _renderDelayMs;
    final newest = _snapshots.last;
    MatrixWorldSnapshot? older;

    for (var i = _snapshots.length - 2; i >= 0; i--) {
      if (_snapshots[i].timeStamp <= renderTime) {
        older = _snapshots[i];
        break;
      }
    }

    if (older == null) {
      if (newest.timeStamp <= renderTime) {
        return MatrixInterpolationFrame(
          players: newest.players,
          projectiles: newest.projectiles,
          ageMs: renderTime - newest.timeStamp,
        );
      }
      final first = _snapshots.first;
      return MatrixInterpolationFrame(
        players: first.players,
        projectiles: first.projectiles,
        ageMs: renderTime - first.timeStamp,
      );
    }

    final span = newest.timeStamp - older.timeStamp;
    final factor = span <= 0
        ? 1.0
        : ((renderTime - older.timeStamp) / span).clamp(0.0, 1.0);

    final players = <MatrixPlayerSnapshot>[];
    for (final newPlayer in newest.players) {
      final oldPlayer = _matchPlayer(older, newPlayer.deviceIndex);
      if (oldPlayer == null) {
        players.add(newPlayer);
        continue;
      }
      players.add(MatrixPlayerSnapshot(
        deviceIndex: newPlayer.deviceIndex,
        name: newPlayer.name,
        x: _lerp(oldPlayer.x, newPlayer.x, factor),
        y: _lerp(oldPlayer.y, newPlayer.y, factor),
        facingYaw: _lerpAngle(oldPlayer.facingYaw, newPlayer.facingYaw, factor),
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

    final projectiles = <MatrixProjectileSnapshot>[];
    for (final newProjectile in newest.projectiles) {
      final oldProjectile = _matchProjectile(older, newProjectile.id);
      if (oldProjectile == null) {
        projectiles.add(newProjectile);
        continue;
      }
      projectiles.add(MatrixProjectileSnapshot(
        id: newProjectile.id,
        ownerIndex: newProjectile.ownerIndex,
        x: _lerp(oldProjectile.x, newProjectile.x, factor),
        y: _lerp(oldProjectile.y, newProjectile.y, factor),
        vx: newProjectile.vx,
        vy: newProjectile.vy,
        life: newProjectile.life,
      ));
    }

    return MatrixInterpolationFrame(
      players: players,
      projectiles: projectiles,
      ageMs: renderTime - older.timeStamp,
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

  MatrixProjectileSnapshot? _matchProjectile(
    MatrixWorldSnapshot snapshot,
    int id,
  ) {
    for (final projectile in snapshot.projectiles) {
      if (projectile.id == id) return projectile;
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