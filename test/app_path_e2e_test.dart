// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:bluelink_party/data/models/team.dart';
import 'package:bluelink_party/data/repositories/wifi_info_repository.dart';
import 'package:bluelink_party/features/game/bloc/game_bloc.dart';
import 'package:bluelink_party/features/game/bloc/game_event.dart';
import 'package:bluelink_party/features/lobby/bloc/lobby_bloc.dart';
import 'package:bluelink_party/features/lobby/bloc/lobby_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stub for the Android multicast lock; loopback does not need it.
class _FakeBridge extends PlatformBridge {
  @override
  Future<bool> acquireMulticastLock() async => true;

  @override
  Future<void> releaseMulticastLock() async {}
}

Future<void> _waitUntil(
  bool Function() condition, {
  String reason = 'condition',
  Duration timeout = const Duration(seconds: 12),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timeout while waiting for: $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'app path: two LobbyBlocs over UDP, StartMatch, and the client bloc '
      'sees BOTH players move and shoot', () async {
    SharedPreferences.setMockInitialValues({});
    final hostLobby = LobbyBloc(bridge: _FakeBridge());
    final clientLobby = LobbyBloc(bridge: _FakeBridge());

    try {
      await _waitUntil(() => hostLobby.state.playerId.isNotEmpty,
          reason: 'host profile id loaded before creating the lobby');
      hostLobby.add(const SavePlayerName('AlexTestHost'));
      await _waitUntil(() => hostLobby.state.playerName == 'AlexTestHost',
          reason: 'host name saved');
      hostLobby.add(const CreateLobby());
      await _waitUntil(() => hostLobby.state.isHost,
          reason: 'host lobby created (UDP bound)');
      print('STEP host lobby up, name=${hostLobby.state.playerName}');

      hostLobby.add(const ClaimSlot(Team.red));
      clientLobby.add(const ScanForLobbies());
      await _waitUntil(() => clientLobby.state.foundLobbies.isNotEmpty,
          reason: 'client discovers the host');
      print('STEP client discovered ${clientLobby.state.foundLobbies.length} lobby(s): '
          '${clientLobby.state.foundLobbies.map((l) => l.lobbyName).join(', ')}');

      final target = clientLobby.state.foundLobbies.firstWhere(
        (l) => l.lobbyName == "AlexTestHost's Lobby",
        orElse: () => clientLobby.state.foundLobbies.first,
      );
      clientLobby.add(JoinDiscovered(target));
      await _waitUntil(() => clientLobby.state.isClient,
          reason: 'client joined the host lobby');
      clientLobby.add(const ClaimSlot(Team.blue));
      await _waitUntil(() => hostLobby.state.canStartMatch,
          reason: 'both seats filled on the host');

      hostLobby.add(const StartMatch());
      var twoReady = false;
      for (var i = 0; i < 80; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        twoReady = hostLobby.state.gameSync != null &&
            clientLobby.state.gameSync != null &&
            hostLobby.state.matchEvent != null &&
            clientLobby.state.matchEvent != null;
        if (twoReady) break;
      }
      print('STEP hostMatch=${hostLobby.state.matchEvent != null} '
          'hostSync=${hostLobby.state.gameSync != null} '
          'clientMatch=${clientLobby.state.matchEvent != null} '
          'clientSync=${clientLobby.state.gameSync != null} '
          'clientRole=${clientLobby.state.role} '
          'hostRole=${hostLobby.state.role} '
          'hostErr=${hostLobby.state.error} '
          'clientErr=${clientLobby.state.error}');
      expect(twoReady, isTrue,
          reason: 'both lobby blocs must hold the match event + sync adapter');

      final hostEvent = hostLobby.state.matchEvent!;
      final clientEvent = clientLobby.state.matchEvent!;
      expect(hostEvent.config.players.length, 2,
          reason: 'host roster must contain both players');
      expect(clientEvent.config.players.length, 2,
          reason: 'client roster must contain both players');

      final hostBloc = GameBloc(sync: hostLobby.state.gameSync)
        ..add(MatchStarted(hostEvent, localPlayerId: hostLobby.state.playerId));
      final clientBloc = GameBloc(sync: clientLobby.state.gameSync)
        ..add(MatchStarted(clientEvent, localPlayerId: clientLobby.state.playerId));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      hostBloc.add(const CountdownFinished());
      await _waitUntil(() => clientBloc.state.phase.name == 'inGame',
          reason: 'client bloc enters inGame via host snapshot');
      print('STEP both blocs inGame; client isAuthoritative=${clientBloc.isAuthoritative}');

      final h1Before =
          clientBloc.state.players.firstWhere((p) => p.id == hostLobby.state.playerId).x;
      final c1Before =
          clientBloc.state.players.firstWhere((p) => p.id == clientLobby.state.playerId).x;

      hostBloc.add(const PlayerInputChanged(moveX: 1));
      clientBloc.add(const PlayerInputChanged(moveX: -1, firing: true));
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final after = clientBloc.state;
      expect(
        after.players.firstWhere((p) => p.id == hostLobby.state.playerId).x,
        isNot(h1Before),
        reason: 'client screen must show the host player moving',
      );
      expect(
        after.players.firstWhere((p) => p.id == clientLobby.state.playerId).x,
        isNot(c1Before),
        reason: 'client player must move via host echo (input round trip)',
      );
      expect(
        hostBloc.state.players.firstWhere((p) => p.id == clientLobby.state.playerId).x,
        isNot(c1Before),
        reason: 'host must move the client player (client input reached host)',
      );

      print('STEP app-path movement sync verified (both directions, replica client)');

      await hostBloc.close();
      await clientBloc.close();
    } finally {
      hostLobby.add(const Disconnect());
      clientLobby.add(const Disconnect());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await hostLobby.close();
      await clientLobby.close();
    }
  });
}
