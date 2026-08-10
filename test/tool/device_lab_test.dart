// Headless virtual-device lab for Screen Shift.
//
// Run:  flutter test test/tool/device_lab_test.dart
//
// Options (--dart-define):
//   LAB_DEVICES   comma list of profile keys (phone-p, phone-l, tablet-p,
//                 tablet-l, desktop, ultrawide). Cycled when fewer than
//                 players; defaults to the desktop+tablet+phone mix.
//   LAB_PLAYERS   2, 3 or 4 (default 4)
//   LAB_TRANSPORT memory | udp (default memory; udp uses real loopback sockets)
//   LAB_SECONDS   sim seconds before asserting the match finished (default 14)
//   LAB_SEED      deterministic RNG seed (default 7)
//   LAB_OUT       output directory for PNGs + report.json (default tool/lab_out)
//
// Writes per-device frames and a mosaic overview into LAB_OUT, plus
// report.json, and fails the test when a per-device assertion breaks.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_shift/dev/lab/device_profile.dart';
import 'package:screen_shift/dev/lab/matrix_device_lab.dart';
import 'package:screen_shift/features/matrix_arena/domain/matrix_snapshots.dart';

const _envDevices = String.fromEnvironment('LAB_DEVICES');
const _envPlayers = String.fromEnvironment('LAB_PLAYERS');
const _envTransport = String.fromEnvironment('LAB_TRANSPORT');
const _envSeconds = String.fromEnvironment('LAB_SECONDS');
const _envSeed = String.fromEnvironment('LAB_SEED');
const _envOut = String.fromEnvironment('LAB_OUT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Screen Shift runs on N virtual devices of mixed sizes and ratios',
      () async {
    final outDir = Directory(
      _envOut.isEmpty ? 'tool/lab_out' : _envOut,
    );
    outDir.createSync(recursive: true);
    final devicesDir = Directory('${outDir.path}/frames');
    devicesDir.createSync(recursive: true);

    final players = _envPlayers.isEmpty ? 4 : int.parse(_envPlayers);
    final transport = _envTransport == 'udp'
        ? LabTransport.udp
        : LabTransport.memory;
    final seconds = _envSeconds.isEmpty ? 14.0 : double.parse(_envSeconds);
    final seed = _envSeed.isEmpty ? 7 : int.parse(_envSeed);
    final profiles = _envDevices.isEmpty
        ? const <VirtualDeviceProfile>[]
        : [
            for (final key in _envDevices.split(','))
              if (key.trim().isNotEmpty) VirtualDeviceProfile.fromKey(key),
          ];

    final lab = VirtualDeviceLab(
      playerCount: players,
      transport: transport,
      devices: profiles,
      playSeconds: seconds,
      calibrationSeconds: 0.5,
      countdownSeconds: 0.7,
      seed: seed,
      killsToWin: 1,
    );

    final assertions = <({String name, bool ok, String detail})>[];
    final deviceReports = <Map<String, dynamic>>[];
    var sawPlaying = false;
    var sawFinished = false;
    var renderedCount = 0;

    try {
      await lab.start();
      expect(lab.devicesLive.length, players,
          reason: 'one virtual device per player');

      final expectedColumns = switch (players) {
        2 => 2,
        3 => 2,
        4 => 2,
        _ => -1,
      };
      expect(lab.matrix.columns, expectedColumns);
      expect(lab.matrix.rows, players == 2 ? 1 : 2);

      final tickMs = 16;
      var simSeconds = 0.0;
      var tick = 0;
      while (!lab.isOver && simSeconds < seconds) {
        lab.step(tickMs / 1000);
        simSeconds += tickMs / 1000;
        tick++;

        if (lab.hostController!.phase == MatrixMatchPhase.playing) {
          sawPlaying = true;
        }
        if (lab.isOver) {
          sawFinished = true;
        }

        final snapshotAt = (tick % 30) == 0;
        if (snapshotAt) {
          for (final device in lab.devicesLive) {
            final counts = lab.visibleCounts(device);
            final ownTilePlayers = device.controller
                .renderFrame()
                .players
                .where((p) => p.deviceIndex == device.deviceIndex)
                .length;
            final painterOnScreen =
                counts.onScreen;
            final framePlayers = device.controller
                .renderFrame()
                .players
                .length;
            final painterPlayers = counts.inTile;
            final painterAnyOther = painterOnScreen > painterPlayers;
            if (!lab.isOver) {
              deviceReports.add({
                'tick': tick,
                'phase': lab.hostController!.phase.name,
                'onScreen': counts.onScreen,
                'inTile': counts.inTile,
                'ownTilePlayers': ownTilePlayers,
                'framePlayers': framePlayers,
                'painterPlayers': painterPlayers,
                'painterAnyOther': painterAnyOther,
              });
            }
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      assertions.add((
        name: 'reached_playing',
        ok: sawPlaying,
        detail: 'host phase advanced past calibration/countdown',
      ));

      if (sawFinished) {
        assertions.add((
          name: 'match_finished',
          ok: true,
          detail: 'winner=${lab.winnerIndex}',
        ));
      } else {
        assertions.add((
          name: 'match_finished',
          ok: false,
          detail: 'no winner within ${seconds}s',
        ));
      }

      for (final device in lab.devicesLive) {
        final frame = device.controller.renderFrame();
        final ownTilePlayers = frame.players
            .where((p) => p.deviceIndex == device.deviceIndex)
            .length;
        final counts = lab.visibleCounts(device);
        deviceReports.add({
          'device': device.deviceIndex,
          'isHost': device.isHost,
          'profile': device.profile.key,
          'label': device.profile.label,
          'width': device.profile.width,
          'height': device.profile.height,
          'aspect': device.profile.aspect.toStringAsFixed(3),
          'phase': lab.hostController!.phase.name,
          'localTileColumn': device.controller.localTile.column,
          'localTileRow': device.controller.localTile.row,
          'localTileWidth': device.controller.localTile.tileWidth,
          'localTileHeight': device.controller.localTile.tileHeight,
          'ownTilePlayers': ownTilePlayers,
          'onScreen': counts.onScreen,
          'inTile': counts.inTile,
        });
      }

      for (final device in lab.devicesLive) {
        final bytes = await device.renderPng();
        final file = File('${devicesDir.path}/${device.deviceIndex}_${device.profile.key}.png');
        file.writeAsBytesSync(bytes);
        renderedCount++;
      }
    } finally {
      lab.dispose();
    }

    final report = <String, dynamic>{
      'players': players,
      'transport': transport.name,
      'seed': seed,
      'seconds': seconds,
      'devices': deviceReports,
      'framesRendered': renderedCount,
    };
    File('${outDir.path}/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );

    for (final assertion in assertions) {
      print('[${assertion.ok ? 'PASS' : 'FAIL'}] ${assertion.name}: ${assertion.detail}');
    }
    for (final a in assertions) {
      expect(a.ok, isTrue, reason: '${a.name}: ${a.detail}');
    }
  });
}
