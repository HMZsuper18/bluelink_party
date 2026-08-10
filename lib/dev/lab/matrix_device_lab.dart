import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../data/models/team.dart';
import '../../../data/repositories/wifi_info_repository.dart';
import '../../../network/client_service.dart';
import '../../../network/host_service.dart';
import '../../../network/protocol.dart';
import '../../features/matrix_arena/demo/matrix_memory_bus.dart';
import '../../features/matrix_arena/domain/matrix_grid.dart';
import '../../features/matrix_arena/domain/matrix_world.dart';
import '../../features/matrix_arena/game/matrix_arena_controller.dart';
import '../../features/matrix_arena/game/matrix_interpolation.dart';
import '../../features/matrix_arena/game/matrix_sync_adapter.dart';
import '../../features/matrix_arena/game/matrix_transport_sync.dart';
import '../../features/matrix_arena/game/matrix_viewport.dart';
import '../../features/matrix_arena/presentation/matrix_arena_painter.dart';
import 'device_profile.dart';

enum LabTransport { memory, udp }

class LabPlatformBridge extends PlatformBridge {
  @override
  Future<bool> acquireMulticastLock() async => true;

  @override
  Future<void> releaseMulticastLock() async {}
}

class VirtualArenaDevice {
  VirtualArenaDevice({
    required this.deviceIndex,
    required this.profile,
    required this.controller,
    required this.isHost,
  });

  final int deviceIndex;
  final VirtualDeviceProfile profile;
  final MatrixArenaController controller;
  final bool isHost;

  String get label => isHost ? 'Host ${deviceIndex + 1}' : 'Dev ${deviceIndex + 1}';

  MatrixViewportCamera camera() => MatrixViewportCamera(
        tile: controller.localTile,
        screenSize: profile.size,
      );

  Future<Uint8List> renderPng() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = profile.size;
    MatrixArenaPainter(
      viewport: camera(),
      frame: controller.renderFrame(),
      matrix: controller.matrix,
      phase: controller.phase,
      countdown: controller.countdownRemaining,
      debugGuides: false,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }
}

class VirtualDeviceLab {
  VirtualDeviceLab({
    required this.playerCount,
    this.transport = LabTransport.memory,
    this.devices = const [],
    this.playSeconds = 12,
    this.calibrationSeconds = 0.6,
    this.countdownSeconds = 0.8,
    this.seed = 1,
    this.killsToWin = 1,
  });

  final int playerCount;
  final LabTransport transport;
  final List<VirtualDeviceProfile> devices;
  final double playSeconds;
  final double calibrationSeconds;
  final double countdownSeconds;
  final int seed;
  final int killsToWin;

  late final TileMatrix matrix;
  final List<VirtualArenaDevice> devicesLive = [];

  HostService? _host;
  final List<ClientService> _clients = [];
  MatrixArenaController? _hostController;
  final List<MatrixSyncAdapter> _adapters = [];

  bool _started = false;

