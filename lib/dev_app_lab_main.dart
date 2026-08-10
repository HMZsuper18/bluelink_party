import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'dev/lab/app_bot_lab.dart';
import 'dev/lab/app_device_wall.dart';
import 'features/player_setup/presentation/player_setup_screen.dart';

void main() => runApp(const AppBotLabApp());

/// The whole real app (player setup -> lobby -> any match mode) with a swarm
/// of real-client bots on loopback and a floating wall that shows every bot's
/// screen, painted by the same painters the game uses on devices. Because the
/// running UI is the real app itself, every edit to it applies here directly.
class AppBotLabApp extends StatelessWidget {
  const AppBotLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScreenShift · Bots Lab',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _AppBotLabHome(),
    );
  }
}

class _AppBotLabHome extends StatefulWidget {
  const _AppBotLabHome();

  @override
  State<_AppBotLabHome> createState() => _AppBotLabHomeState();
}

class _AppBotLabHomeState extends State<_AppBotLabHome>
    with SingleTickerProviderStateMixin {
  late final AppBotSwarm _swarm;
  final int _botCount = 3;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _swarm = AppBotSwarm(botCount: _botCount)..start();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _swarm.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dtSeconds = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    _swarm.tick(dtSeconds.clamp(0.0, 0.1));
  }

  void _openWall() {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: AppColors.background,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            title: const Text(
              'Other devices',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: AppDeviceWall(swarm: _swarm),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Navigator(
          onGenerateInitialRoutes: (navigator, initialRoute) => [
            MaterialPageRoute<void>(builder: (_) => const PlayerSetupScreen()),
          ],
        ),
        Positioned(
          left: 14,
          bottom: 14,
          child: Material(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            elevation: 6,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openWall,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.devices_rounded,
                        size: 18, color: AppColors.p2),
                    const SizedBox(width: 8),
                    Text(
                      'DEVICES  ·  ${_swarm.joinedCount}/$_botCount',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}