import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'dart:math' as math;

import '../../../core/theme/acrylic.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/game_phase.dart';
import '../../../data/models/match_event.dart';
import '../../../data/models/team.dart';
import '../bloc/game_bloc.dart';
import '../bloc/game_event.dart';
import '../domain/match_player.dart';
import '../domain/match_projectile.dart';
import '../bloc/game_state.dart';
import 'screen_scaler.dart';
import '../sync/game_sync_adapter.dart';
import '../../battle_sync/presentation/widgets/action_button.dart';
import '../../battle_sync/presentation/widgets/virtual_joystick.dart';
import 'match_effects.dart';

Color _teamColor(Team team) => team == Team.red ? AppColors.p2 : AppColors.p1;

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.event,
    this.localPlayerId = '',
    this.sync,
  });

  final MatchEvent event;
  final String localPlayerId;
  final GameSyncAdapter? sync;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameBloc _gameBloc;

  @override
  void initState() {
    super.initState();
    _gameBloc = GameBloc(sync: widget.sync)
      ..add(MatchStarted(widget.event, localPlayerId: widget.localPlayerId));
  }

  @override
  void dispose() {
    _gameBloc.close();
    widget.sync?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _gameBloc,
      child: AcrylicBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: BlocConsumer<GameBloc, GameState>(
              listenWhen: (previous, current) =>
                  previous.phase != GamePhase.lobby &&
                  current.phase == GamePhase.lobby,
              listener: (context, state) => Navigator.of(context).pop(),
              buildWhen: (previous, current) => previous != current,
              builder: (context, state) {
                // Leaving the match clears config; never flash the spinner —
                // the listener above pops this route on the lobby transition.
                if (state.phase == GamePhase.lobby) {
                  return const SizedBox.shrink();
                }
                final config = state.config;
                if (config == null) {
                  return const _LoadingView();
                }
                final canLeavePause =
                    !state.isPaused || state.allPlayersReady;
                return PopScope(
                  canPop: canLeavePause,
                  child: ScreenScaler(
                    viewport: Size(
                      config.viewportWidth,
                      config.viewportHeight,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const GameCanvas(),
                        if (state.phase == GamePhase.countdown)
                          CountdownOverlay(
                            remaining: state.remainingSeconds,
                            viewport: Size(
                              config.viewportWidth,
                              config.viewportHeight,
                            ),
                          ),
                        if (state.phase == GamePhase.inGame ||
                            state.phase == GamePhase.matchResult) ...[
                          MatchCanvas(
                            players: state.players,
                            projectiles: state.projectiles,
                            elapsedMs: state.elapsedMs,
                          ),
                          MatchEffectsOverlay(state: state),
                          MatchHud(state: state),
                        ],
                        if (state.phase == GamePhase.inGame &&
                            !state.isPaused)
                          Positioned(
                            top: 20,
                            right: 20,
                            child: _PauseButton(
                              onTap: () =>
                                  _gameBloc.add(const PauseMatch()),
                            ),
                          ),
                        if (state.phase == GamePhase.inGame &&
                            !state.isPaused)
                          MatchControls(bloc: _gameBloc, state: state),
                        if (state.isPaused)
                          PauseOverlay(
                            state: state,
                            onReady: (playerId, ready) => _gameBloc
                                .add(PlayerReadyChanged(playerId, ready: ready)),
                            onResume: () =>
                                _gameBloc.add(const ResumeMatch()),
                            onRestart: () =>
                                _gameBloc.add(const RestartMatch()),
                            onQuit: () =>
                                _gameBloc.add(const ReturnToLobby()),
                          ),
                        if (state.phase == GamePhase.matchResult)
                          MatchResultOverlay(
                            outcome: state.outcome,
                            state: state,
                            onRestart: () =>
                                _gameBloc.add(const RestartMatch()),
                            onReturn: () =>
                                _gameBloc.add(const ReturnToLobby()),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class GameCanvas extends StatelessWidget {
  const GameCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const FieldPainter(),
      size: Size.infinite,
    );
  }
}

class FieldPainter extends CustomPainter {
  const FieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fieldRect = _centeredArenaRect(size);

    // Arena flooring: subtle vertical gradient over the base surface.
    final fillRect = Rect.fromLTWH(
      fieldRect.left,
      fieldRect.top,
      fieldRect.width,
      fieldRect.height,
    );
    final fieldPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.surfaceRaised.withValues(alpha: 0.9),
          AppColors.surface.withValues(alpha: 0.95),
        ],
      ).createShader(fillRect);
    canvas.drawRect(fillRect, fieldPaint);

    // Corner glow that reads as seat lighting on each team's side.
    final redZone = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.p2.withValues(alpha: 0.14),
          AppColors.p2.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(
        fieldRect.left,
        fieldRect.top,
        fieldRect.width * 0.35,
        fieldRect.height,
      ));
    canvas.drawRect(
      Rect.fromLTWH(
        fieldRect.left,
        fieldRect.top,
        fieldRect.width * 0.35,
        fieldRect.height,
      ),
      redZone,
    );
    final blueZone = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.p1.withValues(alpha: 0.14),
          AppColors.p1.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(
        fieldRect.left + fieldRect.width * 0.65,
        fieldRect.top,
        fieldRect.width * 0.35,
        fieldRect.height,
      ));
    canvas.drawRect(
      Rect.fromLTWH(
        fieldRect.left + fieldRect.width * 0.65,
        fieldRect.top,
        fieldRect.width * 0.35,
        fieldRect.height,
      ),
      blueZone,
    );

    // Faint tactical grid behind the action.
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    const gridCell = 42.0;
    for (var x = fieldRect.left; x < fieldRect.right; x += gridCell) {
      canvas.drawLine(Offset(x, fieldRect.top), Offset(x, fieldRect.bottom),
          gridPaint);
    }
    for (var y = fieldRect.top; y < fieldRect.bottom; y += gridCell) {
      canvas.drawLine(Offset(fieldRect.left, y), Offset(fieldRect.right, y),
          gridPaint);
    }

    // Center emblem ring with a soft glow.
    final center = fieldRect.center;
    final halo = Paint()..color = AppColors.accent.withValues(alpha: 0.08);
    canvas.drawCircle(center, 42, halo);
    final emblemPaint = Paint()
      ..color = AppColors.borderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 24, emblemPaint);
    canvas.drawCircle(center, 10, Paint()..color = AppColors.borderStrong);

    // Midfield divider.
    final midX = fieldRect.center.dx;
    final divider = Paint()
      ..color = AppColors.borderStrong
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(midX, fieldRect.top + 8),
      Offset(midX, fieldRect.bottom - 8),
      divider,
    );
    for (double dy = -18; dy <= 18; dy += 12) {
      canvas.drawCircle(
        Offset(midX, fieldRect.center.dy + dy),
        2,
        Paint()..color = AppColors.borderStrong,
      );
    }

    // Outer frame: thick rounded border with an inner highlight.
    final frame = Paint()
      ..color = AppColors.surfaceRaised
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawRect(fillRect.deflate(3), frame);
    final borderPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(fillRect.inflate(1), const Radius.circular(14)),
      borderPaint,
    );

    // Corner tick marks (corner-style arena markers).
    final tick = Paint()
      ..color = AppColors.textMuted
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const tLen = 18.0;
    final corners = [
      Offset(fieldRect.left, fieldRect.top),
      Offset(fieldRect.right, fieldRect.top),
      Offset(fieldRect.left, fieldRect.bottom),
      Offset(fieldRect.right, fieldRect.bottom),
    ];
    final signs = [
      (1.0, 1.0),
      (-1.0, 1.0),
      (1.0, -1.0),
      (-1.0, -1.0),
    ];
    for (var i = 0; i < 4; i++) {
      final c = corners[i];
      final (sx, sy) = signs[i];
      canvas.drawLine(c, Offset(c.dx + sx * tLen, c.dy), tick);
      canvas.drawLine(c, Offset(c.dx, c.dy + sy * tLen), tick);
    }
  }

  static const double _aspect = 4 / 3;

  Rect _centeredArenaRect(Size size) {
    final maxWidthFraction = 0.84;
    final maxHeightFraction = 0.76;
    const aspect = _aspect;

    var fieldWidth = size.width * maxWidthFraction;
    var fieldHeight = fieldWidth / aspect;
    if (fieldHeight > size.height * maxHeightFraction) {
      fieldHeight = size.height * maxHeightFraction;
      fieldWidth = fieldHeight * aspect;
    }

    final left = (size.width - fieldWidth) / 2;
    final top = (size.height - fieldHeight) / 2;
    return Rect.fromLTWH(left, top, fieldWidth, fieldHeight);
  }

  @override
  bool shouldRepaint(FieldPainter oldDelegate) => false;
}