  MatrixArenaController? get hostController => _hostController;
  bool get isRunning => _started && _hostController != null;
  bool get isOver => _hostController?.isMatchOver ?? false;
  int? get winnerIndex => _hostController?.winnerIndex;
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
    matrix = MatrixLayoutManager()
        .matrixForPlayerCount(playerCount);
    final config = MatrixWorldConfig(
      killsToWin: killsToWin,
      projectileSpeed: 1400,
      projectileLife: 3,
      projectileDamage: 100,
      respawnDelay: 0.2,
    );
    if (transport == LabTransport.udp) {
      await _startUdp(config);
    } else {
      _startMemory(config);
    }
  }

  void _startMemory(MatrixWorldConfig config) {
    final bus = MatrixMemoryBus(hostController: null, clients: []);
    final host = MatrixArenaController(
      matrix: matrix,
      deviceCount: playerCount,
      isHost: true,
      config: config,
      adapter: bus,
      calibrationDuration: calibrationSeconds,
      countdownDuration: countdownSeconds,
      random: Random(seed),
    );
    bus.attachHost(host);
    _hostController = host;
    devicesLive.add(VirtualArenaDevice(
      deviceIndex: 0,
      profile: _effectiveProfiles[0],
      controller: host,
      isHost: true,
    ));
    for (var i = 1; i < playerCount; i++) {
      final client = MatrixArenaController(
        matrix: matrix,
        deviceCount: playerCount,
        isHost: false,
        deviceIndex: i,
        config: config,
        adapter: bus,
        calibrationDuration: calibrationSeconds,
        countdownDuration: countdownSeconds,
        random: Random(seed + i),
      );
      bus.addClient(client);
      devicesLive.add(VirtualArenaDevice(
        deviceIndex: i,
        profile: _effectiveProfiles[i],
        controller: client,
        isHost: false,
      ));
    }
  }

  Future<void> _startUdp(MatrixWorldConfig config) async {
    final host = HostService(
      bridge: LabPlatformBridge(),
      playerId: 'lab-host',
      playerName: 'Lab Host',
    );
    _host = host;
    await host.startHosting();
    host.claimSlot(Team.red);

    for (var i = 0; i < playerCount - 1; i++) {
      final client = ClientService(playerId: 'lab-c$i', playerName: 'Lab $i');
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

    final hostTransport = MatrixHostTransport(
      host,
      localPlayerId: 'lab-host',
      rosterIds: rosterIds,
    );
    final hostController = MatrixArenaController(
      matrix: matrix,
      deviceCount: playerCount,
      isHost: true,
      config: config,
      adapter: hostTransport,
      calibrationDuration: calibrationSeconds,
      countdownDuration: countdownSeconds,
      random: Random(seed),
    );
    hostTransport.attach(hostController);
    _hostController = hostController;
    devicesLive.add(VirtualArenaDevice(
      deviceIndex: 0,
      profile: _effectiveProfiles[0],
      controller: hostController,
      isHost: true,
    ));

    for (var i = 0; i < _clients.length; i++) {
      final devIndex = i + 1;
      final transport = MatrixClientTransport(
        _clients[i],
        localPlayerId: 'lab-c$i',
        deviceIndex: devIndex,
      );
      final controller = MatrixArenaController(
        matrix: matrix,
        deviceCount: playerCount,
        isHost: false,
        deviceIndex: devIndex,
        config: config,
        adapter: transport,
        calibrationDuration: calibrationSeconds,
        countdownDuration: countdownSeconds,
        random: Random(seed + devIndex),
      );
      transport.attach(controller);
      _adapters.add(transport);
      devicesLive.add(VirtualArenaDevice(
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
      _applyLocalInput(device, frame, dt);
      device.controller.step(dt);
    }
  }

  void _applyLocalInput(
    VirtualArenaDevice device,
    MatrixInterpolationFrame frame,
    double dt,
  ) {
    final controller = device.controller;
    final players = frame.players;
    if (players.length < 2) return;
    final enemy = players[(device.deviceIndex + 1) % players.length];
    final me = players[device.deviceIndex];
    final dx = enemy.x - me.x;
    final dy = enemy.y - me.y;
    final dist = sqrt(dx * dx + dy * dy);
    final aimX = dist == 0 ? 0 : dx / dist;
    final aimY = dist == 0 ? 0 : dy / dist;
    final orbit = Random(seed * 100 + device.deviceIndex).nextDouble();
    final moveX = aimX * 0.85 + sin(orbit + device.deviceIndex) * 0.3;
    final moveY = aimY * 0.85 + cos(orbit + device.deviceIndex) * 0.3;
    controller.setLocalInput(moveX: moveX, moveY: moveY, firing: true);
  }

  /// True when the device's painted screen shows entities that live in other
  /// tiles (cross-tile rendering) or everything matches its own tile.
  ({int onScreen, int inTile}) visibleCounts(VirtualArenaDevice device) {
    final frame = device.controller.renderFrame();
    MatrixViewportCamera camera;
    try {
      camera = device.camera();
    } catch (_) {
      return (onScreen: 0, inTile: 0);
    }
    var onScreen = 0;
    var inTile = 0;
    for (final p in frame.players) {
      onScreen += camera.isVisibleOnScreen(camera.worldToScreen(p.x, p.y), 16)
          ? 1
          : 0;
      inTile += _inTile(device, p.x, p.y) ? 1 : 0;
    }
    for (final p in frame.projectiles) {
      onScreen += camera.isVisibleOnScreen(camera.worldToScreen(p.x, p.y), 16)
          ? 1
          : 0;
      inTile += _inTile(device, p.x, p.y) ? 1 : 0;
    }
    return (onScreen: onScreen, inTile: inTile);
  }

  bool _inTile(VirtualArenaDevice device, double x, double y) {
    final tile = device.controller.localTile;
    return x >= tile.left &&
        x <= tile.right &&
        y >= tile.top &&
        y <= tile.bottom;
  }

  void dispose() {
    for (final adapter in _adapters) {
      adapter.dispose();
    }
    for (final client in _clients) {
      client.dispose();
    }
    _host?.dispose();
    _hostController?.dispose();
    _hostController = null;
    _started = false;
    devicesLive.clear();
  }
}