import 'package:flutter_test/flutter_test.dart';

import 'package:bluelink_party/data/models/game_mode.dart';
import 'package:bluelink_party/data/models/game_phase.dart';
import 'package:bluelink_party/data/models/match_config.dart';
import 'package:bluelink_party/data/models/match_event.dart';
import 'package:bluelink_party/data/models/player_slot.dart';
import 'package:bluelink_party/data/models/team.dart';
import 'package:bluelink_party/dev/lab/app_bot_lab.dart';
import 'package:bluelink_party/dev/lab/matrix_device_lab.dart'
    show LabPlatformBridge;
import 'package:bluelink_party/features/matrix_arena/domain/matrix_grid.dart';
import 'package:bluelink_party/features/matrix_arena/domain/matrix_snapshots.dart';
import 'package:bluelink_party/features/matrix_arena/game/matrix_arena_controller.dart';
import 'package:bluelink_party/features/matrix_arena/game/matrix_transport_sync.dart';
import 'package:bluelink_party/network/host_service.dart';

/// Loopback e2e: the bot swarm is a real lobby client like a real phone. It
/// discovers the host, joins, claims a seat, and mirrors a Screen Shift match
/// once it starts. Sockets are real, so this must not run in parallel with
/// other e2e suites.
void main() {
  test('bot swarm joins a hosted lobby and follows into a screen shift match',
      () async {
    final host = HostService(
      bridge: LabPlatformBridge(),
      playerId: 'test-host',
      playerName: 'Test Host',
    );
    await host.startHosting(lobbyName: 'app-bot-lab-e2e');
    host.claimSlot(Team.red);

    final swarm = AppBotSwarm(botCount: 2, requiredLobbyName: 'app-bot-lab-e2e');
    await swarm.start();

    var joins = 0;
    for (var i = 0; i < 120 && joins < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      joins = swarm.joinedCount;
    }
    expect(joins, 2, reason: 'bots discover and join the lobby');

    const rosterIds = ['test-host', 'bot-1', 'bot-2'];
    final config = MatchConfig(
      mode: GameMode.screenShift,
      players: const [
        PlayerSlot(team: Team.red, seat: 0, playerId: 'test-host', playerName: 'Test Host'),
        PlayerSlot(team: Team.blue, seat: 0, playerId: 'bot-1', playerName: 'Bot 1'),
        PlayerSlot(team: Team.blue, seat: 1, playerId: 'bot-2', playerName: 'Bot 2'),
      ],
    );

    final matrix = MatrixLayoutManager().matrixForPlayerCount(3);
    final transport = MatrixHostTransport(
      host,
      localPlayerId: 'test-host',
      rosterIds: rosterIds,
    );
    final hostController = MatrixArenaController(
      matrix: matrix,
      deviceCount: 3,
      isHost: true,
      deviceIndex: 0,
      adapter: transport,
      calibrationDuration: 1,
      countdownDuration: 1,
    );
    transport.attach(hostController);

    host.pushMatchEvent(MatchEvent(phase: GamePhase.countdown, config: config));

    for (var i = 0; i < 80; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      swarm.tick(1 / 60);
      hostController.step(1 / 60);
    }

    for (final bot in swarm.bots) {
      expect(bot.matrixController, isNotNull, reason: '${bot.name} mirror');
      expect(
        bot.matrixController!.phase,
        anyOf(MatrixMatchPhase.countdown, MatrixMatchPhase.playing),
        reason: '${bot.name} phase',
      );
    }

    transport.dispose();
    hostController.dispose();
    swarm.dispose();
    await host.dispose();
  });
}