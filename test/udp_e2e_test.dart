// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:bluelink_party/data/models/game_phase.dart';
import 'package:bluelink_party/data/models/match_config.dart';
import 'package:bluelink_party/data/models/match_event.dart';
import 'package:bluelink_party/data/models/team.dart';
import 'package:bluelink_party/features/game/bloc/game_bloc.dart';
import 'package:bluelink_party/features/game/bloc/game_event.dart';
import 'package:bluelink_party/features/game/sync/game_sync_adapter.dart';
import 'package:bluelink_party/network/client_service.dart';
import 'package:bluelink_party/network/host_service.dart';
import 'package:bluelink_party/data/repositories/wifi_info_repository.dart';
import 'package:bluelink_party/network/protocol.dart';

/// Stub for the Android multicast lock; loopback does not need it.
class _FakeBridge extends PlatformBridge {
  @override
  Future<bool> acquireMulticastLock() async => true;

  @override
  Future<void> releaseMulticastLock() async {}
}

void main() {
  test(
      'real UDP host+client: client joins, match starts, and BOTH players move '
      'on the client screen', () async {
    final host = HostService(
      bridge: _FakeBridge(),
      playerId: 'h1',
      playerName: 'Host',
    );
    final client = ClientService(playerId: 'c1', playerName: 'Guest');

    try {
      await host.startHosting();
      print("STEP host started"); expect(host.isHosting, isTrue);
      host.claimSlot(Team.red); print("STEP claimed red");

      // Real discovery over the wire.
      final found = await client.discover();
      print("STEP discover"); expect(found, isNotEmpty,
          reason: 'client must find the host over real UDP');
      // Skip other lobbies on machines sharing this network (e.g. the running
      // dev app on the default host port) and join the host this test started.
      final lobby = found.firstWhere(
        (l) => l.hostPort != NetConstants.hostPort,
        orElse: () => found.first,
      );
      final error = await client.join(lobby).timeout(const Duration(seconds: 8), onTimeout: () => "TIMEOUT1"); print("STEP joined err=$error");
      expect(error, isNull);
      final claimError = await client.claimSlot(Team.blue).timeout(const Duration(seconds: 8), onTimeout: () => "TIMEOUT"); print("STEP claim blue err=$claimError");
      expect(claimError, isNull);

      // Snapshot the room via the client's join ack (same as the lobby).
      final room = await client.snapshots.first.then((s) => s.room);
      print('STEP got room');
      final event = MatchEvent(
        phase: GamePhase.countdown,
        config: MatchConfig(players: [
          for (final team in Team.all)
            for (final slot in room.slotsOf(team))
              if (slot.isFilled) slot,
        ]),
      );

      final hostSync = HostGameSyncAdapter(host, localPlayerId: 'h1');
      final clientSync = ClientGameSyncAdapter(client, localPlayerId: 'c1');
      final hostBloc = GameBloc(sync: hostSync);
      final clientBloc = GameBloc(sync: clientSync);

      hostBloc.add(MatchStarted(event, localPlayerId: 'h1'));
      clientBloc.add(MatchStarted(event, localPlayerId: 'c1'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      hostBloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // The client must have entered the match via the host's broadcast.
      print("STEP awaiting inGame broadcast; HOST phase=${hostBloc.state.phase} players=${hostBloc.state.players.length} isPaused=${hostBloc.state.isPaused}"); expect(clientBloc.state.phase, GamePhase.inGame,
          reason: 'client must receive the host gameState broadcast');

      final h1Before =
          clientBloc.state.players.firstWhere((p) => p.id == 'h1').x;
      final c1Before =
          clientBloc.state.players.firstWhere((p) => p.id == 'c1').x;
      final c1BeforeOnHost =
          hostBloc.state.players.firstWhere((p) => p.id == 'c1').x;

      hostBloc.add(const PlayerInputChanged(moveX: 1));
      clientBloc.add(const PlayerInputChanged(moveX: -1, firing: true));
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final after = clientBloc.state;
      expect(
        after.players.firstWhere((p) => p.id == 'h1').x,
        isNot(h1Before),
        reason: 'client must see the host player move (host->client gameState)',
      );
      expect(
        after.players.firstWhere((p) => p.id == 'c1').x,
        isNot(c1Before),
        reason: 'host must move the client player (client->host gameInput)',
      );
      expect(
        hostBloc.state.players.firstWhere((p) => p.id == 'c1').x,
        isNot(c1BeforeOnHost),
        reason: 'the client input must reach and move its player on the host',
      );
      expect(
        after.projectiles,
        isNotEmpty,
        reason: 'the client shot must appear on the client screen '
            '(client->host gameInput -> host snapshot)',
      );

      await hostBloc.close();
      await clientBloc.close();
      hostSync.dispose();
      clientSync.dispose();
    } finally {
      await host.dispose();
      await client.dispose();
    }
  });
}
