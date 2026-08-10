import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/acrylic.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/game_mode.dart';
import '../../../data/models/game_phase.dart';
import '../../../data/models/lobby_room.dart';
import '../../game/presentation/game_screen.dart';
import '../../../core/widgets/app_launcher_icon.dart';
import '../../matrix_arena/presentation/matrix_arena_screen.dart';
import '../../matrix_futbol/presentation/futbol_arena_screen.dart';
import '../bloc/lobby_bloc.dart';
import '../bloc/lobby_event.dart';
import '../bloc/lobby_state.dart';
import '../../about/presentation/about_screen.dart';
import 'widgets/action_bar.dart';
import 'widgets/mode_selector.dart';
import 'widgets/profile_card.dart';
import 'widgets/role_choice_panel.dart';
import 'widgets/room_code_card.dart';
import 'widgets/scanning_panel.dart';
import 'widgets/team_grid.dart';

/// Multiplayer Lobby / Dashboard screen (Windows 10 Acrylic theme).
class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => LobbyBloc(), child: const _LobbyView());
  }
}

class _LobbyView extends StatefulWidget {
  const _LobbyView();

  @override
  State<_LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends State<_LobbyView> {
  String? _lastErrorShown;
  bool _matchNoticeShown = false;
  bool _pickerShown = false;
  bool _joinRequested = false;
  bool _inGame = false;

  void _handleStateChange(BuildContext context, LobbyState state) {
    final bloc = context.read<LobbyBloc>();

    if (state.error != null && state.error != _lastErrorShown) {
      _lastErrorShown = state.error;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(state.error!)));
      bloc.add(const ClearNotice());
    }

    if (state.matchReady && !_matchNoticeShown) {
      _matchNoticeShown = true;
      _showMatchReadyDialog(context);
      bloc.add(const ClearNotice());
    }