class MatchCanvas extends StatelessWidget {
  const MatchCanvas({
    super.key,
    required this.players,
    required this.projectiles,
    required this.elapsedMs,
  });

  final List<MatchPlayer> players;
  final List<MatchProjectile> projectiles;
  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: MatchPainter(
        players: players,
        projectiles: projectiles,
        elapsedMs: elapsedMs,
        scale: ScaledViewport.scaleOf(context),
      ),
      size: Size.infinite,
    );
  }
}

class MatchPainter extends CustomPainter {
  const MatchPainter({
    required this.players,
    required this.projectiles,
    required this.elapsedMs,
    required this.scale,
  });

  final List<MatchPlayer> players;
  final List<MatchProjectile> projectiles;
  final int elapsedMs;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    for (final projectile in projectiles) {
      _paintProjectile(canvas, projectile);
    }
    for (final player in players) {
      _paintPlayer(canvas, player);
    }

    canvas.restore();
  }

  double get _phase => elapsedMs / 1000;

  void _paintProjectile(Canvas canvas, MatchProjectile projectile) {
    final color = _teamColor(projectile.ownerTeam);
    final position = Offset(projectile.x, projectile.y);

    // Velocity-aligned tail streak.
    final speed = math.sqrt(projectile.vx * projectile.vx + projectile.vy * projectile.vy);
    if (speed > 1) {
      final dir = Offset(projectile.vx / speed, projectile.vy / speed);
      final tailLen = 14.0 + speed * 0.03;
      final tail = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(position - dir * tailLen, position, tail);
    }

    // Pulsing glow, hot core.
    final pulse = 0.6 + 0.4 * math.sin(_phase * 14 + projectile.x);
    final glow = Paint()..color = color.withValues(alpha: 0.30 * pulse);
    canvas.drawCircle(position, 14, glow);
    final outer = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(position, 6, outer);
    final core = Paint()..color = color;
    canvas.drawCircle(position, 4.5, core);
    canvas.drawCircle(position, 2, Paint()..color = Colors.white);
  }

  void _paintPlayer(Canvas canvas, MatchPlayer player) {
    final color = _teamColor(player.team);
    final position = Offset(player.x, player.y);

    if (!player.alive) {
      _paintWreck(canvas, player, position, color);
      return;
    }

    final angle = math.atan2(player.facingY, player.facingX);
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(angle);

    // Soft team under-glow.
    final glow = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset.zero, player.radius * 1.8, glow);

    // Engine exhaust flicker while the ship is facing a direction.
    final flicker = 0.5 + 0.5 * math.sin(_phase * 30 + player.id.hashCode % 7);
    final engine = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.6 * flicker)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-player.radius * 0.8, 0),
      Offset(-player.radius * (1.1 + 0.25 * flicker), 0),
      engine,
    );

    // Hull: tapered arrow along the facing axis.
    final hull = Path()
      ..moveTo(player.radius * 1.05, 0)
      ..lineTo(-player.radius * 0.75, player.radius * 0.8)
      ..lineTo(-player.radius * 0.45, 0)
      ..lineTo(-player.radius * 0.75, -player.radius * 0.8)
      ..close();
    canvas.drawPath(
      hull,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      hull,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // Cockpit accent.
    canvas.drawCircle(
      Offset(player.radius * 0.35, 0),
      player.radius * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    canvas.restore();

    // Local player: pulsing target ring so the player always spots their seat.
    if (player.isLocal) {
      final ringPulse = 0.35 + 0.3 * math.sin(_phase * 5);
      final ring = Paint()
        ..color = Colors.white.withValues(alpha: ringPulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawCircle(position, player.radius * (1.5 + ringPulse * 0.6), ring);
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'YOU',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          position.dx - textPainter.width / 2,
          position.dy - player.radius - 22,
        ),
      );
    }

    _paintHealthBar(canvas, player, position);
  }

  void _paintWreck(Canvas canvas, MatchPlayer player, Offset position, Color color) {
    // Faded scorch mark with a broken X.
    final scorch = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(position, player.radius * 1.6, scorch);

    final cross = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final r = player.radius * 0.7;
    canvas.drawLine(position - Offset(r, r), position + Offset(r, r), cross);
    canvas.drawLine(position - Offset(-r, r), position + Offset(-r, r), cross);
  }

  void _paintHealthBar(Canvas canvas, MatchPlayer player, Offset position) {
    final width = player.hitboxSize;
    final top = position.dy - player.radius - 12;
    final left = position.dx - width / 2;
    final back = Paint()..color = AppColors.inactiveSlotDarker;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, 5),
      const Radius.circular(3),
    );
    canvas.drawRRect(track, back);
    final fillColor = Color.lerp(
      AppColors.danger,
      _teamColor(player.team),
      player.hpRatio,
    )!;
    final fill = Paint()..color = fillColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width * player.hpRatio, 5),
        const Radius.circular(3),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant MatchPainter oldDelegate) =>
      oldDelegate.players != players ||
      oldDelegate.projectiles != projectiles ||
      oldDelegate.elapsedMs != elapsedMs ||
      oldDelegate.scale != scale;
}

