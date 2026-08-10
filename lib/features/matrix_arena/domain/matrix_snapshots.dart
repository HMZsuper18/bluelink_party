enum MatrixMatchPhase { calibrating, countdown, playing, finished }

MatrixMatchPhase matrixPhaseFromKey(String key) {
  return switch (key) {
    'calibrating' => MatrixMatchPhase.calibrating,
    'countdown' => MatrixMatchPhase.countdown,
    'playing' => MatrixMatchPhase.playing,
    'finished' => MatrixMatchPhase.finished,
    _ => MatrixMatchPhase.calibrating,
  };
}

String matrixPhaseKey(MatrixMatchPhase phase) => switch (phase) {
      MatrixMatchPhase.calibrating => 'calibrating',
      MatrixMatchPhase.countdown => 'countdown',
      MatrixMatchPhase.playing => 'playing',
      MatrixMatchPhase.finished => 'finished',
    };

class MatrixInput {
  const MatrixInput({
    required this.deviceIndex,
    required this.moveX,
    required this.moveY,
    required this.firing,
    this.sequence = 0,
  });

  final int deviceIndex;
  final double moveX;
  final double moveY;
  final bool firing;
  final int sequence;

  Map<String, dynamic> toJson() => {
        'd': deviceIndex,
        'x': moveX,
        'y': moveY,
        'f': firing,
        's': sequence,
      };