    final matchEvent = state.matchEvent;
    if (!_inGame &&
        matchEvent != null &&
        matchEvent.phase == GamePhase.countdown) {
      _inGame = true;
      final mode = matchEvent.config.mode;
      final Widget screen;
      if (mode == GameMode.screenShift) {
        screen = MatrixArenaScreen(controller: state.matrixController!);
      } else if (mode == GameMode.pixelFutbol) {
        screen = FutbolArenaScreen(controller: state.futbolController!);
      } else {
        screen = GameScreen(
          event: matchEvent,
          localPlayerId: state.playerId,
          sync: state.gameSync,
        );
      }
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(builder: (_) => screen),
          )
          .then((_) {
        _inGame = false;
        if (context.mounted) bloc.add(const ReturnToLobby());
      });
    }

    final hasChoices =
        state.role == NetworkRole.scanning && state.foundLobbies.isNotEmpty;
    if (hasChoices && !_pickerShown) {
      _pickerShown = true;
      _showLobbyPicker(context);
    }
  }

  void _showMatchReadyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.rocket_launch_rounded,
              color: AppColors.success,
              size: 40,
            ),
            const SizedBox(height: 16),
            const Text(
              'Match is ready!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'All minimum players have joined. The in-match screen is the next milestone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            GlassButton(
              label: 'OK',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _showLobbyPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final state = context.read<LobbyBloc>().state;
        return BlocProvider.value(
          value: context.read<LobbyBloc>(),
          child: _LobbyPickerSheet(
            lobbies: state.foundLobbies,
            onJoinRequested: () => _joinRequested = true,
          ),
        );
      },
    ).whenComplete(() {
      // Barrier dismiss (or a join that never resolved) returns here while the
      // scan is still active; cancel it unless a join was actually requested.
      if (!_joinRequested && context.mounted) {
        final current = context.read<LobbyBloc>().state;
        if (current.role == NetworkRole.scanning) {
          context.read<LobbyBloc>().add(const CancelScan());
        }
      }
      _joinRequested = false;
      _pickerShown = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AcrylicBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: BlocListener<LobbyBloc, LobbyState>(
            listenWhen: (previous, current) => previous != current,
            listener: _handleStateChange,
            child: BlocBuilder<LobbyBloc, LobbyState>(
              builder: (context, state) {
                if (!state.profileLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildBody(context, state);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LobbyState state) {
    final bloc = context.read<LobbyBloc>();
    final inRoom = state.isHost || state.isClient;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _buildHeader(context, state),
        const SizedBox(height: 18),
        ProfileCard(
          name: state.playerName,
          playerId: state.playerId,
          onSaved: (value) => bloc.add(SavePlayerName(value)),
        ),
        const SizedBox(height: 14),
        const SizedBox(height: 18),
        if (state.role == NetworkRole.idle) ...[
          _sectionTitle('HOST OR GUEST?'),
          const SizedBox(height: 10),
          RoleChoicePanel(
            onHost: () => bloc.add(const CreateLobby()),
            onJoin: () => bloc.add(const ScanForLobbies()),
          ),
        ] else if (state.role == NetworkRole.scanning) ...[
          ScanningPanel(onCancel: () => bloc.add(const CancelScan())),
        ] else ...[
          if (state.room != null) ...[
            RoomCodeCard(
              roomCode: state.room!.roomCode,
              filledSlots: state.filledSlots,
              isHost: state.isHost,
            ),
            const SizedBox(height: 18),
          ],
          _sectionTitle('Choose Your Team'),
          const SizedBox(height: 10),
          TeamGrid(
            room: state.room!,
            rttMs: state.rttMs,
            connecting: state.connecting,
            myPlayerId: state.playerId,
            interactive: inRoom,
            onJoin: (team) => bloc.add(ClaimSlot(team)),
            onKick: (playerId) => bloc.add(KickMember(playerId)),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Game Mode'),
          const SizedBox(height: 10),
          ModeSelector(
            selected: state.room?.selectedMode,
            enabled: state.isHost && state.room != null,
            onSelected: (mode) => bloc.add(SelectMode(mode)),
          ),
          const SizedBox(height: 22),
          ActionBar(
            state: state,
            onStartMatch: () => bloc.add(const StartMatch()),
            onDisconnect: () => bloc.add(const Disconnect()),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader(BuildContext context, LobbyState state) {
    final (roleLabel, roleColor, roleIcon) = switch (state.role) {
      NetworkRole.hosting => ('Host Mode', AppColors.p1, Icons.cast_rounded),
      NetworkRole.client => ('Client Mode', AppColors.p4, Icons.link_rounded),
      NetworkRole.scanning => (
        'Searching...',
        AppColors.warning,
        Icons.radar_rounded,
      ),
      NetworkRole.idle => (
        'Idle',
        AppColors.textMuted,
        Icons.power_settings_new_rounded,
      ),
    };

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: const AppLauncherIcon(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BlueLink Party',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                state.room == null
                    ? 'Multiplayer Local Wi-Fi Lobby'
                    : 'Room ${state.room!.roomCode}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: state.room == null
                      ? AppColors.textMuted
                      : AppColors.p1,
                  fontWeight: state.room == null
                      ? FontWeight.w400
                      : FontWeight.w700,
                  letterSpacing: state.room == null ? 0 : 1.2,
                ),
              ),
            ],
          ),
        ),
        GlassBadge(label: roleLabel, color: roleColor, icon: roleIcon),
        const SizedBox(width: 8),
        Material(
          color: const Color(0x14FFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _LobbyPickerSheet extends StatelessWidget {
  const _LobbyPickerSheet({
    required this.lobbies,
    required this.onJoinRequested,
  });

  final List<DiscoveredLobby> lobbies;
  final VoidCallback onJoinRequested;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LobbyBloc>();
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Available Rooms',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${lobbies.length} room${lobbies.length == 1 ? '' : 's'} found on this network',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            for (final lobby in lobbies) ...[
              _LobbyRow(
                lobby: lobby,
                onJoin: () {
                  onJoinRequested();
                  Navigator.of(context).pop();
                  bloc.add(JoinDiscovered(lobby));
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: GlassButton(
                label: 'Cancel',
                compact: true,
                background: const Color(0x0AFFFFFF),
                onPressed: () {
                  Navigator.of(context).pop();
                  bloc.add(const CancelScan());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LobbyRow extends StatelessWidget {
  const _LobbyRow({required this.lobby, required this.onJoin});

  final DiscoveredLobby lobby;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.p1.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.p1.withValues(alpha: 0.35)),
            ),
            child: Text(
              lobby.roomCode,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: AppColors.p1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lobby.lobbyName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${lobby.mode.label}  •  ${lobby.filledSlots}/4  •  ${lobby.hostName}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlassButton(
            label: 'Join',
            compact: true,
            background: AppColors.p4.withValues(alpha: 0.12),
            onPressed: onJoin,
          ),
        ],
      ),
    );
  }
}
