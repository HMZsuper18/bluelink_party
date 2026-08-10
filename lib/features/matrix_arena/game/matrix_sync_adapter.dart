import '../domain/matrix_snapshots.dart';

abstract class MatrixSyncAdapter {
  void sendInput(MatrixInput input);

  void sendSnapshot(MatrixWorldSnapshot snapshot);

  void sendPhase(MatrixPhaseMessage phase);

  /// Any device -> host: request a global pause (true) or resume (false). The
  /// host applies the request; clients only forward it. No-op when there is no
  /// network path (a host controller applies the request directly).
  void requestPause(bool paused);

  void dispose();
}

class NoopMatrixSyncAdapter implements MatrixSyncAdapter {
  const NoopMatrixSyncAdapter();

  @override
  void sendInput(MatrixInput input) {}

  @override
  void sendPhase(MatrixPhaseMessage phase) {}

  @override
  void sendSnapshot(MatrixWorldSnapshot snapshot) {}

  @override
  void requestPause(bool paused) {}

  @override
  void dispose() {}
}