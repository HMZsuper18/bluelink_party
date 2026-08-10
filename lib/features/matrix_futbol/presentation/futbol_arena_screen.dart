import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/audio/sfx_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../battle_sync/presentation/widgets/action_button.dart';
import '../../battle_sync/presentation/widgets/virtual_joystick.dart';
import '../../game/presentation/pause_menu.dart';
import '../../matrix_arena/game/matrix_viewport.dart';
import '../../matrix_arena/presentation/calibration_overlay.dart';
import '../game/futbol_interpolation.dart';
import '../game/futbol_match_controller.dart';
import 'futbol_arena_painter.dart';

class FutbolArenaScreen extends StatefulWidget {
  const FutbolArenaScreen({
    super.key,
    required this.controller,
    this.onExit,
    this.debugGuides = false,
    this.viewportOverride,
  });

  final FutbolMatchController controller;
  final VoidCallback? onExit;
  final bool debugGuides;

  /// When set (e.g. a solo dev view that shows the whole pitch instead of
  /// only this device's tile), the screen renders with this camera.
  final MatrixViewportCamera? viewportOverride;

  @override
  State<FutbolArenaScreen> createState() => _FutbolArenaScreenState();
}

class _FutbolArenaScreenState extends State<FutbolArenaScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Offset _moveInput = Offset.zero;
  bool _kicking = false;

  FutbolMatchController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
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
    setState(() {});
  }

  final List<FutbolFx> _fx = [];

  double _previousBallSpeed = 0;
  double _previousVx = 0;
  double _previousVy = 0;
  bool _previousCelebration = false;
  bool _winSoundPlayed = false;

  void _detectFrameEvents(double dt) {
    final ballSpeed = sqrt(
      controller.ballVx * controller.ballVx +
          controller.ballVy * controller.ballVy,
    );
    final speedFactor =
        controller.phase == FutbolMatchPhase.playing ? ballSpeed : 0.0;
    if (speedFactor > 260 && _previousBallSpeed < 120) {
      _fx.add(FutbolFx.kick(x: controller.ballX, y: controller.ballY));
      SfxService.instance.kick();
    }
    _previousBallSpeed = speedFactor;

    if (_previousVx != 0 || _previousVy != 0) {
      final curSpeed = ballSpeed;
      final prevSpeed =
          sqrt(_previousVx * _previousVx + _previousVy * _previousVy);
      final dot = controller.ballVx * _previousVx +
          controller.ballVy * _previousVy;
      final cosAngle = dot / (curSpeed * prevSpeed);
      if (_ballNearWall() && prevSpeed > 120 && cosAngle < -0.3) {
        _fx.add(FutbolFx.bounce(x: controller.ballX, y: controller.ballY));
        SfxService.instance.bounce();
      }
    }
    _previousVx = controller.ballVx;
    _previousVy = controller.ballVy;

    final celebrating = controller.isCelebrating;
    if (celebrating && !_previousCelebration) {
      final team = controller.scoredBy ?? 0;
      final inside = team == 0
          ? -controller.pitch.goalInset
          : controller.pitch.worldWidth + controller.pitch.goalInset;
      _fx.add(FutbolFx.goal(
        x: inside,
        y: (controller.pitch.leftGoalTop + controller.pitch.leftGoalBottom) / 2,
        color: team == 0 ? AppColors.p1 : AppColors.p4,
      ));
      SfxService.instance.goal();
      SfxService.instance.whistle();
    }
    _previousCelebration = celebrating;

    if (controller.isMatchOver && !_winSoundPlayed) {
      _winSoundPlayed = true;
      SfxService.instance.win();
    }

    for (final fx in _fx) {
      fx.elapsed += dt;
    }
    _fx.removeWhere((fx) => fx.elapsed >= fx.life);
  }

  bool _ballNearWall() {
    final margin = 40.0;
    final x = controller.ballX;
    final y = controller.ballY;
    return x < margin ||
        x > controller.pitch.worldWidth - margin ||
        y < margin ||
        y > controller.pitch.worldHeight - margin;
  }

  /// Pausing is meaningful once the countdown starts and until full time.
  bool get _pauseAvailable =>
      !controller.isPaused &&
      (controller.phase == FutbolMatchPhase.countdown ||
          controller.phase == FutbolMatchPhase.playing);

  void _exit() {
    if (widget.onExit != null) {
      widget.onExit!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final viewport = widget.viewportOverride ?? controller.camera(size);
            final zones = MatrixControlZones.compute(
              screenSize: size,
              playRect: viewport.playRect,
              padding: EdgeInsets.zero,
            );
            final frame = controller.renderFrame();

            final preGame = controller.phase == FutbolMatchPhase.calibrating ||
                controller.phase == FutbolMatchPhase.countdown;

            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: FutbolArenaPainter(
                      controller: controller,
                      screenSize: size,
                      frame: frame,
                      effects: _fx,
                      viewport: viewport,
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: controller.isPaused,
                  child: _buildControls(zones),
                ),
                if (controller.isCelebrating)
                  _buildGoalBanner(frame),
                if (controller.isMatchOver)
                  _buildResultOverlay(frame),
                if (preGame)
                  Positioned.fill(
                    child: CalibrationOverlay(
                      viewport: viewport,
                      tile: controller.localTile,
                      phaseLabel: controller.phase == FutbolMatchPhase.countdown
                          ? 'GET READY'
                          : 'ALIGN YOUR SCREEN',
                      countdown: controller.phase == FutbolMatchPhase.countdown
                          ? controller.phaseTimer
                          : controller.phaseTimer.clamp(0, 6),
                      matrix: controller.matrix,
                      deviceIndex: controller.deviceIndex,
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 12,
                  child: _phaseChip(controller.phase),
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

  Widget _buildControls(MatrixControlZones zones) {
    return Stack(
      children: [
        Positioned(
          left: zones.joystickRect.left,
          top: zones.joystickRect.top,
          width: zones.joystickRect.width,
          height: zones.joystickRect.height,
          child: Center(
            child: VirtualJoystick(
              size: zones.joystickRect.width,
              onChanged: (offset) {
                _moveInput = offset;
                _sendInput();
              },
            ),
          ),
        ),
        Positioned(
          left: zones.fireRect.left,
          top: zones.fireRect.top,
          width: zones.fireRect.width,
          height: zones.fireRect.height,
          child: Center(
            child: ActionButton(
              size: zones.fireRect.width,
              label: 'KICK',
              color: AppColors.success,
              onPressedChanged: (pressed) {
                _kicking = pressed;
                _sendInput();
              },
            ),
          ),
        ),
      ],
    );
  }

  void _sendInput() {
    controller.setLocalInput(
      moveX: _moveInput.dx,
      moveY: _moveInput.dy,
      firing: _kicking,
    );
  }

  Widget _buildGoalBanner(FutbolRenderFrame frame) {
    final text = frame.scoredBy == 0 ? 'RED SCORES!' : 'BLUE SCORES!';
    final color = frame.scoredBy == 0 ? AppColors.p1 : AppColors.p4;
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.8), width: 2),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultOverlay(FutbolRenderFrame frame) {
    final winner = controller.winnerIndex;
    final draw = winner == null;
    final text = draw
        ? 'DRAW'
        : (winner == 0 ? 'RED WINS' : 'BLUE WINS');
    final color = draw
        ? Colors.white
        : (winner == 0 ? AppColors.p1 : AppColors.p4);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'RED ${frame.redScore} : ${frame.blueScore} BLUE',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: _exit,
              child: const Text('BACK TO LOBBY'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phaseChip(FutbolMatchPhase phase) {
    final label = switch (phase) {
      FutbolMatchPhase.calibrating => 'CALIBRATING',
      FutbolMatchPhase.countdown => 'COUNTDOWN',
      FutbolMatchPhase.playing => 'IN PLAY',
      FutbolMatchPhase.finished => 'FULL TIME',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.75),
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
}