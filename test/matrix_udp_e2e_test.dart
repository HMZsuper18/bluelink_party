// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:bluelink_party/data/models/game_mode.dart';
import 'package:bluelink_party/data/models/match_config.dart';
import 'package:bluelink_party/data/models/team.dart';
import 'package:bluelink_party/data/repositories/wifi_info_repository.dart';
import 'package:bluelink_party/features/matrix_arena/domain/matrix_grid.dart';
import 'package:bluelink_party/features/matrix_arena/domain/matrix_snapshots.dart';
import 'package:bluelink_party/features/matrix_arena/game/matrix_arena_controller.dart';
import 'package:bluelink_party/features/matrix_arena/game/matrix_transport_sync.dart';
import 'package:bluelink_party/network/client_service.dart';
import 'package:bluelink_party/network/host_service.dart';
import 'package:bluelink_party/network/protocol.dart';

class _FakeBridge extends PlatformBridge {
  @override
  Future<bool> acquireMulticastLock() async => true;

  @override
  Future<void> releaseMulticastLock() async {}
}

void main() {
  test(
      'real UDP Screen Shift: client sees its own tile only, host moves the '
      'client player via remote input', () async {
    final host = HostService(
      bridge: _FakeBridge(),
      playerId: 'h1',
      playerName: 'Host',
    );
    final client = ClientService(playerId: 'c1', playerName: 'Guest');

    try {
      await host.startHosting();
      host.claimSlot(Team.red);
      final found = await client.discover();
      final lobby = found.firstWhere(
        (l) => l.hostPort != NetConstants.hostPort,
        orElse: () => found.first,
      );
      final joinError =
          await client.join(lobby).timeout(const Duration(seconds: 8));
      expect(joinError, isNull);
      final claimError = await client.claimSlot(Team.blue);
      expect(claimError, isNull);

      final room = await client.snapshots.first.then((s) => s.room);
      final config = MatchConfig(
        mode: GameMode.screenShift,
        players: [
          for (final team in Team.all)
            for (final slot in room.slotsOf(team))
              if (slot.isFilled) slot,
        ],
      );

      final rosterIds = [
        for (final slot in config.players) slot.playerId ?? '',
      ];
      final hostTransport = MatrixHostTransport(
        host,
        localPlayerId: 'h1',
        rosterIds: rosterIds,
      );
      final clientTransport = MatrixClientTransport(
        client,
        localPlayerId: 'c1',
        deviceIndex: 1,
      );
      final hostController = MatrixArenaController(
        matrix: MatrixLayoutManager().matrixForPlayerCount(2),
        deviceCount: 2,
        isHost: true,
        adapter: hostTransport,
        calibrationDuration: 0.05,
        countdownDuration: 0.05,
      );
      final clientController = MatrixArenaController(
        matrix: MatrixLayoutManager().matrixForPlayerCount(2),
        deviceCount: 2,
        isHost: false,
        deviceIndex: 1,
        adapter: clientTransport,
      );
      hostTransport.attach(hostController);
      clientTransport.attach(clientController);

      expect(hostController.phase, MatrixMatchPhase.calibrating);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(clientController.phase, MatrixMatchPhase.calibrating,
          reason: 'client must receive the calibration phase over UDP');

      var ticks = 0;
      while (hostController.phase != MatrixMatchPhase.playing && ticks < 600) {
        hostController.step(1 / 60);
        await Future<void>.delayed(const Duration(milliseconds: 2));
        ticks++;
      }
      expect(hostController.phase, MatrixMatchPhase.playing,
          reason: 'host must reach playing after calibration+countdown');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(clientController.phase, MatrixMatchPhase.playing,
          reason: 'client must be told the match is playing');

      final h1Before =
          clientController.players.firstWhere((p) => p.deviceIndex == 0).x;
      final c1BeforeOnHost =
          hostController.players.firstWhere((p) => p.deviceIndex == 1).x;

      hostController.setLocalInput(moveX: 1, moveY: 0, firing: false);
      clientController.setLocalInput(moveX: -1, moveY: 0, firing: true);

      ticks = 0;
      while (ticks < 120) {
        hostController.step(1 / 60);
        await Future<void>.delayed(const Duration(milliseconds: 2));
        ticks++;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final h1After =
          clientController.players.firstWhere((p) => p.deviceIndex == 0).x;
      final c1AfterOnHost =
          hostController.players.firstWhere((p) => p.deviceIndex == 1).x;

      expect(h1After, isNot(h1Before),
          reason: 'client must see host movement via broadcast snapshots');
      expect(c1AfterOnHost, isNot(c1BeforeOnHost),
          reason: 'client gameInput must reach and move its player on the host');
      expect(hostController.projectiles, isNotEmpty,
          reason: 'client firing must spawn projectiles on the host world');

      expect(clientController.localTile.column, 1,
          reason: 'client tile must be its own slice, not the whole battlefield');

      // Pause the shared match from the client device over the wire.
      clientController.requestPause(true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(hostController.isPaused, isTrue,
          reason: 'host must apply the client pause command');
      expect(clientController.isPaused, isTrue,
          reason: 'client must receive the paused phase back over UDP');

      // Let the client converge on the frozen frame the host re-broadcasts
      // while paused (pre-pause snapshots may still be in flight).
      for (var i = 0; i < 40; i++) {
        hostController.step(1 / 60);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final frozenH1X = clientController.players
          .firstWhere((p) => p.deviceIndex == 0)
          .x;
      for (var i = 0; i < 40; i++) {
        hostController.step(1 / 60);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final frozenH1XAfter = clientController.players
          .firstWhere((p) => p.deviceIndex == 0)
          .x;
      expect(frozenH1XAfter, frozenH1X,
          reason: 'host must keep broadcasting the frozen frame while paused');

      clientController.requestPause(false);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(hostController.isPaused, isFalse,
          reason: 'host must apply the client resume command');
      expect(clientController.isPaused, isFalse,
          reason: 'client must receive the resume phase back over UDP');

      hostTransport.dispose();
      clientTransport.dispose();
    } finally {
      await host.dispose();
      await client.dispose();
    }
  });
}