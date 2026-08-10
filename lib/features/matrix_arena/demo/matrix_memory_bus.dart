import '../domain/matrix_snapshots.dart';
import '../game/matrix_arena_controller.dart';
import '../game/matrix_sync_adapter.dart';

class MatrixMemoryBus implements MatrixSyncAdapter {
  MatrixMemoryBus({
    required this.hostController,
    required List<MatrixArenaController> clients,
  }) : _clients = List.of(clients);

  final MatrixArenaController? hostController;
  final List<MatrixArenaController> _clients;

  void addClient(MatrixArenaController client) {
    _clients.add(client);
  }

  void attachHost(MatrixArenaController host) {
    _host = host;
  }

  MatrixArenaController? _host;

  @override
  void sendInput(MatrixInput input) {
    _host?.applyRemoteInput(input);
  }

  @override
  void sendPhase(MatrixPhaseMessage phase) {
    for (final client in _clients) {
      client.applyRemotePhase(phase);
    }
  }

  @override
  void sendSnapshot(MatrixWorldSnapshot snapshot) {
    for (final client in _clients) {
      client.applyRemoteSnapshot(snapshot);
    }
  }

  @override
  void requestPause(bool paused) {
    if (paused) {
      _host?.pause();
    } else {
      _host?.resume();
    }
  }

  @override
  void sendReady({required int deviceIndex, required bool ready}) {}

  @override
  void dispose() {
    for (final client in _clients) {
      client.dispose();
    }
    _host?.dispose();
  }
}