  factory MatrixInput.fromJson(Map<String, dynamic> json) => MatrixInput(
        deviceIndex: (json['d'] as num).toInt(),
        moveX: (json['x'] as num).toDouble(),
        moveY: (json['y'] as num).toDouble(),
        firing: json['f'] == true,
        sequence: (json['s'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) {
    return other is MatrixInput &&
        other.deviceIndex == deviceIndex &&
        other.moveX == moveX &&
        other.moveY == moveY &&
        other.firing == firing &&
        other.sequence == sequence;
  }

  @override
  int get hashCode => Object.hash(deviceIndex, moveX, moveY, firing, sequence);
}

class MatrixPlayerSnapshot {
  const MatrixPlayerSnapshot({
    required this.deviceIndex,
    required this.name,
    required this.x,
    required this.y,
    required this.facingYaw,
    required this.hp,
    required this.maxHp,
    required this.alive,
    required this.kills,
    this.tileX = 0,
    this.tileY = 0,
    this.columns = 1,
    this.rows = 1,
    this.isGoalkeeper = false,
  });

  final int deviceIndex;
  final String name;
  final double x;
  final double y;
  final double facingYaw;
  final int hp;
  final int maxHp;
  final bool alive;
  final int kills;
  final int tileX;
  final int tileY;
  final int columns;
  final int rows;
  final bool isGoalkeeper;

  Map<String, dynamic> toJson() => {
        'i': deviceIndex,
        'n': name,
        'x': x,
        'y': y,
        'a': facingYaw,
        'h': hp,
        'm': maxHp,
        'v': alive,
        'k': kills,
        'tx': tileX,
        'ty': tileY,
        'cx': columns,
        'cy': rows,
        'g': isGoalkeeper,
      };

  factory MatrixPlayerSnapshot.fromJson(Map<String, dynamic> json) =>
      MatrixPlayerSnapshot(
        deviceIndex: (json['i'] as num).toInt(),
        name: (json['n'] as String?) ?? '',
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        facingYaw: (json['a'] as num).toDouble(),
        hp: (json['h'] as num).toInt(),
        maxHp: (json['m'] as num).toInt(),
        alive: json['v'] == true,
        kills: (json['k'] as num?)?.toInt() ?? 0,
        tileX: (json['tx'] as num?)?.toInt() ?? 0,
        tileY: (json['ty'] as num?)?.toInt() ?? 0,
        columns: (json['cx'] as num?)?.toInt() ?? 1,
        rows: (json['cy'] as num?)?.toInt() ?? 1,
        isGoalkeeper: json['g'] == true,
      );
}

class MatrixProjectileSnapshot {
  const MatrixProjectileSnapshot({
    required this.id,
    required this.ownerIndex,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.life = 1.4,
  });

  final int id;
  final int ownerIndex;
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double life;

  Map<String, dynamic> toJson() => {
        'id': id,
        'o': ownerIndex,
        'x': x,
        'y': y,
        'vx': vx,
        'vy': vy,
        'l': life,
      };

  factory MatrixProjectileSnapshot.fromJson(Map<String, dynamic> json) =>
      MatrixProjectileSnapshot(
        id: (json['id'] as num).toInt(),
        ownerIndex: (json['o'] as num).toInt(),
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        vx: (json['vx'] as num).toDouble(),
        vy: (json['vy'] as num).toDouble(),
        life: (json['l'] as num).toDouble(),
      );
}

class MatrixWorldSnapshot {
  const MatrixWorldSnapshot({
    required this.seq,
    required this.timeStamp,
    required this.players,
    required this.projectiles,
    this.futbol,
  });

  final int seq;
  final double timeStamp;
  final List<MatrixPlayerSnapshot> players;
  final List<MatrixProjectileSnapshot> projectiles;
  final FutbolWorld? futbol;

  Map<String, dynamic> toJson() => {
        's': seq,
        't': timeStamp,
        'p': players.map((p) => p.toJson()).toList(),
        'x': projectiles.map((p) => p.toJson()).toList(),
        if (futbol != null) 'g': futbol!.toJson(),
      };

  factory MatrixWorldSnapshot.fromJson(Map<String, dynamic> json) {
    final rawPlayers = (json['p'] as List<dynamic>?) ?? const [];
    final rawProjectiles = (json['x'] as List<dynamic>?) ?? const [];
    final rawFutbol = json['g'];
    return MatrixWorldSnapshot(
      seq: (json['s'] as num).toInt(),
      timeStamp: (json['t'] as num).toDouble(),
      players: rawPlayers
          .map((e) => MatrixPlayerSnapshot.fromJson(e as Map<String, dynamic>))
          .toList(),
      projectiles: rawProjectiles
          .map((e) =>
              MatrixProjectileSnapshot.fromJson(e as Map<String, dynamic>))
          .toList(),
      futbol: rawFutbol is Map<String, dynamic>
          ? FutbolWorld.fromJson(rawFutbol)
          : null,
    );
  }
}

class FutbolWorld {
  const FutbolWorld({
    this.ballX = 0,
    this.ballY = 0,
    this.ballVx = 0,
    this.ballVy = 0,
    this.redScore = 0,
    this.blueScore = 0,
    this.celebration = false,
    this.celebrationSeconds = 0,
    this.scoredBy = 0,
    this.kickOff = false,
    this.phase = 'calibrating',
    this.paused = false,
  });

  final double ballX;
  final double ballY;
  final double ballVx;
  final double ballVy;
  final int redScore;
  final int blueScore;
  final bool celebration;
  final double celebrationSeconds;
  final int scoredBy;
  final bool kickOff;
  final String phase;

  /// True while the host has the match frozen for every device. Rides on the
  /// snapshot stream so a dropped resume phase packet self-heals on the next
  /// broadcast (futbol snapshots never carry a separate phase message).
  final bool paused;

  Map<String, dynamic> toJson() => {
        'x': ballX,
        'y': ballY,
        'vx': ballVx,
        'vy': ballVy,
        'r': redScore,
        'b': blueScore,
        'c': celebration,
        'cs': celebrationSeconds,
        's': scoredBy,
        'k': kickOff,
        'p': phase,
        if (paused) 'z': true,
      };

  factory FutbolWorld.fromJson(Map<String, dynamic> json) => FutbolWorld(
        ballX: (json['x'] as num?)?.toDouble() ?? 0,
        ballY: (json['y'] as num?)?.toDouble() ?? 0,
        ballVx: (json['vx'] as num?)?.toDouble() ?? 0,
        ballVy: (json['vy'] as num?)?.toDouble() ?? 0,
        redScore: (json['r'] as num?)?.toInt() ?? 0,
        blueScore: (json['b'] as num?)?.toInt() ?? 0,
        celebration: json['c'] == true,
        celebrationSeconds: (json['cs'] as num?)?.toDouble() ?? 0,
        scoredBy: (json['s'] as num?)?.toInt() ?? 0,
        kickOff: json['k'] == true,
        phase: json['p'] as String? ?? 'calibrating',
        paused: json['z'] == true,
      );
}

class MatrixPhaseMessage {
  const MatrixPhaseMessage({
    required this.phase,
    required this.remainingSeconds,
    this.winnerIndex,
    this.paused = false,
  });

  final MatrixMatchPhase phase;
  final double remainingSeconds;
  final int? winnerIndex;

  /// True while the host has the match frozen for every device.
  final bool paused;

  Map<String, dynamic> toJson() => {
        'p': matrixPhaseKey(phase),
        'r': remainingSeconds,
        if (winnerIndex != null) 'w': winnerIndex,
        if (paused) 'z': true,
      };

  factory MatrixPhaseMessage.fromJson(Map<String, dynamic> json) =>
      MatrixPhaseMessage(
        phase: matrixPhaseFromKey((json['p'] as String?) ?? 'calibrating'),
        remainingSeconds: (json['r'] as num?)?.toDouble() ?? 0,
        winnerIndex: (json['w'] as num?)?.toInt(),
        paused: json['z'] == true,
      );
}

/// Global pause/resume requests a device sends the host over the
/// game-command channel (see `HostService.gameCommandPackets`). The host is
/// the only authority that actually freezes/resumes the shared match.
enum PauseControlKey {
  pause('pause'),
  resume('resume');

  const PauseControlKey(this.key);

  final String key;

  static PauseControlKey? fromKey(String? key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

class MatrixMatchConfig {
  const MatrixMatchConfig({
    required this.playerCount,
    required this.tileWidth,
    required this.tileHeight,
  });

  final int playerCount;
  final double tileWidth;
  final double tileHeight;

  Map<String, dynamic> toJson() => {
        'n': playerCount,
        'w': tileWidth,
        'h': tileHeight,
      };

  factory MatrixMatchConfig.fromJson(Map<String, dynamic> json) =>
      MatrixMatchConfig(
        playerCount: (json['n'] as num).toInt(),
        tileWidth: (json['w'] as num).toDouble(),
        tileHeight: (json['h'] as num).toDouble(),
      );
}