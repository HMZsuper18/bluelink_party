import 'dart:async';

import '../../../network/client_service.dart';
import '../../../network/host_service.dart';
import '../../matrix_arena/domain/matrix_snapshots.dart';
import '../../matrix_arena/game/matrix_sync_adapter.dart';
import 'futbol_match_controller.dart';

/// Host-side adapter: the host controller simulates the match and streams
/// snapshots/phase to every client over the lobby's game-state channel; remote
/// client input arrives through the host's input packet stream.
class FutbolHostTransport implements MatrixSyncAdapter {
  FutbolHostTransport(
    this._host, {
    required List<String> rosterIds,
  }) : _rosterIds = List.of(rosterIds) {
    _inputSub = _host.gameInputPackets.listen(_applyInput);
    _commandSub = _host.gameCommandPackets.listen(_applyCommand);
    _readySub = _host.gameReadyPackets.listen(_applyReady);
  }

  final HostService _host;
  final List<String> _rosterIds;

  StreamSubscription<Map<String, dynamic>>? _inputSub;
  StreamSubscription<Map<String, dynamic>>? _commandSub;
  StreamSubscription<Map<String, dynamic>>? _readySub;
  FutbolMatchController? _controller;
  bool _disposed = false;

  void attach(FutbolMatchController controller) {
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

  void _applyReady(Map<String, dynamic> packet) {
    final controller = _controller;
    if (controller == null) return;
    final playerId = packet['playerId'] as String?;
    if (playerId == null) return;
    final deviceIndex = _rosterIds.indexOf(playerId);
    if (deviceIndex < 0) return;
    controller.setReady(
      deviceIndex,
      ready: packet['ready'] as bool? ?? true,
    );
  }

  void _applyInput(Map<String, dynamic> packet) {
    final controller = _controller;
    if (controller == null) return;
    final playerId = packet['playerId'] as String?;
    if (playerId == null) return;
    final deviceIndex = _rosterIds.indexOf(playerId);
    if (deviceIndex < 0) return;
    final seq = (packet['seq'] as num?)?.toInt() ?? 0;
    controller.applyRemoteInput(MatrixInput(
      deviceIndex: deviceIndex,
      moveX: (packet['moveX'] as num?)?.toDouble() ?? 0,
      moveY: (packet['moveY'] as num?)?.toDouble() ?? 0,
      firing: packet['firing'] as bool? ?? false,
      sequence: seq,
    ));
  }

  @override
  void sendInput(MatrixInput input) {}

  @override
  void requestPause(bool paused) {
    // The host applies pause/resume requests directly on its controller.
  }

  @override
  void sendReady({required int deviceIndex, required bool ready}) {}

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
    _readySub?.cancel();
  }
}

/// Client-side adapter: receives the host's snapshot/phase stream and forwards
/// this device's local input to the host, exactly like a real device client.
class FutbolClientTransport implements MatrixSyncAdapter {
  FutbolClientTransport(
    this._client, {
    required this.playerId,
    required this.deviceIndex,
  }) {
    _stateSub = _client.gameStates.listen(_applyMessage);
  }

  final ClientService _client;
  final String playerId;
  final int deviceIndex;

  StreamSubscription<Map<String, dynamic>>? _stateSub;
  FutbolMatchController? _controller;
  int _seq = 0;
  bool _disposed = false;

  void attach(FutbolMatchController controller) {
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
      playerId: playerId,
      moveX: input.moveX,
      moveY: input.moveY,
      firing: input.firing,
      seq: ++_seq,
    );
  }

  @override
  void requestPause(bool paused) {
    _client.sendGameCommand(
      from: playerId,
      command: (paused ? PauseControlKey.pause : PauseControlKey.resume).key,
    );
  }

  @override
  void sendReady({required int deviceIndex, required bool ready}) {
    _client.sendGameReady(playerId: playerId, ready: ready);
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
