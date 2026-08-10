import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'dart:math';

import '../../../core/audio/sfx_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/lobby_room.dart';
import '../../../data/models/team.dart';
import '../game/battle_sync_controller.dart';
import '../game/virtual_resolution.dart';
import 'arena_painter.dart';
import 'widgets/action_button.dart';
import 'widgets/virtual_joystick.dart';

class BattleSyncGameScreen extends StatefulWidget {
  const BattleSyncGameScreen({
    super.key,
    required this.room,
    required this.myPlayerId,
    this.controller,
    this.adapter,
    this.isHost = false,
    this.virtualResolution = const VirtualResolution(),
  });

  final LobbyRoom room;
  final String myPlayerId;
  final BattleSyncController? controller;
  final BattleSyncAdapter? adapter;
  final bool isHost;
  final VirtualResolution virtualResolution;

  @override
  State<BattleSyncGameScreen> createState() => _BattleSyncGameScreenState();
}

class _BattleSyncGameScreenState extends State<BattleSyncGameScreen>
    with SingleTickerProviderStateMixin {
  late final BattleSyncController _controller;
  Ticker? _ticker;
  Duration? _lastTick;

  Offset _move = Offset.zero;
  bool _firing = false;

  double _shake = 0;
  double _hitFlash = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ??
        BattleSyncController.fromRoom(
          room: widget.room,
          localPlayerId: widget.myPlayerId,
          adapter: widget.adapter,
          isHost: widget.isHost,
        );
    _controller.onMatchEnded = (winner) {
      if (!mounted) return;
      SfxService.instance.win();
      setState(() {});
    };
    _controller.onPlayerDefeated = (defender) {
      if (!mounted) return;
      SfxService.instance.death();
      if (defender.isLocal) {
        _shake = 1;
        _hitFlash = 1;
      }
      setState(() {});
    };
    _controller.onPlayerHit = (defender) {
      if (!mounted) return;
      SfxService.instance.hit();
      if (defender.isLocal) {
        _hitFlash = 1;
      }
    };
    _controller.onShotFired = (shooter) {
      if (!mounted) return;
      if (shooter.isLocal) {
        SfxService.instance.shoot();
      }
    };
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == null) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick!).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    _controller.step(dt.clamp(0.0, 0.1));
    if (_shake > 0) _shake = (_shake - dt * 3).clamp(0.0, 1.0);
    if (_hitFlash > 0) _hitFlash = (_hitFlash - dt * 2.5).clamp(0.0, 1.0);
    if (mounted) setState(() {});
  }

  void _onMoveChanged(Offset direction) {
    _move = direction;
    _syncInput();
  }

  void _onFiringChanged(bool firing) {
    _firing = firing;
    _syncInput();
  }

  void _syncInput() {
    _controller.setLocalInput(moveX: _move.dx, moveY: _move.dy, firing: _firing);
    _controller.sendLocalInputToHost();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxSize = constraints.biggest;
          final viewport = widget.virtualResolution.fitWithin(maxSize);
          final scale = viewport.width / widget.virtualResolution.width;

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: ArenaBackdropPainter(scale: scale),
                  size: Size.infinite,
                ),
              ),
              Positioned.fill(
                child: Transform.translate(
                  offset: _shakeOffset(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildArena(viewport, scale),
                      if (_hitFlash > 0)
                        IgnorePointer(
                          child: Container(
                            color: Colors.red.withValues(
                              alpha: 0.28 * _hitFlash,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _buildHud(),
              if (!_controller.isMatchOver) ...[
                Positioned(
                  left: 18,
                  bottom: 18,
                  child: VirtualJoystick(
                    onChanged: _onMoveChanged,
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: ActionButton(
                    onPressedChanged: _onFiringChanged,
                  ),
                ),
              ],
              if (_controller.isMatchOver) _buildMatchOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildArena(Rect viewport, double scale) {
    return Positioned(
      left: viewport.left,
      top: viewport.top,
      width: viewport.width,
      height: viewport.height,
      child: CustomPaint(
        painter: ArenaPainter(
          controller: _controller,
          scale: scale,
        ),
        size: viewport.size,
      ),
    );
  }

  Offset _shakeOffset() {
    if (_shake <= 0) return Offset.zero;
    final t = _lastTick?.inMilliseconds ?? 0;
    final amplitude = 7 * _shake;
    return Offset(
      sin(t / 45) * amplitude,
      cos(t / 61) * amplitude,
    );
  }

  Widget _buildHud() {
    final redHp = _controller.players.values
        .where((p) => p.team == Team.red)
        .fold(0, (sum, p) => sum + p.hp);
    final blueHp = _controller.players.values
        .where((p) => p.team == Team.blue)
        .fold(0, (sum, p) => sum + p.hp);

    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.paddingOf(context).top + 8,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _TeamHud(
                team: Team.red,
                alive: _controller.aliveRedCount,
                hp: redHp,
                accent: AppColors.p2,
              ),
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderStrong),
                    ),
                    child: Text(
                      'BATTLE SYNC',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            letterSpacing: 2,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
              _TeamHud(
                team: Team.blue,
                alive: _controller.aliveBlueCount,
                hp: blueHp,
                accent: AppColors.p1,
                alignEnd: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchOverlay() {
    final winner = _controller.winnerTeam;
    final accent = winner == Team.red ? AppColors.p2 : AppColors.p1;
    final title = winner == null ? 'DRAW' : '${winner.tag} TEAM WINS';

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.6),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  winner == null
                      ? 'Both teams eliminated.'
                      : '${_controller.aliveRedCount}R  —  ${_controller.aliveBlueCount}B',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 22),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.borderStrong),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Back to Lobby'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamHud extends StatelessWidget {
  const _TeamHud({
    required this.team,
    required this.alive,
    required this.hp,
    required this.accent,
    this.alignEnd = false,
  });

  final Team team;
  final int alive;
  final int hp;
  final Color accent;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment:
              alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              '${team.tag} TEAM',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              '$alive alive · $hp HP',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: content,
    );
  }
}