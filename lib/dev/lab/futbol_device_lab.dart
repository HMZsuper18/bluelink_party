import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../data/models/team.dart';
import '../../../network/client_service.dart';
import '../../../network/host_service.dart';
import '../../../network/protocol.dart';
import '../../features/matrix_arena/domain/matrix_grid.dart';
import '../../features/matrix_arena/domain/matrix_snapshots.dart';
import '../../features/matrix_arena/game/matrix_sync_adapter.dart';
import '../../features/matrix_arena/game/matrix_viewport.dart';
import '../../features/matrix_futbol/game/futbol_interpolation.dart';
import '../../features/matrix_futbol/game/futbol_match_controller.dart';
import '../../features/matrix_futbol/game/futbol_sync_adapter.dart';
import '../../features/matrix_futbol/presentation/futbol_arena_painter.dart';
import 'device_profile.dart';
import 'matrix_device_lab.dart' show LabPlatformBridge;

enum FutbolLabTransport { memory, udp }

class FutbolMemoryBus implements MatrixSyncAdapter {
  FutbolMemoryBus({required this.hostController});

  final FutbolMatchController? hostController;
  final List<FutbolMatchController> _clients = [];
  FutbolMatchController? _host;

  void addClient(FutbolMatchController controller) => _clients.add(controller);

  void attachHost(FutbolMatchController host) => _host = host;

  @override
  void sendInput(MatrixInput input) => _host?.applyRemoteInput(input);

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
  void dispose() {}
}

class VirtualFutbolDevice {
  VirtualFutbolDevice({
    required this.deviceIndex,
    required this.profile,
    required this.controller,
    required this.isHost,
  });

  final int deviceIndex;
  final VirtualDeviceProfile profile;
  final FutbolMatchController controller;
  final bool isHost;

  String get label =>
      isHost ? 'Host ${deviceIndex + 1}' : 'Dev ${deviceIndex + 1}';

  MatrixViewportCamera camera() => controller.camera(profile.size);
}

class FutbolDeviceLab {
  FutbolDeviceLab({
    required this.playerCount,
    this.transport = FutbolLabTransport.memory,
    this.devices = const [],
    this.seed = 1,
    this.scoreLimit = 5,
    this.humanDeviceIndex = -1,
  });

  final int playerCount;
  final FutbolLabTransport transport;
  final List<VirtualDeviceProfile> devices;
  final int seed;
  final int scoreLimit;

  /// When >= 0, the matching device is driven by a human (not by the bot AI)
  /// and must be stepped by whoever owns its screen (e.g. the real
  /// `FutbolArenaScreen` ticker). `-1` keeps the classic all-bots lab.
  final int humanDeviceIndex;

  late final TileMatrix matrix;
  final List<VirtualFutbolDevice> devicesLive = [];

  HostService? _host;
  final List<ClientService> _clients = [];
  FutbolMatchController? _hostController;
  final List<FutbolHostTransport> _hostTransports = [];
  final List<FutbolClientTransport> _clientTransports = [];
  bool _started = false;

  FutbolMatchController? get hostController => _hostController;
  bool get isRunning => _started && _hostController != null;
  bool get isOver => _hostController?.isMatchOver ?? false;
  int? get winnerTeam => _hostController?.winnerIndex;
  int get redScore => _hostController?.redScore ?? 0;
  int get blueScore => _hostController?.blueScore ?? 0;

  double get worldWidth => matrix.worldWidth;
  double get worldHeight => matrix.worldHeight;

  List<VirtualDeviceProfile> get _effectiveProfiles {
    final defaults = VirtualDeviceProfile.defaults;
    final list = devices.isEmpty ? defaults : devices;
    return List.generate(playerCount, (i) => list[i % list.length]);
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    matrix = MatrixLayoutManager().matrixForPlayerCount(playerCount);
    if (transport == FutbolLabTransport.udp) {
      await _startUdp();
    } else {
      _startMemory();
    }
  }

  FutbolRules _rules() => FutbolRules(
        calibrationSeconds: 1,
        countdownSeconds: 3,
        celebrationSeconds: 1.6,
        matchDurationSeconds: 999,
        scoreLimit: scoreLimit,
      );

  void _startMemory() {
    final bus = FutbolMemoryBus(hostController: null);
    final host = FutbolMatchController(
      matrix: matrix,
      deviceCount: playerCount,
      isHost: true,
      rules: _rules(),
      adapter: bus,
    );
    bus.attachHost(host);
    _hostController = host;
    host.start();
    devicesLive.add(VirtualFutbolDevice(
      deviceIndex: 0,
      profile: _effectiveProfiles[0],
      controller: host,
      isHost: true,
    ));
    for (var i = 1; i < playerCount; i++) {
      final client = FutbolMatchController(
        matrix: matrix,
        deviceCount: playerCount,
        isHost: false,
        deviceIndex: i,
        rules: _rules(),
        adapter: bus,
      );
      bus.addClient(client);
      devicesLive.add(VirtualFutbolDevice(
        deviceIndex: i,
        profile: _effectiveProfiles[i],
        controller: client,
        isHost: false,
      ));
    }
  }

