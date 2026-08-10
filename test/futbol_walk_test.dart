import 'package:flutter_test/flutter_test.dart';
import 'package:screen_shift/features/matrix_arena/domain/matrix_grid.dart';
import 'package:screen_shift/features/matrix_arena/domain/matrix_snapshots.dart';
import 'package:screen_shift/features/matrix_futbol/game/futbol_interpolation.dart';
import 'package:screen_shift/features/matrix_futbol/game/futbol_match_controller.dart';
import 'package:screen_shift/features/matrix_futbol/game/futbol_walk_animator.dart';

MatrixPlayerSnapshot _snap(int index, double x, double y,
        {bool keeper = false}) =>
    MatrixPlayerSnapshot(
      deviceIndex: index,
      name: 'P$index',
      x: x,
      y: y,
      facingYaw: 0,
      hp: 1,
      maxHp: 1,
      alive: true,
      kills: 0,
      tileX: 0,
      tileY: 0,
      columns: 2,
      rows: 2,
      isGoalkeeper: keeper,
    );

FutbolMatchController _host({int deviceCount = 2}) {
  return FutbolMatchController(
    matrix: MatrixLayoutManager().matrixForPlayerCount(deviceCount),
    deviceCount: deviceCount,
    isHost: true,
    rules: const FutbolRules(
      calibrationSeconds: 0.2,
      countdownSeconds: 0.2,
      celebrationSeconds: 0.3,
      matchDurationSeconds: 0,
      scoreLimit: 5,
    ),
  );
}

void main() {
  group('FutbolWalkAnimator', () {
    test('idle players keep zero stride and zero phase', () {
      final walk = FutbolWalkAnimator();
      walk.advance(1 / 60, [_snap(0, 0, 0)]);
      walk.advance(1 / 60, [_snap(0, 0, 0)]);
      expect(walk.strideFor(0), 0);
      expect(walk.phaseFor(0), 0);
    });

    test('a sprinting player accumulates phase from distance travelled', () {
      final walk = FutbolWalkAnimator();
      walk.advance(1 / 60, [_snap(0, 0, 0)]);
      // 26 world units at 260 u/s over 0.1 s: one full-speed step.
      walk.advance(0.1, [_snap(0, 26, 0)]);
      expect(walk.phaseFor(0), closeTo(2 * 3.141592653589793 * 26 / 80, 0.001));
      // The stride ramps toward the sprint target (capped by the approach
      // rate), then saturates at 1 as the player keeps running.
      expect(walk.strideFor(0), closeTo(0.6, 0.001));
      walk.advance(0.1, [_snap(0, 52, 0)]);
      expect(
        walk.phaseFor(0),
        closeTo(2 * 3.141592653589793 * 52 / 80, 0.001),
      );
      expect(walk.strideFor(0), 1);
    });

    test('stride decays back to zero once the player stops', () {
      final walk = FutbolWalkAnimator();
      walk.advance(1 / 60, [_snap(0, 0, 0)]);
      walk.advance(0.1, [_snap(0, 26, 0)]);
      expect(walk.strideFor(0), greaterThan(0.5));
      for (var i = 0; i < 60; i++) {
        walk.advance(1 / 60, [_snap(0, 26, 0)]);
      }
      expect(walk.strideFor(0), 0);
    });

    test('goalkeepers never animate feet', () {
      final walk = FutbolWalkAnimator();
      walk.advance(1 / 60, [_snap(0, 0, 0, keeper: true)]);
      walk.advance(0.1, [_snap(0, 26, 0, keeper: true)]);
      expect(walk.strideFor(0), 0);
      expect(walk.phaseFor(0), 0);
    });
  });

  group('walk animation wiring', () {
    test('moving players animate and idle players settle back down', () {
      final host = _host();
      host.start();
      for (var i = 0; i < 26; i++) {
        host.step(1 / 60);
      }
      expect(host.phase, FutbolMatchPhase.playing);
      expect(host.walk.strideFor(0), 0,
          reason: 'no input means no running, so no feet');

      // Hold right: the player runs and the feet start swinging.
      host.setLocalInput(moveX: 1, moveY: 0, firing: false);
      for (var i = 0; i < 40; i++) {
        host.step(1 / 60);
      }
      expect(host.walk.strideFor(0), greaterThan(0.5),
          reason: 'a sprinting player must swing its feet');
      expect(host.walk.phaseFor(0), greaterThan(0));

      // Let go: the player stops and the feet tuck back under the body.
      host.setLocalInput(moveX: 0, moveY: 0, firing: false);
      for (var i = 0; i < 60; i++) {
        host.step(1 / 60);
      }
      expect(host.walk.strideFor(0), 0,
          reason: 'an idle player must show no feet');
    });
  });
}
