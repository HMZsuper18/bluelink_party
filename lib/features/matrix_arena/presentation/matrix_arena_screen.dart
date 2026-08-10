import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../battle_sync/presentation/widgets/action_button.dart';
import '../../battle_sync/presentation/widgets/virtual_joystick.dart';
import '../../../core/audio/sfx_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../game/presentation/pause_menu.dart';
import '../domain/matrix_snapshots.dart';
import '../game/matrix_arena_controller.dart';
import '../game/matrix_viewport.dart';
import 'calibration_overlay.dart';
import 'matrix_arena_painter.dart';

/// Lightweight visual-only effects produced by the presentation layer on top
/// of the replicated world frame (works identically on host and clients).
enum MatrixFxKind { muzzle, hit, death, shockwave }

class MatrixFx {
  MatrixFx.muzzle({
    required this.x,
    required this.y,
    required this.life,
    this.vx = 0,
    this.vy = 0,
    this.color = Colors.white,
  }) : kind = MatrixFxKind.muzzle;

  MatrixFx.hit({
    required this.x,
    required this.y,
    this.color = const Color(0xFFFCE38A),
  })  : vx = 0,
        vy = 0,
        kind = MatrixFxKind.hit,
        life = 0.35;

  MatrixFx.death({
    required this.x,
    required this.y,
    this.color = Colors.white,
  })  : vx = 0,
        vy = 0,
        kind = MatrixFxKind.death,
        life = 0.8;

  MatrixFx.shockwave({
    required this.x,
    required this.y,
    this.color = Colors.white,
    this.life = 0.5,
  })  : vx = 0,
        vy = 0,
        kind = MatrixFxKind.shockwave;

  final MatrixFxKind kind;
  final double x;
  final double y;
  final double vx;
  final double vy;
  final Color color;
  final double life;
  double elapsed = 0;
}

class MatrixArenaScreen extends StatefulWidget {
  const MatrixArenaScreen({
    super.key,
    required this.controller,
    this.onExit,
    this.debugGuides = false,
    this.cameraOverride,
  });

  final MatrixArenaController controller;
  final VoidCallback? onExit;
  final bool debugGuides;

  /// When set (e.g. a solo dev view showing the whole arena instead of only
  /// this device's tile), the screen renders with this camera.
  final MatrixViewportCamera? cameraOverride;

  @override
  State<MatrixArenaScreen> createState() => _MatrixArenaScreenState();
}