  Future<void> _startUdp() async {
    final host = HostService(
      bridge: LabPlatformBridge(),
      playerId: 'lab-fut-host',
      playerName: 'Lab Futbol Host',
    );
    _host = host;
    await host.startHosting();
    host.claimSlot(Team.red);

    for (var i = 0; i < playerCount - 1; i++) {
      final client = ClientService(
          playerId: 'lab-fut-$i', playerName: 'Lab Futbol $i');
      _clients.add(client);
      final found = await client.discover();
      final lobby = found.length > 1
          ? found.firstWhere(
              (l) => l.hostPort != NetConstants.hostPort,
              orElse: () => found.first,
            )
          : found.first;
      await client.join(lobby).timeout(const Duration(seconds: 8));
      await client.claimSlot(i.isEven ? Team.blue : Team.red);
    }

    final room = await _clients.first.snapshots.first.then((s) => s.room);
    final rosterIds = <String>[
      for (final team in Team.all)
        for (final slot in room.slotsOf(team))
          if (slot.isFilled) slot.playerId ?? '',
    ];

    final hostTransport = FutbolHostTransport(
      host,
      rosterIds: rosterIds,
    );
    final hostController = FutbolMatchController(
      matrix: matrix,
      deviceCount: playerCount,
      isHost: true,
      rules: _rules(),
      adapter: hostTransport,
    );
    hostTransport.attach(hostController);
    _hostController = hostController;
    _hostTransports.add(hostTransport);
    devicesLive.add(VirtualFutbolDevice(
      deviceIndex: 0,
      profile: _effectiveProfiles[0],
      controller: hostController,
      isHost: true,
    ));

    for (var i = 0; i < _clients.length; i++) {
      final devIndex = i + 1;
      final transport = FutbolClientTransport(
        _clients[i],
        playerId: 'lab-f$i',
        deviceIndex: devIndex,
      );
      final controller = FutbolMatchController(
        matrix: matrix,
        deviceCount: playerCount,
        isHost: false,
        deviceIndex: devIndex,
        rules: _rules(),
        adapter: transport,
      );
      transport.attach(controller);
      _clientTransports.add(transport);
      devicesLive.add(VirtualFutbolDevice(
        deviceIndex: devIndex,
        profile: _effectiveProfiles[devIndex],
        controller: controller,
        isHost: false,
      ));
    }
  }

  void step(double dt) {
    final host = _hostController;
    if (host == null || !_started) return;
    final frame = host.renderFrame();
    for (final device in devicesLive) {
      _applyLocalInput(device, frame);
      device.controller.step(dt);
    }
  }

  void _applyLocalInput(
    VirtualFutbolDevice device,
    FutbolRenderFrame frame,
  ) {
    final controller = device.controller;
    final myIndex = device.deviceIndex;
    final myPlayer = frame.players[myIndex];
    final isHome = myIndex.isEven;

    var targetX = frame.ballX;
    var targetY = frame.ballY;
    if (frame.phase != FutbolMatchPhase.playing) {
      targetX = controller.matrix.worldWidth * (isHome ? 0.24 : 0.76);
      targetY = controller.matrix.worldHeight / 2;
    }

    final px = myPlayer.x;
    final py = myPlayer.y;
    final dx = targetX - px;
    final dy = targetY - py;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 1e-3) return;
    final moveX = dx / dist;
    final moveY = dy / dist;

    var firing = false;
    if (controller.phase == FutbolMatchPhase.playing) {
      final toBall = sqrt(
        (frame.ballX - px) * (frame.ballX - px) +
            (frame.ballY - py) * (frame.ballY - py),
      );
      if (toBall < 70) firing = true;
    }
    controller.setLocalInput(
      moveX: moveX,
      moveY: moveY,
      firing: firing,
    );
  }

  Future<Uint8List> renderPng(VirtualFutbolDevice device) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = device.profile.size;
    FutbolArenaPainter(
      controller: device.controller,
      screenSize: size,
      frame: device.controller.renderFrame(),
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  void dispose() {
    for (final transport in _hostTransports) {
      transport.dispose();
    }
    for (final transport in _clientTransports) {
      transport.dispose();
    }
    for (final client in _clients) {
      client.dispose();
    }
    _host?.dispose();
    _hostController?.dispose();
    for (final device in devicesLive) {
      if (!device.isHost) {
        device.controller.dispose();
      }
    }
    _started = false;
    devicesLive.clear();
    _hostTransports.clear();
    _clientTransports.clear();
    _clients.clear();
    _host = null;
    _hostController = null;
  }
}