class MatchHud extends StatelessWidget {
  const MatchHud({super.key, required this.state});

  final GameState state;

  String _formatClock(int ms) {
    final total = (ms / 1000).round();
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scale = ScaledViewport.scaleOf(context);
    final redHp = state.totalTeamHp(Team.red);
    final redMax = state.totalTeamMaxHp(Team.red);
    final blueHp = state.totalTeamHp(Team.blue);
    final blueMax = state.totalTeamMaxHp(Team.blue);

    return Stack(
      children: [
        Positioned(
          top: 20,
          left: 32,
          child: GlassBadge(
            label: _labelFor(state.phase),
            icon: Icons.sports_esports_rounded,
          ),
        ),
        Positioned(
          top: 66,
          right: 40,
          child: Text(
            '${(scale * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: Center(
            child: _ScoreBar(
              redScore: state.redScore,
              blueScore: state.blueScore,
              redHp: redHp,
              redMax: redMax,
              blueHp: blueHp,
              blueMax: blueMax,
              clock: _formatClock(state.timeRemainingMs),
              duration: _formatClock(state.matchDurationMs),
            ),
          ),
        ),
      ],
    );
  }

  String _labelFor(GamePhase phase) {
    return switch (phase) {
      GamePhase.inGame => 'In Match',
      GamePhase.matchResult => 'Result',
      GamePhase.countdown => 'Starting',
      GamePhase.lobby => 'Waiting',
    };
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.redScore,
    required this.blueScore,
    required this.redHp,
    required this.redMax,
    required this.blueHp,
    required this.blueMax,
    required this.clock,
    required this.duration,
  });

  final int redScore;
  final int blueScore;
  final int redHp;
  final int redMax;
  final int blueHp;
  final int blueMax;
  final String clock;
  final String duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ScoreBarTeam(
            label: 'RED',
            score: redScore,
            hp: redHp,
            maxHp: redMax,
            color: AppColors.p2,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Text(
                  clock,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '/ $duration',
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          _ScoreBarTeam(
            label: 'BLUE',
            score: blueScore,
            hp: blueHp,
            maxHp: blueMax,
            color: AppColors.p1,
          ),
        ],
      ),
    );
  }
}

