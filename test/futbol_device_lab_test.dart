import 'package:flutter_test/flutter_test.dart';

import 'package:bluelink_party/dev/lab/futbol_device_lab.dart';
import 'package:bluelink_party/features/matrix_futbol/game/futbol_interpolation.dart';

void main() {
  test('memory futom lab boots 4 devices into playing', () async {
    final lab = FutbolDeviceLab(playerCount: 4, scoreLimit: 3);
    await lab.start();
    expect(lab.devicesLive.length, 4);
    expect(lab.hostController, isNotNull);
    expect(lab.hostController!.isHost, isTrue);

    for (var i = 0; i < 6 * 60; i++) {
      lab.step(1 / 60);
    }

    final host = lab.hostController!;
    expect(host.phase, FutbolMatchPhase.playing);
    expect(lab.hostController!.renderFrame().players.length, 4);
    final frame = host.renderFrame();
    expect(frame.ballX, greaterThan(0));
    expect(frame.ballY, greaterThan(0));
    for (final device in lab.devicesLive) {
      final deviceFrame = device.controller.renderFrame();
      expect(deviceFrame.phase, FutbolMatchPhase.playing);
    }
    lab.dispose();
  });

  test('futbol bots score and a winner is decided', () async {
    final lab = FutbolDeviceLab(playerCount: 2, scoreLimit: 1);
    await lab.start();

    var goals = 0;
    for (var i = 0; i < 6 * 60 * 30 && !lab.isOver; i++) {
      lab.step(1 / 60);
      final host = lab.hostController!;
      goals = host.redScore + host.blueScore;
      if (goals > 0) break;
    }
    expect(goals, greaterThan(0));
    expect(lab.winnerTeam, isNotNull);
    lab.dispose();
  });

  test('client controllers remain in lockstep with host scores', () async {
    final lab = FutbolDeviceLab(playerCount: 3, scoreLimit: 2);
    await lab.start();

    for (var i = 0; i < 6 * 60 * 45 && !lab.isOver; i++) {
      lab.step(1 / 60);
    }
    final host = lab.hostController!;
    for (final device in lab.devicesLive) {
      final controller = device.controller;
      expect(controller.redScore, host.redScore);
      expect(controller.blueScore, host.blueScore);
    }
    lab.dispose();
  });

  test('3p futbol (2v1) spawns a goalkeeper on the outnumbered team', () async {
    final lab = FutbolDeviceLab(playerCount: 3, scoreLimit: 3);
    await lab.start();

    final host = lab.hostController!;
    final keepers = host.players.where((p) => p.isGoalkeeper).toList();
    expect(keepers.length, 1);
    final keeper = keepers.single;
    expect(keeper.deviceIndex.isOdd, isTrue,
        reason: 'blue is the outnumbered side with 3 players');
    lab.dispose();
  });

  test('goalkeeper only slides along the goal line and never leaves x',
      () async {
    final lab = FutbolDeviceLab(playerCount: 3, scoreLimit: 5);
    await lab.start();

    final host = lab.hostController!;
    for (var i = 0; i < 6 * 60 * 20; i++) {
      lab.step(1 / 60);
      final keeper = host.players.firstWhere((p) => p.isGoalkeeper);
      final keeperX = keeper.x;
      final expectedX = host.pitch.worldWidth -
          (host.pitch.goalInset + host.rules.playerRadius * 0.8);
      expect(
        (keeperX - expectedX).abs(),
        lessThan(1e-6),
        reason: 'x must stay fixed on the goal line (iter $i)',
      );
    }
    lab.dispose();
  });

  test('goalkeeper never stops moving along the goal line', () async {
    final lab = FutbolDeviceLab(playerCount: 3, scoreLimit: 5);
    await lab.start();

    final host = lab.hostController!;
    late double previousY;
    final yChanges = <double>[];
    for (var i = 0; i < 6 * 60; i++) {
      lab.step(1 / 60);
      final keeper = host.players.firstWhere((p) => p.isGoalkeeper);
      if (i == 0) {
        previousY = keeper.y;
        continue;
      }
      yChanges.add((keeper.y - previousY).abs());
      previousY = keeper.y;
    }
    expect(yChanges.length, greaterThan(0));
    final movingFrames =
        yChanges.where((delta) => delta > 1e-9).length;
    expect(movingFrames, greaterThan(0),
        reason: 'keeper must keep sliding every frame it has a target');
    lab.dispose();
  });

  test('goalkeeper stays inside its goal mouth', () async {
    final lab = FutbolDeviceLab(playerCount: 3, scoreLimit: 5);
    await lab.start();

    final host = lab.hostController!;
    for (var i = 0; i < 6 * 60 * 10; i++) {
      lab.step(1 / 60);
      final keeper = host.players.firstWhere((p) => p.isGoalkeeper);
      expect(
        keeper.y,
        inInclusiveRange(host.pitch.rightGoalTop, host.pitch.rightGoalBottom),
        reason: 'keeper must slide within its goal mouth (iter $i)',
      );
    }
    lab.dispose();
  });

  test('goalkeeper flag survives the wire snapshot', () async {
    final lab = FutbolDeviceLab(playerCount: 3, scoreLimit: 3);
    await lab.start();

    final host = lab.hostController!;
    final frame = host.renderFrame();
    final keeperOnFrame =
        frame.players.where((p) => p.isGoalkeeper).toList();
    expect(keeperOnFrame.length, 1);
    expect(frame.players.length, 4,
        reason: '3 humans + 1 goalkeeper on the frame');

    for (final device in lab.devicesLive) {
      final deviceFrame = device.controller.renderFrame();
      final seen = deviceFrame.players.where((p) => p.isGoalkeeper).length;
      expect(seen, 1,
          reason: 'client ${device.deviceIndex} must render the keeper too');
    }
    lab.dispose();
  });

  test('1v1 and 2v2 games get no goalkeeper', () async {
    for (final playerCount in [2, 4]) {
      final lab = FutbolDeviceLab(playerCount: playerCount, scoreLimit: 3);
      await lab.start();
      final host = lab.hostController!;
      expect(
        host.players.where((p) => p.isGoalkeeper).length,
        0,
        reason: '$playerCount-player match is balanced',
      );
      lab.dispose();
    }
  });
}