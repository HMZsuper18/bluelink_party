import 'dart:async';

import '../../../network/client_service.dart';
import '../../../network/host_service.dart';
import '../domain/matrix_snapshots.dart';
import 'matrix_arena_controller.dart';
import 'matrix_sync_adapter.dart';

class MatrixHostTransport implements MatrixSyncAdapter {
  MatrixHostTransport(
    this._host, {
    required this.localPlayerId,
    required List<String> rosterIds,
  }) : _rosterIds = List.of(rosterIds) {
    _inputSub = _host.gameInputPackets.listen(_applyInput);
    _commandSub = _host.gameCommandPackets.listen(_applyCommand);
  }

  final HostService _host;

  final String localPlayerId;
  final List<String> _rosterIds;

  StreamSubscription<Map<String, dynamic>>? _inputSub;
  StreamSubscription<Map<String, dynamic>>? _commandSub;
  MatrixArenaController? _controller;
  bool _disposed = false;

  void attach(MatrixArenaController controller) {
    _controller = controller;
  }

  void _applyCommand(Map<String, dynamic> packet) {
    final controller = _controller;
    if (controller == null) return;
    switch (PauseControlKey.fromKey(packet['command'] as String?)) {
      case PauseControlKey.pause:
        controller.pause();
      case PauseControlKey.resume:
        controller.resume();
      case null:
        break;
    }
  }

  void _applyInput(Map<String, dynamic> packet) {
    final controller = _controller;
    if (controller == null) return;
    final playerId = packet['playerId'] as String?;
    if (playerId == null) return;
    final deviceIndex = _rosterIds.indexOf(playerId);
    if (deviceIndex < 0) return;
    controller.applyRemoteInput(MatrixInput(
      deviceIndex: deviceIndex,
      moveX: (packet['moveX'] as num?)?.toDouble() ?? 0,
      moveY: (packet['moveY'] as num?)?.toDouble() ?? 0,
      firing: packet['firing'] as bool? ?? false,
    ));
  }

  @override
  void sendInput(MatrixInput input) {}

  @override
  void requestPause(bool paused) {
    // The host applies pause/resume requests directly on its controller.
  }

  @override
  void sendSnapshot(MatrixWorldSnapshot snapshot) {
    _host.broadcastGameState(snapshot.toJson());
  }

  @override
  void sendPhase(MatrixPhaseMessage phase) {
    _host.broadcastGameState(phase.toJson());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _inputSub?.cancel();
    _commandSub?.cancel();
  }
}

class MatrixClientTransport implements MatrixSyncAdapter {
  MatrixClientTransport(
    this._client, {
    required this.localPlayerId,
    required this.deviceIndex,
  }) {
    _stateSub = _client.gameStates.listen(_applyMessage);
  }

  final ClientService _client;

  final String localPlayerId;
  final int deviceIndex;

  StreamSubscription<Map<String, dynamic>>? _stateSub;
  MatrixArenaController? _controller;
  bool _disposed = false;

  void attach(MatrixArenaController controller) {
    _controller = controller;
  }

  void _applyMessage(Map<String, dynamic> payload) {
    final controller = _controller;
    if (controller == null) return;
    final phaseKey = payload['p'];
    if (phaseKey is String) {
      controller.applyRemotePhase(MatrixPhaseMessage(
        phase: matrixPhaseFromKey(phaseKey),
        remainingSeconds: (payload['r'] as num?)?.toDouble() ?? 0,
        winnerIndex: (payload['w'] as num?)?.toInt(),
        paused: payload['z'] == true,
      ));
    }
    if (payload['s'] is! num) return;
    try {
      controller.applyRemoteSnapshot(MatrixWorldSnapshot.fromJson(payload));
    } catch (_) {}
  }

  @override
  void sendInput(MatrixInput input) {
    _client.sendGameInput(
      playerId: localPlayerId,
      moveX: input.moveX,
      moveY: input.moveY,
      firing: input.firing,
      seq: input.sequence,
    );
  }

  @override
  void requestPause(bool paused) {
    _client.sendGameCommand(
      from: localPlayerId,
      command: (paused ? PauseControlKey.pause : PauseControlKey.resume).key,
    );
  }

  @override
  void sendSnapshot(MatrixWorldSnapshot snapshot) {}

  @override
  void sendPhase(MatrixPhaseMessage phase) {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateSub?.cancel();
  }
}