import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core/theme/app_colors.dart';
import 'dev/lab/device_profile.dart';
import 'dev/lab/matrix_device_lab.dart';
import 'features/matrix_arena/domain/matrix_snapshots.dart';
import 'features/matrix_arena/game/matrix_arena_controller.dart';
import 'features/matrix_arena/game/matrix_interpolation.dart';
import 'features/matrix_arena/game/matrix_viewport.dart';
import 'features/matrix_arena/presentation/calibration_overlay.dart';
import 'features/matrix_arena/presentation/matrix_arena_painter.dart';

void main() => runApp(const DeviceLabApp());

class DeviceLabApp extends StatelessWidget {
  const DeviceLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueLink Party Device Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(primary: AppColors.p1),
      ),
      home: const DeviceLabScreen(),
    );
  }
}

class DeviceLabScreen extends StatefulWidget {
  const DeviceLabScreen({super.key});

  @override
  State<DeviceLabScreen> createState() => _DeviceLabScreenState();
}

class _DeviceLabScreenState extends State<DeviceLabScreen>
    with TickerProviderStateMixin {
  static const _allProfiles = [
    VirtualDeviceProfile.phonePortrait,
    VirtualDeviceProfile.phoneLandscape,
    VirtualDeviceProfile.tabletPortrait,
    VirtualDeviceProfile.tabletLandscape,
    VirtualDeviceProfile.desktopHd,
    VirtualDeviceProfile.ultraWide,
  ];

  int _playerCount = 4;
  final List<VirtualDeviceProfile> _selections = [];
  VirtualDeviceLab? _lab;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  int _seed = DateTime.now().millisecondsSinceEpoch % 100000;

  @override
  void initState() {
    super.initState();
    _selections.addAll(
      List.generate(4, (i) => _allProfiles[(i * 3) % _allProfiles.length]),
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _lab?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dtSeconds = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    final lab = _lab;
    if (lab == null) return;
    lab.step(dtSeconds);
    if (lab.isOver) {
      _ticker?.stop();
    }
    setState(() {});
  }

  void _start() {
    _ticker?.dispose();
    _lab?.dispose();
    final lab = VirtualDeviceLab(
      playerCount: _playerCount,
      devices: _selections.take(_playerCount).toList(),
      playSeconds: 999,
      seed: _seed,
      killsToWin: 5,
      countdownSeconds: 5,
    );
    lab.start();
    _lab = lab;
    _lastTick = Duration.zero;
    _ticker = createTicker(_onTick)..start();
    setState(() {});
  }

  void _stop() {
    _ticker?.stop();
    setState(() {});
  }

  void _resume() {
    _lastTick = Duration.zero;
    _ticker?.start();
    setState(() {});
  }

  void _restart() {
    _seed = (_seed + 1) % 100000;
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final lab = _lab;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screen Shift Device Lab'),
        actions: [
          if (lab != null && lab.isRunning && !lab.isOver)
            TextButton(onPressed: _stop, child: const Text('PAUSE')),
          if (lab != null && lab.isRunning && lab.isOver)
            TextButton(onPressed: _resume, child: const Text('RESUME')),
          if (lab != null)
            TextButton(onPressed: _restart, child: const Text('RESTART')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildConfigBar(lab),
          Expanded(child: _buildDeviceWall(lab)),
        ],
      ),
    );
  }

  Widget _buildConfigBar(VirtualDeviceLab? lab) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: Row(
        children: [
          Text('Devices',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(width: 8),
          for (final count in [2, 3, 4])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('$count'),
                selected: _playerCount == count,
                onSelected: (_) {
                  setState(() => _playerCount = count);
                },
              ),
            ),
          const SizedBox(width: 12),
          Text('Seed $_seed',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const Spacer(),
          if (lab == null)
            FilledButton(onPressed: _start, child: const Text('PLAY'))
          else if (lab.isOver)
            Text('WINNER: Device ${lab.winnerIndex! + 1}',
                style: const TextStyle(
                    color: AppColors.p1,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildDeviceWall(VirtualDeviceLab? lab) {
    if (lab == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pick device sizes, then press PLAY.',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _start, child: const Text('PLAY')),
          ],
        ),
      );
    }
    final devices = lab.devicesLive;
    final columns = devices.length <= 2 ? 2 : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.9,
      ),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        return _buildDeviceFrame(device, lab);
      },
    );
  }

  Widget _buildDeviceFrame(VirtualArenaDevice device, VirtualDeviceLab lab) {
    final profile = device.profile;
    final camera = device.camera();
    final controller = device.controller;
    final phase = controller.phase;
    final frame = controller.renderFrame();

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: device.isHost ? AppColors.p1 : AppColors.border,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                device.isHost ? Icons.cast_rounded : Icons.phone_android_rounded,
                size: 14,
                color: device.isHost ? AppColors.p1 : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                '${device.label}  ·  ${profile.label} ${profile.width}x${profile.height} '
                '·  T(${controller.localTile.column},${controller.localTile.row})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: device.isHost ? AppColors.p1 : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                _phaseLabel(phase, controller.countdownRemaining),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: profile.width.toDouble(),
                  height: profile.height.toDouble(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _ArenaPainterScale(
                          camera: camera,
                          frame: frame,
                          controller: controller,
                        ),
                      ),
                      if (phase != MatrixMatchPhase.playing &&
                          phase != MatrixMatchPhase.finished)
                        CalibrationOverlay(
                          viewport: camera,
                          tile: controller.localTile,
                          phaseLabel: phase == MatrixMatchPhase.countdown
                              ? 'GET READY'
                              : 'PLACE YOUR SCREEN',
                          countdown:
                              phase == MatrixMatchPhase.countdown
                                  ? controller.countdownRemaining
                                  : 0,
                          matrix: controller.matrix,
                          deviceIndex: controller.deviceIndex,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(MatrixMatchPhase phase, double remaining) {
    return switch (phase) {
      MatrixMatchPhase.calibrating => 'ALIGN ${remaining.toStringAsFixed(0)}',
      MatrixMatchPhase.countdown => 'READY ${remaining.toStringAsFixed(0)}',
      MatrixMatchPhase.playing => 'LIVE',
      MatrixMatchPhase.finished => 'OVER',
    };
  }
}

class _ArenaPainterScale extends CustomPainter {
  _ArenaPainterScale({
    required this.camera,
    required this.frame,
    required this.controller,
  });

  final MatrixViewportCamera camera;
  final MatrixInterpolationFrame frame;
  final MatrixArenaController controller;

  @override
  void paint(Canvas canvas, Size size) {
    MatrixArenaPainter(
      viewport: camera,
      frame: frame,
      matrix: controller.matrix,
      phase: controller.phase,
      countdown: controller.countdownRemaining,
      debugGuides: false,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_ArenaPainterScale oldDelegate) =>
      oldDelegate.controller.phase != controller.phase ||
      oldDelegate.frame != frame;
}