class _MatrixArenaScreenState extends State<MatrixArenaScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  MatrixArenaController get controller => widget.controller;

  Offset _moveInput = Offset.zero;
  bool _firing = false;

  final List<MatrixFx> _fx = [];
  final Map<int, double> _previousHp = {};
  final Set<int> _seenProjectileIds = {};
  double _shake = 0;
  double _hitFlash = 0;
  bool _winSoundPlayed = false;

  @override
  void initState() {
    super.initState();
    for (final player in controller.players) {
      _previousHp[player.deviceIndex] = player.hp.toDouble();
    }
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dtSeconds = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    controller.step(dtSeconds);
    final dt = dtSeconds.clamp(0.0, 0.1);
    _detectFrameEvents(dt);
    if (_shake > 0) _shake = (_shake - dt * 3).clamp(0.0, 1.0);
    if (_hitFlash > 0) _hitFlash = (_hitFlash - dt * 2.5).clamp(0.0, 1.0);
    setState(() {});
  }

  void _detectFrameEvents(double dt) {
    final frame = controller.renderFrame();

    for (final projectile in frame.projectiles) {
      if (_seenProjectileIds.add(projectile.id)) {
        final shooter = frame.players
            .where((p) => p.deviceIndex == projectile.ownerIndex)
            .firstOrNull;
        if (shooter != null) {
          _fx.add(MatrixFx.muzzle(
            x: shooter.x,
            y: shooter.y,
            vx: projectile.vx,
            vy: projectile.vy,
            life: 0.14,
            color: SlotVisuals.colorOf(shooter.deviceIndex),
          ));
        }
        SfxService.instance.shoot();
      }
    }
    _seenProjectileIds
        .removeWhere((id) => !frame.projectiles.any((p) => p.id == id));
    if (_seenProjectileIds.length > 64) _seenProjectileIds.clear();

    for (final player in frame.players) {
      final previous = _previousHp[player.deviceIndex];
      if (previous == null) continue;
      if (player.hp < previous && player.hp > 0) {
        final color = SlotVisuals.colorOf(player.deviceIndex);
        _fx.add(MatrixFx.hit(
          x: player.x,
          y: player.y,
          color: color,
        ));
        _fx.add(MatrixFx.shockwave(
          x: player.x,
          y: player.y,
          color: color,
        ));
        SfxService.instance.hit();
        if (player.deviceIndex == controller.deviceIndex) {
          _hitFlash = 1;
        }
      }
      if (previous > 0 && player.hp <= 0) {
        _fx.add(MatrixFx.death(
          x: player.x,
          y: player.y,
        ));
        _fx.add(MatrixFx.shockwave(
          x: player.x,
          y: player.y,
          life: 0.9,
        ));
        SfxService.instance.death();
        if (player.deviceIndex == controller.deviceIndex) {
          _shake = 1;
        }
      }
      _previousHp[player.deviceIndex] = player.hp.toDouble();
    }

    if (controller.isMatchOver && !_winSoundPlayed) {
      _winSoundPlayed = true;
      SfxService.instance.win();
    }

    for (final fx in _fx) {
      fx.elapsed += dt;
    }
    _fx.removeWhere((fx) => fx.elapsed >= fx.life);
  }

  /// Pausing is meaningful once the countdown starts and until match over.
  bool get _pauseAvailable =>
      !controller.isPaused &&
      (controller.phase == MatrixMatchPhase.countdown ||
          controller.phase == MatrixMatchPhase.playing);

  void _exit() {
    if (widget.onExit != null) {
      widget.onExit!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  ({String label, Color color})? get _positionHint {
    if (controller.phase != MatrixMatchPhase.calibrating &&
        controller.phase != MatrixMatchPhase.countdown) {
      return null;
    }
    final tile = controller.localTile;
    final playerNumber = controller.deviceIndex + 1;
    final color = SlotVisuals.colorOf(controller.deviceIndex);

    final worldW = controller.matrix.worldWidth;
    final worldH = controller.matrix.worldHeight;
    final centerX = tile.centerX;
    final centerY = tile.centerY;

    final horizontal = centerX < worldW / 3
        ? 'LEFT'
        : (centerX > worldW * 2 / 3 ? 'RIGHT' : 'CENTER');
    final vertical = centerY < worldH / 2 ? 'TOP' : 'BOTTOM';

    final side = switch ((tile.columns, tile.rows)) {
      (_, 1) => horizontal,
      _ => '$vertical $horizontal'.trim(),
    };
    return (label: 'PLAYER $playerNumber  ·  $side', color: color);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final viewport = widget.cameraOverride ??
            MatrixViewportCamera(
              tile: controller.localTile,
              screenSize: size,
            );
            final zones = MatrixControlZones.compute(
              screenSize: size,
              playRect: viewport.playRect,
              padding: EdgeInsets.zero,
            );

            final frame = controller.renderFrame();

            final inPreGame = controller.phase != MatrixMatchPhase.playing &&
                controller.phase != MatrixMatchPhase.finished;

            final hint = _positionHint;

            return Stack(
              children: [
                Positioned.fill(
                  child: Transform.translate(
                    offset: _shakeOffset(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: MatrixArenaPainter(
                            viewport: viewport,
                            frame: frame,
                            matrix: controller.matrix,
                            phase: controller.phase,
                            countdown: controller.countdownRemaining,
                            debugGuides: widget.debugGuides,
                            effects: _fx,
                          ),
                        ),
                        if (_hitFlash > 0)
                          IgnorePointer(
                            child: Container(
                              color: Colors.red.withValues(
                                alpha: 0.25 * _hitFlash,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (inPreGame)
                  Positioned.fill(
                    child: CalibrationOverlay(
                      viewport: viewport,
                      tile: controller.localTile,
                      phaseLabel: controller.phase == MatrixMatchPhase.countdown
                          ? 'GET READY'
                          : 'PLACE YOUR SCREEN',
                      countdown: controller.phase == MatrixMatchPhase.countdown
                          ? controller.countdownRemaining
                          : controller.countdownRemaining.clamp(0, 6),
                      positionLabel: hint?.label,
                      positionColor: hint?.color,
                      matrix: controller.matrix,
                      deviceIndex: controller.deviceIndex,
                    ),
                  ),
                if (controller.isMatchOver)
                  Positioned.fill(child: _buildResultOverlay(context)),
                IgnorePointer(
                  ignoring: controller.isPaused,
                  child: _buildJoystick(zones),
                ),
                IgnorePointer(
                  ignoring: controller.isPaused,
                  child: _buildFireButton(zones),
                ),
                _buildHealthBars(zones),
                if (zones.tileIndicatorRect != null)
                  Positioned.fromRect(
                    rect: zones.tileIndicatorRect!,
                    child: _buildTileIndicator(),
                  ),
                Positioned(
                  top: 8,
                  right: 12,
                  child: _buildPhaseChip(context),
                ),
                if (_pauseAvailable)
                  Positioned(
                    top: 8,
                    left: 12,
                    child: PauseMenuButton(
                      onPressed: () => controller.requestPause(true),
                    ),
                  ),
                if (controller.isPaused)
                  Positioned.fill(
                    child: PauseMenuOverlay(
                      onResume: () => controller.requestPause(false),
                      onQuit: _exit,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildJoystick(MatrixControlZones zones) {
    final rect = zones.joystickRect;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Center(
        child: VirtualJoystick(
          size: rect.width,
          onChanged: (offset) {
            _moveInput = offset;
            _sendInput();
          },
        ),
      ),
    );
  }

  Widget _buildFireButton(MatrixControlZones zones) {
    final rect = zones.fireRect;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Center(
        child: ActionButton(
          size: rect.width,
          label: 'FIRE',
          color: AppColors.danger,
          onPressedChanged: (pressed) {
            _firing = pressed;
            _sendInput();
          },
        ),
      ),
    );
  }

  void _sendInput() {
    controller.setLocalInput(
      moveX: _moveInput.dx,
      moveY: _moveInput.dy,
      firing: _firing,
    );
  }

  Offset _shakeOffset() {
    if (_shake <= 0) return Offset.zero;
    final t = _lastTick.inMilliseconds;
    final amplitude = 8 * _shake;
    return Offset(
      sin(t / 43) * amplitude,
      cos(t / 57) * amplitude,
    );
  }

  Widget _buildHealthBars(MatrixControlZones zones) {
    final rect = zones.healthBarsRect;
    if (rect == null) return const SizedBox.shrink();
    return Positioned(
      left: rect.left,
      top: rect.top,
      right: rect.right,
      height: rect.height,
      child: Row(
        children: [
          for (final player in controller.players)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _PlayerHealthBar(
                  color: SlotVisuals.colorOf(player.deviceIndex),
                  name: player.name,
                  hp: player.hp,
                  maxHp: player.maxHp,
                  alive: player.alive,
                  kills: player.kills,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTileIndicator() {
    final tile = controller.localTile;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Text(
            'TILE ${tile.column + 1},${tile.row + 1}  OF  ${tile.columns}x${tile.rows}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseChip(BuildContext context) {
    final label = switch (controller.phase) {
      MatrixMatchPhase.calibrating => 'CALIBRATING',
      MatrixMatchPhase.countdown => 'COUNTDOWN',
      MatrixMatchPhase.playing => 'IN PLAY',
      MatrixMatchPhase.finished => 'MATCH OVER',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildResultOverlay(BuildContext context) {
    final winner = controller.winnerIndex;
    final winnerPlayer =
        winner == null ? null : controller.playerAt(winner);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: winnerPlayer == null
                    ? Colors.white
                    : SlotVisuals.colorOf(winnerPlayer.deviceIndex),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              winnerPlayer == null ? 'DRAW' : '${winnerPlayer.name} WINS',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'KILLS TO WIN: ${controller.config.killsToWin}',
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 28),
            FilledButton.tonal(
              onPressed: _exit,
              child: const Text('BACK TO LOBBY'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerHealthBar extends StatelessWidget {
  const _PlayerHealthBar({
    required this.color,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.alive,
    required this.kills,
  });

  final Color color;
  final String name;
  final int hp;
  final int maxHp;
  final bool alive;
  final int kills;

  @override
  Widget build(BuildContext context) {
    final ratio = (hp / maxHp).clamp(0.0, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: alive ? color : Colors.white24,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              name.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$kills K',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}