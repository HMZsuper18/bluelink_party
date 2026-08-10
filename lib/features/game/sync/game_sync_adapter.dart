import 'dart:async';

import '../../../network/client_service.dart';
import '../../../network/host_service.dart';
import 'game_snapshot.dart';

/// Global controls a device may send the host. The host is the only authority
/// that actually mutates the world; clients only forward these requests.
enum GameCommand {
  pause('pause'),
  resume('resume'),
  restart('restart'),
  quit('quit');

  const GameCommand(this.key);

  final String key;

  static GameCommand? fromKey(String? key) {
    for (final c in GameCommand.values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// Inbound network messages a [GameBloc] turns into domain events.
sealed class GameSyncEvent {
  const GameSyncEvent();
}

class RemoteInputEvent extends GameSyncEvent {
  const RemoteInputEvent({
    required this.playerId,
    required this.moveX,
    required this.moveY,
    required this.firing,
  });

  final String playerId;
  final double moveX;
  final double moveY;
  final bool firing;
}

class RemoteReadyEvent extends GameSyncEvent {
  const RemoteReadyEvent({required this.playerId, required this.ready});

  final String playerId;
  final bool ready;
}

class RemoteCommandEvent extends GameSyncEvent {
  const RemoteCommandEvent(this.command);

  final GameCommand command;
}

class RemoteSnapshotEvent extends GameSyncEvent {
  const RemoteSnapshotEvent(this.snapshot);

  final GameSnapshot snapshot;
}

/// Transport-agnostic gateway between a running [GameBloc] and the network.
///
/// The host owns the authoritative simulation and broadcasts snapshots; clients
/// send their intent (input / ready / command) and replay the host's snapshots
/// instead of simulating locally.
abstract class GameSyncAdapter {
  bool get isHost;
  String get localPlayerId;
  Stream<GameSyncEvent> get events;

  /// Host: push the authoritative state to every client. Client: no-op.
  void broadcastSnapshot(GameSnapshot snapshot);

  /// Client -> host: report this device's movement / fire intent.
  void sendInput({required double moveX, required double moveY, required bool firing});

  /// Device -> host: toggle this device's own ready-to-continue state.
  void sendReady({required String playerId, required bool ready});

  /// Device -> host: request a global control (pause / resume / restart / quit).
  void sendCommand(GameCommand command);

  /// Notifies the network layer that this device left the game screen.
  void dispose();
}

/// Local-only adapter: no network. Simulation runs on the single device.
class NoopGameSyncAdapter implements GameSyncAdapter {
  NoopGameSyncAdapter({required this.localPlayerId});

  @override
  final String localPlayerId;

  @override
  bool get isHost => true;

  @override
  Stream<GameSyncEvent> get events => const Stream.empty();

  @override
  void broadcastSnapshot(GameSnapshot snapshot) {}

  @override
  void sendInput({required double moveX, required double moveY, required bool firing}) {}

  @override
  void sendReady({required String playerId, required bool ready}) {}

  @override
  void sendCommand(GameCommand command) {}

  @override
  void dispose() {}
}

/// Host-side adapter: receives client input/ready/command packets.
class HostGameSyncAdapter implements GameSyncAdapter {
  HostGameSyncAdapter(this._host, {required this.localPlayerId}) {
    _inputsSub = _host.gameInputPackets.listen((p) {
      _sink.add(RemoteInputEvent(
        playerId: p['playerId'] as String,
        moveX: (p['moveX'] as num).toDouble(),
        moveY: (p['moveY'] as num).toDouble(),
        firing: p['firing'] as bool? ?? false,
      ));
    });
    _readySub = _host.gameReadyPackets.listen((p) {
      _sink.add(RemoteReadyEvent(
        playerId: p['playerId'] as String,
        ready: p['ready'] as bool? ?? true,
      ));
    });
    _commandSub = _host.gameCommandPackets.listen((p) {
      final command = GameCommand.fromKey(p['command'] as String?);
      if (command != null) _sink.add(RemoteCommandEvent(command));
    });
  }

  final HostService _host;

  @override
  final String localPlayerId;

  final StreamController<GameSyncEvent> _sink =
      StreamController<GameSyncEvent>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _inputsSub;
  StreamSubscription<Map<String, dynamic>>? _readySub;
  StreamSubscription<Map<String, dynamic>>? _commandSub;

  @override
  bool get isHost => true;

  @override
  Stream<GameSyncEvent> get events => _sink.stream;

  @override
  void broadcastSnapshot(GameSnapshot snapshot) {
    _host.broadcastGameState(snapshot.toMap());
  }

  @override
  void sendInput({required double moveX, required double moveY, required bool firing}) {}

  @override
  void sendReady({required String playerId, required bool ready}) {}

  @override
  void sendCommand(GameCommand command) {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _inputsSub?.cancel();
    _readySub?.cancel();
    _commandSub?.cancel();
    _sink.close();
  }

  bool _disposed = false;
}

/// Client-side adapter: sends intents to the host and replays host snapshots.
class ClientGameSyncAdapter implements GameSyncAdapter {
  ClientGameSyncAdapter(this._client, {required this.localPlayerId}) {
    _stateSub = _client.gameStates.listen((payload) {
      final snapshot = GameSnapshot.fromMap(payload);
      _sink.add(RemoteSnapshotEvent(snapshot));
    });
  }

  final ClientService _client;

  @override
  final String localPlayerId;

  final StreamController<GameSyncEvent> _sink =
      StreamController<GameSyncEvent>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _stateSub;
  int _seq = 0;

  @override
  bool get isHost => false;

  @override
  Stream<GameSyncEvent> get events => _sink.stream;

  @override
  void broadcastSnapshot(GameSnapshot snapshot) {}

  @override
  void sendInput({required double moveX, required double moveY, required bool firing}) {
    _client.sendGameInput(
      playerId: localPlayerId,
      moveX: moveX,
      moveY: moveY,
      firing: firing,
      seq: ++_seq,
    );
  }

  @override
  void sendReady({required String playerId, required bool ready}) {
    _client.sendGameReady(playerId: playerId, ready: ready);
  }

  @override
  void sendCommand(GameCommand command) {
    _client.sendGameCommand(from: localPlayerId, command: command.key);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateSub?.cancel();
    _sink.close();
  }

  bool _disposed = false;
}