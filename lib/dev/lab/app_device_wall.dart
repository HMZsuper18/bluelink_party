import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/game_mode.dart';
import '../../data/models/game_phase.dart';
import '../../features/game/presentation/game_screen.dart';
import '../../features/matrix_arena/domain/matrix_snapshots.dart';
import '../../features/matrix_arena/game/matrix_viewport.dart';
import '../../features/matrix_arena/presentation/matrix_arena_painter.dart';
import '../../features/matrix_futbol/game/futbol_interpolation.dart';
import '../../features/matrix_futbol/presentation/futbol_arena_painter.dart';
import 'app_bot_lab.dart';

/// Mini rendered screens of every bot device, drawn with the exact same
/// painters the real app uses on real phones — so any painter edit in the
/// game shows up here immediately.
class AppDeviceWall extends StatelessWidget {
  const AppDeviceWall({super.key, required this.swarm});

  final AppBotSwarm swarm;

  @override
  Widget build(BuildContext context) {
    final devices = swarm.bots;
    if (devices.isEmpty) {
      return const Center(
        child: Text(
          'No bot devices configured.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.7,
      ),
      itemCount: devices.length,
      itemBuilder: (context, index) => _BotTile(bot: devices[index]),
    );
  }
}

class _BotTile extends StatelessWidget {
  const _BotTile({required this.bot});

  final AppBot bot;

  @override
  Widget build(BuildContext context) {
    final profile = bot.profile;
    final connected = bot.joined;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.phone_android_rounded : Icons.pause_circle,
                size: 13,
                color: connected ? AppColors.p4 : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                '${bot.name}  ·  ${profile.label}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                connected ? _statusLabel(bot) : 'SEARCHING...',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: profile.width.toDouble(),
                  height: profile.height.toDouble(),
                  child: _mirrorView(bot),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(AppBot bot) {
    final mode = bot.mode;
    final phase = switch (mode) {
      GameMode.screenShift =>
        bot.matrixController?.phase ?? MatrixMatchPhase.calibrating,
      GameMode.pixelFutbol =>
        bot.futbolController?.phase ?? FutbolMatchPhase.calibrating,
      GameMode.battleSync =>
        bot.battleBloc?.state.phase ?? GamePhase.countdown,
      null => null,
    };
    if (phase == null) return 'IN LOBBY';
    return phase.toString().split('.').last.toUpperCase();
  }

  Widget _mirrorView(AppBot bot) {
    final matrix = bot.matrixController;
    if (matrix != null) {
      return CustomPaint(
        painter: MatrixArenaPainter(
          viewport: MatrixViewportCamera(
            tile: matrix.localTile,
            screenSize: bot.profile.size,
          ),
          frame: matrix.renderFrame(),
          matrix: matrix.matrix,
          phase: matrix.phase,
          countdown: matrix.countdownRemaining,
          debugGuides: false,
        ),
      );
    }
    final futbol = bot.futbolController;
    if (futbol != null) {
      return CustomPaint(
        painter: FutbolArenaPainter(
          controller: futbol,
          screenSize: bot.profile.size,
          frame: futbol.renderFrame(),
        ),
      );
    }
    final battle = bot.battleBloc;
    if (battle != null) {
      final state = battle.state;
      return Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: FieldPainter()),
          if (state.phase == GamePhase.inGame ||
              state.phase == GamePhase.matchResult)
            MatchCanvas(
              players: state.players,
              projectiles: state.projectiles,
              elapsedMs: state.elapsedMs,
            ),
        ],
      );
    }
    return const ColoredBox(color: Colors.black);
  }
}