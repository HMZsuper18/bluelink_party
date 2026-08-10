import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_shift/data/models/team.dart';
import 'package:screen_shift/features/matrix_arena/domain/matrix_grid.dart';
import 'package:screen_shift/features/matrix_arena/domain/matrix_snapshots.dart';
import 'package:screen_shift/features/matrix_arena/game/matrix_sync_adapter.dart';
import 'package:screen_shift/features/matrix_futbol/domain/futbol_ball.dart';
import 'package:screen_shift/features/matrix_futbol/game/futbol_interpolation.dart';
import 'package:screen_shift/features/matrix_futbol/game/futbol_match_controller.dart';

class _Bus implements MatrixSyncAdapter {
  FutbolMatchController? host;
  FutbolMatchController? client;

  @override
  void sendInput(MatrixInput input) {
    host?.applyRemoteInput(input);
  }

  @override
  void sendPhase(MatrixPhaseMessage phase) {
    client?.applyRemotePhase(phase);
  }

  @override
  void sendSnapshot(MatrixWorldSnapshot snapshot) {
    client?.applyRemoteSnapshot(snapshot);
  }

  @override
  void requestPause(bool paused) {
    if (paused) {
      host?.pause();
    } else {
      host?.resume();
    }
  }

  @override
  void dispose() {}
}

FutbolRules get _fastRules => const FutbolRules(
      calibrationSeconds: 0.2,
      countdownSeconds: 0.2,
      celebrationSeconds: 0.3,
      matchDurationSeconds: 0,
      scoreLimit: 3,
    );

FutbolMatchController _host({
  int deviceCount = 2,
  int deviceIndex = 0,
  FutbolRules? rules,
  MatrixSyncAdapter? adapter,
  List<Team>? teams,
}) {
  return FutbolMatchController(
    matrix: MatrixLayoutManager().matrixForPlayerCount(deviceCount),
    deviceCount: deviceCount,
    isHost: true,
    deviceIndex: deviceIndex,
    rules: rules ?? _fastRules,
    adapter: adapter ?? const NoopMatrixSyncAdapter(),
    teams: teams,
  );
}

FutbolMatchController _client({
  int deviceCount = 2,
  int deviceIndex = 1,
  MatrixSyncAdapter? adapter,
  List<Team>? teams,
}) {
  return FutbolMatchController(
    matrix: MatrixLayoutManager().matrixForPlayerCount(deviceCount),
    deviceCount: deviceCount,
    isHost: false,
    deviceIndex: deviceIndex,
    rules: _fastRules,
    adapter: adapter ?? const NoopMatrixSyncAdapter(),
    teams: teams,
  );
}

void _run(FutbolMatchController controller, int frames, [double dt = 1 / 60]) {
  for (var i = 0; i < frames; i++) {
    controller.step(dt);
  }
}

void _reachPlaying(FutbolMatchController host) {
  host.start();
  _run(host, 26);
}