class _ScoreBarTeam extends StatelessWidget {
  const _ScoreBarTeam({
    required this.label,
    required this.score,
    required this.hp,
    required this.maxHp,
    required this.color,
  });

  final String label;
  final int score;
  final int hp;
  final int maxHp;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = maxHp == 0 ? 0.0 : hp / maxHp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$score',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            width: 64,
            height: 5,
            color: AppColors.inactiveSlotDarker,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ),
        ),
      ],
    );
  }
}

class MatchControls extends StatefulWidget {
  const MatchControls({super.key, required this.bloc, required this.state});

  final GameBloc bloc;
  final GameState state;

  @override
  State<MatchControls> createState() => _MatchControlsState();
}

class _MatchControlsState extends State<MatchControls> {
  double _moveX = 0;
  double _moveY = 0;
  bool _firing = false;

  void _pushInput() {
    widget.bloc.add(PlayerInputChanged(
      moveX: _moveX,
      moveY: _moveY,
      firing: _firing,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.state.players
        .where((p) => p.isLocal)
        .cast<MatchPlayer?>()
        .firstWhere((p) => p != null, orElse: () => null);
    final fireColor =
        local == null ? AppColors.danger : _teamColor(local.team);
    return Stack(
      children: [
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 28),
            child: VirtualJoystick(
              onChanged: (direction) {
                _moveX = direction.dx;
                _moveY = direction.dy;
                _pushInput();
              },
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 28, bottom: 28),
            child: ActionButton(
              onPressedChanged: (pressed) {
                _firing = pressed;
                _pushInput();
              },
              color: fireColor,
            ),
          ),
        ),
      ],
    );
  }
}

class CountdownOverlay extends StatefulWidget {
  const CountdownOverlay({
    super.key,
    required this.remaining,
    required this.viewport,
  });

