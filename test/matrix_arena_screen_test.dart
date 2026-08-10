import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluelink_party/features/battle_sync/presentation/widgets/action_button.dart';
import 'package:bluelink_party/features/battle_sync/presentation/widgets/virtual_joystick.dart';
import 'package:bluelink_party/features/matrix_arena/domain/matrix_grid.dart';
import 'package:bluelink_party/features/matrix_arena/domain/matrix_snapshots.dart';
import 'package:bluelink_party/features/matrix_arena/game/matrix_arena_controller.dart';
import 'package:bluelink_party/features/matrix_arena/presentation/matrix_arena_screen.dart';

MatrixArenaController makeHost({int players = 2}) {
  return MatrixArenaController(
    matrix: MatrixLayoutManager().matrixForPlayerCount(players),
    deviceCount: players,
    isHost: true,
    calibrationDuration: 1,
    countdownDuration: 1,
  );
}

Future<MatrixArenaController> pumpScreen(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = makeHost();
  await tester.pumpWidget(
    MaterialApp(home: MatrixArenaScreen(controller: controller)),
  );
  // Let the screen's ticker drive a few frames.
  await tester.pump(const Duration(milliseconds: 120));
  return controller;
}

/// Advances fake time until the match reaches the playing phase.
Future<void> reachPlaying(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> expectBattleSyncControls(
  WidgetTester tester, {
  required Size size,
}) async {
  await pumpScreen(tester, size: size);

  final joystick = find.byType(VirtualJoystick);
  final fire = find.byType(ActionButton);
  expect(joystick, findsOneWidget,
      reason: 'a joystick must be rendered, not just a fire button');
  expect(fire, findsOneWidget);

  final joystickRect = tester.getRect(joystick);
  final fireRect = tester.getRect(fire);

  // Battle Sync control layout: joystick on the left, fire on the right,
  // both fully on screen and non-overlapping.
  expect(joystickRect.center.dx, lessThan(size.width / 2));
  expect(fireRect.center.dx, greaterThan(size.width / 2));
  expect(joystickRect.bottom, lessThanOrEqualTo(size.height));
  expect(fireRect.bottom, lessThanOrEqualTo(size.height));
  expect(joystickRect.right, lessThan(fireRect.left));
}

void main() {
  testWidgets('Screen Shift shows a joystick AND a fire button laid out like '
      'Battle Sync (movement is always available)', (tester) async {
    // Portrait phones hit the letterboxed fallback path (the bug report:
    // controls used to float mid-screen, so players saw a "centred" button
    // and no way to move).
    await expectBattleSyncControls(tester, size: const Size(390, 844));

    // Landscape phones hit the side-strip path; controls must stay docked.
    await expectBattleSyncControls(tester, size: const Size(844, 390));
  });

  testWidgets('dragging the joystick moves the local player (host sim)',
      (tester) async {
    final controller = await pumpScreen(tester);
    await reachPlaying(tester);
    expect(controller.phase, MatrixMatchPhase.playing);

    // Park the local player mid-arena so movement is unambiguous.
    final local = controller.players[0];
    local.x = 500;
    local.y = 300;
    final startX = local.x;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VirtualJoystick)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(milliseconds: 200));

    expect(local.vx, greaterThan(0),
        reason: 'joystick input must reach the authoritative simulation');
    expect(local.x, greaterThan(startX),
        reason: 'the player must physically move while the joystick is held');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 120));
    expect(local.vx, 0,
        reason: 'releasing the joystick stops the player');
  });
}