void main() {
  group('pitch geometry', () {
    test('2 devices span one 1000x600 horizontal strip', () {
      final host = _host(deviceCount: 2);
      expect(host.pitch.worldWidth, 2000);
      expect(host.pitch.worldHeight, 600);
      expect(host.pitch.centerX, 1000);
      expect(host.pitch.centerY, 300);
    });

    test('4 devices span a 2000x1200 matrix', () {
      final host = _host(deviceCount: 4);
      expect(host.pitch.worldWidth, 2000);
      expect(host.pitch.worldHeight, 1200);
      expect(host.pitch.leftGoalTop, 480);
      expect(host.pitch.leftPostTop.dx, 0);
      expect(host.pitch.rightPostBottom.dx, 2000);
    });

    test('the goal mouth is inside the pitch and taller than the ball', () {
      final host = _host(deviceCount: 2);
      expect(host.pitch.leftGoalTop, lessThan(host.pitch.centerY));
      expect(host.pitch.leftGoalBottom, greaterThan(host.pitch.centerY));
      expect(
        host.pitch.leftGoalBottom - host.pitch.leftGoalTop,
        greaterThan(host.rules.ballRadius * 2),
      );
    });

    test('red stripes kick off on the left half, blue on the right', () {
      final host = _host(deviceCount: 4);
      _reachPlaying(host);
      for (var i = 0; i < 4; i++) {
        final expectedSide = i.isEven ? -1.0 : 1.0;
        final actualSide = host.players[i].x - host.pitch.centerX;
        expect(actualSide.sign, expectedSide);
      }
      expect(host.ballX, host.pitch.centerX);
    });
  });

  group('ball physics', () {
    test('friction decays velocity over time', () {
      final ball = FutbolBall(x: 0, y: 0, vx: 500, vy: 0, drag: 0.85);
      ball.step(0.5);
      expect(ball.speed, lessThan(500));
      expect(ball.speed, greaterThan(0));
    });

    test('wall reflects inward velocity with restitution', () {
      final ball = FutbolBall(
        x: 6,
        y: 300,
        vx: -200,
        vy: 0,
        radius: 14,
        wallRestitution: 0.9,
      );
      ball.reflect(const Offset(1, 0));
      expect(ball.vx, closeTo(180, 0.01));
      expect(ball.x, closeTo(6, 0.01));
    });

    test('ball bounces off the top wall', () {
      final ball = FutbolBall(
        x: 100,
        y: 5,
        vx: 0,
        vy: -300,
        radius: 14,
        wallRestitution: 0.9,
      );
      ball.reflect(const Offset(0, 1));
      expect(ball.vy, closeTo(270, 0.01));
    });

    test('ball speed never exceeds maxBallSpeed', () {
      final ball = FutbolBall(x: 0, y: 0, maxSpeed: 100);
      ball.applyImpulse(5000, 0);
      expect(ball.speed, lessThanOrEqualTo(100));
    });
  });

  group('kick & tackle', () {
    test('kicking inside range sends the ball flying along facing', () {
      final host = _host(deviceCount: 2);
      _reachPlaying(host);
      final player = host.players[0];
      player
        ..x = 300
        ..y = 300
        ..facingYaw = 0;
      host.placeBall(330, 300);
      host.setLocalInput(moveX: 1, moveY: 0, firing: true);
      _run(host, 2);
      expect(host.ballVx, greaterThan(400));
      expect(host.ballVy, closeTo(0, 0.5));
    });

    test('a kick is not re-triggered while cooldown is active', () {
      final host = _host(deviceCount: 2);
      _reachPlaying(host);
      final player = host.players[0];
      player
        ..x = 300
        ..y = 300
        ..facingYaw = 0;
      host.placeBall(330, 300);
      host.setLocalInput(moveX: 1, moveY: 0, firing: true);
      _run(host, 1);
      final vxAfterKick = host.ballVx;
      _run(host, 10);
      final vxLater = host.ballVx;
      expect(vxLater, lessThan(vxAfterKick * 0.99));
    });

    test('a body tackle shoves the ball with leftover player speed', () {
      final host = _host(deviceCount: 2);
      _reachPlaying(host);
      final player = host.players[0];
      player
        ..x = 500
        ..y = 500;
      host.placeBall(560, 500);
      host.setLocalInput(moveX: 1, moveY: 0, firing: false);
      _run(host, 30);
      expect(host.ballVx, greaterThan(100));
    });
  });

  group('team assignment', () {
    test('a lone blue player (2v1) sees the whole right half', () {
      // Roster order groups red first: red, red, then the lone blue device.
      final host = _host(
        deviceCount: 3,
        deviceIndex: 2,
        teams: const [Team.red, Team.red, Team.blue],
      );
      final cam = host.camera(const Size(1600, 800));
      expect(host.pitch.worldWidth, 2000);
      expect(host.pitch.worldHeight, 1200);
      expect(cam.worldToScreen(1000, 600).dx, closeTo(cam.playRect.left, 0.001),
          reason: 'view must start at the middle of the world');
      expect(cam.worldToScreen(2000, 600).dx, closeTo(cam.playRect.right, 0.001),
          reason: 'view must end at the right edge of the world');
    });

    test('a lone red player sees the whole left half', () {
      final host = _host(
        deviceCount: 3,
        deviceIndex: 0,
        teams: const [Team.red, Team.blue, Team.blue],
      );
      final cam = host.camera(const Size(1600, 800));
      expect(cam.worldToScreen(0, 600).dx, closeTo(cam.playRect.left, 0.001));
      expect(cam.worldToScreen(1000, 600).dx,
          closeTo(cam.playRect.right, 0.001));
    });

    test('a balanced 2v2 keeps every device on its own quarter tile', () {
      final host = _host(
        deviceCount: 4,
        deviceIndex: 0,
        teams: const [Team.red, Team.red, Team.blue, Team.blue],
      );
      final cam = host.camera(const Size(1600, 800));
      // No lone team: the camera is the device's quarter tile, so the world's
      // center maps to the tile's right edge, not the middle of the screen.
      expect(host.pitch.worldWidth, 2000);
      expect(host.pitch.worldHeight, 1200);
      expect(cam.worldToScreen(1000, 600).dx, closeTo(cam.playRect.right, 0.001));
      expect(cam.worldToScreen(1500, 600).dx, greaterThan(cam.playRect.right));
    });

    test('2v1 teammates split their team column; the lone defender gets the '
        'whole half', () {
      const teams = [Team.red, Team.red, Team.blue];
      final red0 = _host(deviceCount: 3, deviceIndex: 0, teams: teams);
      final red1 = _host(deviceCount: 3, deviceIndex: 1, teams: teams);
      final blue = _host(deviceCount: 3, deviceIndex: 2, teams: teams);

      final cam0 = red0.camera(const Size(1600, 800));
      final cam1 = red1.camera(const Size(1600, 800));
      final camB = blue.camera(const Size(1600, 800));

      expect(cam0.playRect.contains(cam0.worldToScreen(500, 300)), isTrue,
          reason: 'red seat 0 sees the top-left quarter');
      expect(cam0.playRect.contains(cam0.worldToScreen(1500, 300)), isFalse);

      expect(cam1.playRect.contains(cam1.worldToScreen(500, 900)), isTrue,
          reason: 'red seat 1 sees the bottom-left quarter, not the right half');
      expect(cam1.playRect.contains(cam1.worldToScreen(1500, 300)), isFalse);

      // The lone blue defender covers the whole right half, vertically.
      expect(camB.worldToScreen(1000, 600).dx, closeTo(camB.playRect.left, 0.001));
      expect(camB.worldToScreen(2000, 600).dx,
          closeTo(camB.playRect.right, 0.001));
    });

    test('2v2 cameras put red on the left column and blue on the right column',
        () {
      const teams = [Team.red, Team.red, Team.blue, Team.blue];
      final red1 = _host(deviceCount: 4, deviceIndex: 1, teams: teams);
      final blue2 = _host(deviceCount: 4, deviceIndex: 2, teams: teams);

      final camRed = red1.camera(const Size(1600, 800));
      expect(camRed.playRect.contains(camRed.worldToScreen(500, 900)), isTrue,
          reason: 'red seat 1 (roster index 1) sees the bottom-left quarter');
      expect(camRed.playRect.contains(camRed.worldToScreen(1500, 300)), isFalse,
          reason: '…not the top-right quarter');

      final camBlue = blue2.camera(const Size(1600, 800));
      expect(camBlue.playRect.contains(camBlue.worldToScreen(1500, 300)), isTrue,
          reason: 'blue seat 0 (roster index 2) sees the top-right quarter');
      expect(camBlue.playRect.contains(camBlue.worldToScreen(500, 900)), isFalse,
          reason: '…not the bottom-left quarter');
    });

    test('every player kicks off inside the slice they can see', () {
      const lineups = <List<Team>>[
        [Team.red, Team.blue],
        [Team.red, Team.red, Team.blue],
        [Team.red, Team.blue, Team.blue],
        [Team.red, Team.red, Team.blue, Team.blue],
      ];
      for (final teams in lineups) {
        final count = teams.length;
        for (var d = 0; d < count; d++) {
          final host = _host(deviceCount: count, deviceIndex: d, teams: teams);
          _reachPlaying(host);
          final cam = host.camera(const Size(1600, 800));
          final player = host.players[d];
          expect(
            cam.playRect.contains(cam.worldToScreen(player.x, player.y)),
            isTrue,
            reason: 'device $d in a $count-player game must see itself '
                'at kickoff (teams=$teams)',
          );
        }
      }
    });

    test('kick-off lanes follow the real team, not the roster index', () {
      final host = _host(
        deviceCount: 4,
        teams: const [Team.red, Team.red, Team.blue, Team.blue],
      );
      _reachPlaying(host);
      final center = host.pitch.centerX;
      expect(host.players[0].x, lessThan(center), reason: 'red seat 0');
      expect(host.players[1].x, lessThan(center),
          reason: 'red seat 1 must line up left even though its index is odd');
      expect(host.players[2].x, greaterThan(center), reason: 'blue seat 0');
      expect(host.players[3].x, greaterThan(center),
          reason: 'blue seat 1 must line up right even though its index is odd');
    });
  });

  group('goals & celebrations', () {
    test('ball crossing the left line inside the mouth scores for blue', () {
      final host = _host(deviceCount: 2);
      _reachPlaying(host);
      host.placeBall(-15, host.pitch.centerY);
      _run(host, 2);
      expect(host.blueScore, 1);
      expect(host.isCelebrating, isTrue);
      expect(host.scoredBy, 1);
    });

    test('ball crossing the right line inside the mouth scores for red', () {
      final host = _host(deviceCount: 2);
      _reachPlaying(host);
      host.placeBall(
        host.pitch.worldWidth + 15,
        host.pitch.centerY,
      );
      _run(host, 2);
      expect(host.redScore, 1);
      expect(host.isCelebrating, isTrue);
      expect(host.scoredBy, 0);
    });

    test('celebration freezes the field, then resets to kick off', () {
      final host = _host(deviceCount: 2);
      _reachPlaying(host);
      host.placeBall(-15, host.pitch.centerY);
      _run(host, 2);
      expect(host.isCelebrating, isTrue);

      final frozenPlayerX = host.players[0].x;
      host.setLocalInput(moveX: 1, moveY: 0, firing: false);
      _run(host, 6);
      expect(host.players[0].x, frozenPlayerX);

      _run(host, 60);
      expect(host.blueScore, 1);
      expect(host.isCelebrating, isFalse);
      expect(host.ballX, host.pitch.centerX);
      expect(host.players[0].x, lessThan(host.pitch.centerX));
    });

    test('score limit ends the match with a winner', () {
      final host = _host(
        deviceCount: 2,
        rules: const FutbolRules(
          calibrationSeconds: 0.2,
          countdownSeconds: 0.2,
          celebrationSeconds: 0.2,
          matchDurationSeconds: 0,
          scoreLimit: 1,
        ),
      );
      _reachPlaying(host);
      host.placeBall(
        host.pitch.worldWidth + 15,
        host.pitch.centerY,
      );
      _run(host, 2);
      expect(host.phase, FutbolMatchPhase.finished);
      expect(host.winnerIndex, 0);
    });

    test('match duration can end the game in a draw', () {
      final host = FutbolMatchController(
        matrix: MatrixLayoutManager().matrixForPlayerCount(2),
        deviceCount: 2,
        isHost: true,
        rules: const FutbolRules(
          calibrationSeconds: 0.2,
          countdownSeconds: 0.2,
          matchDurationSeconds: 1.0,
          scoreLimit: 0,
        ),
      );
      _reachPlaying(host);
      _run(host, 90);
      expect(host.phase, FutbolMatchPhase.finished);
      expect(host.winnerIndex, isNull);
    });
  });

  group('pause & resume', () {
    test('host pause freezes the match for everyone until resumed', () {
      final bus = _Bus();
      final host = _host(adapter: bus);
      final client = _client(adapter: bus);
      bus
        ..host = host
        ..client = client;

      host.start();
      for (var i = 0; i < 60; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      expect(host.phase, FutbolMatchPhase.playing);

      host.requestPause(true);
      expect(host.isPaused, isTrue);
      for (var i = 0; i < 5; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      expect(client.isPaused, isTrue,
          reason: 'the paused phase must reach clients');

      final ballX = host.ballX;
      final clockBefore = host.matchClock;
      for (var i = 0; i < 60; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      expect(host.ballX, ballX, reason: 'the paused field must not move');
      expect(host.matchClock, clockBefore,
          reason: 'the paused match clock must not advance');

      host.requestPause(false);
      expect(host.isPaused, isFalse);
      for (var i = 0; i < 5; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      expect(client.isPaused, isFalse,
          reason: 'the resume phase must reach clients');
      expect(host.matchClock, greaterThan(clockBefore));
    });

    test('a client requestPause forwards to the host via the bus', () {
      final bus = _Bus();
      final host = _host(adapter: bus);
      final client = _client(adapter: bus);
      bus
        ..host = host
        ..client = client;

      client.requestPause(true);
      expect(host.isPaused, isTrue,
          reason: 'the host must apply the client request');
      expect(client.isPaused, isTrue,
          reason: 'the in-memory bus delivers the paused phase synchronously');

      client.requestPause(false);
      expect(host.isPaused, isFalse);
      expect(client.isPaused, isFalse);
    });

    test('a fresh snapshot heals a client stuck paused', () {
      final bus = _Bus();
      final host = _host(adapter: bus);
      final client = _client(adapter: bus);
      bus
        ..host = host
        ..client = client;

      host.start();
      for (var i = 0; i < 60; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      expect(client.phase, FutbolMatchPhase.playing);

      // Client gets paused through the phase channel…
      client.applyRemotePhase(const MatrixPhaseMessage(
        phase: MatrixMatchPhase.playing,
        remainingSeconds: 0,
        paused: true,
      ));
      expect(client.isPaused, isTrue);

      // …and the next regular snapshot (which never carries a phase message)
      // unpauses it, so a dropped resume packet cannot strand the device.
      for (var i = 0; i < 5; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      expect(client.isPaused, isFalse,
          reason: 'snapshots must carry the paused flag so a dropped resume '
              'phase packet self-heals');
    });
  });

  group('client sync', () {
    test('client mirrors ball, phase and score via bus', () {
      final bus = _Bus();
      final host = _host(adapter: bus);
      final client = _client(adapter: bus);
      bus
        ..host = host
        ..client = client;

      host.start();
      for (var i = 0; i < 60; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      expect(client.phase, FutbolMatchPhase.playing);

      host.placeBall(1400, 300);
      for (var i = 0; i < 30; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      final frame = client.renderFrame();
      expect(frame.ballX, closeTo(1400, 40));
      expect(frame.redScore, host.redScore);
      expect(frame.blueScore, host.blueScore);
    });

    test('goal celebration is pushed to clients', () {
      final bus = _Bus();
      final host = _host(adapter: bus);
      final client = _client(adapter: bus);
      bus
        ..host = host
        ..client = client;

      host.start();
      for (var i = 0; i < 30; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      host.placeBall(-15, host.pitch.centerY);
      for (var i = 0; i < 10; i++) {
        host.step(1 / 60);
        client.step(1 / 60);
      }
      expect(client.isCelebrating, isTrue);
      expect(client.blueScore, 1);
      expect(client.scoredBy, 1);
    });
  });
}