  final int remaining;
  final Size viewport;

  @override
  State<CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.remaining;
    final viewport = widget.viewport;
    return Align(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final scale = 1 + _pulse.value * 0.12;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: viewport.width * 0.16,
                  height: viewport.width * 0.16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(
                          alpha: 0.35 * (1 - _pulse.value),
                        ),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Text(
                    '$remaining',
                    style: TextStyle(
                      fontSize: viewport.width * 0.06,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Get Ready',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class MatchResultOverlay extends StatefulWidget {
  const MatchResultOverlay({
    super.key,
    required this.outcome,
    required this.state,
    required this.onRestart,
    required this.onReturn,
  });

  final MatchOutcome? outcome;
  final GameState state;
  final VoidCallback onRestart;
  final VoidCallback onReturn;

  @override
  State<MatchResultOverlay> createState() => _MatchResultOverlayState();
}

class _MatchResultOverlayState extends State<MatchResultOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  late final Animation<double> _slide = Tween<double>(begin: 0.92, end: 1)
      .animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
  ));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (widget.outcome) {
      MatchOutcome.victory => ('VICTORY', AppColors.success),
      MatchOutcome.defeat => ('DEFEAT', AppColors.danger),
      MatchOutcome.draw => ('DRAW', AppColors.warning),
      null => ('MATCH OVER', AppColors.textSecondary),
    };

    return Container(
      color: Colors.black.withValues(alpha: 0.45 * _fade.value),
      alignment: Alignment.center,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Transform.scale(
            scale: _slide.value,
            child: Opacity(
              opacity: _fade.value,
              child: GlassPanel(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(
                          color: color.withValues(alpha: 0.7),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 32,
                          ),
                        ],
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${widget.state.redScore} — ${widget.state.blueScore}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 2,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 18),
                    GlassButton(
                      label: 'Restart',
                      icon: Icons.refresh_rounded,
                      onPressed: widget.onRestart,
                    ),
                    const SizedBox(height: 10),
                    GlassButton(
                      label: 'Quit',
                      icon: Icons.exit_to_app_rounded,
                      color: AppColors.danger,
                      onPressed: widget.onReturn,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x14FFFFFF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.pause_rounded, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.state,
    required this.onReady,
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
  });

  final GameState state;
  final void Function(String playerId, bool ready) onReady;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final readyCount = state.players
        .where((p) => state.readyPlayerIds.contains(p.id))
        .length;
    final total = state.players.length;
    final allReady = state.allPlayersReady;

    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paused',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              allReady
                  ? 'Everyone is ready'
                  : 'Each player readies on their own device',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            for (final player in state.players) ...[
              _ReadyRow(
                player: player,
                ready: state.readyPlayerIds.contains(player.id),
                interactive: player.isLocal,
                onToggle: () => onReady(
                  player.id,
                  !state.readyPlayerIds.contains(player.id),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '$readyCount / $total ready',
              style: TextStyle(
                fontSize: 12,
                color: allReady ? AppColors.success : AppColors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              allReady
                  ? 'Resume the match or quit to the lobby'
                  : 'Waiting for the other players…\nResume, Restart, and Quit unlock when everyone is ready',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: allReady ? AppColors.success : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                GlassButton(
                  label: 'Resume',
                  icon: Icons.play_arrow_rounded,
                  onPressed: allReady ? onResume : null,
                ),
                GlassButton(
                  label: 'Restart',
                  icon: Icons.refresh_rounded,
                  onPressed: allReady ? onRestart : null,
                ),
                GlassButton(
                  label: 'Quit',
                  icon: Icons.exit_to_app_rounded,
                  color: AppColors.danger,
                  onPressed: allReady ? onQuit : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyRow extends StatelessWidget {
  const _ReadyRow({
    required this.player,
    required this.ready,
    required this.interactive,
    required this.onToggle,
  });

  final MatchPlayer player;
  final bool ready;
  final bool interactive;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final borderColor = ready ? _teamColor(player.team) : AppColors.borderStrong;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _teamColor(player.team),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${player.name}${player.isLocal ? ' (you)' : ''}',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          ready ? 'READY' : 'WAITING',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: ready ? AppColors.success : AppColors.textMuted,
          ),
        ),
        if (interactive) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.touch_app_rounded,
            size: 14,
            color: ready ? AppColors.success : AppColors.textMuted,
          ),
        ],
      ],
    );

    if (!interactive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: content,
      );
    }

    return Material(
      color: const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: content,
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}