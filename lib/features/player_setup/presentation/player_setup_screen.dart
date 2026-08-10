import 'package:flutter/material.dart';

import '../../../core/theme/acrylic.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_launcher_icon.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../lobby/presentation/lobby_screen.dart';

/// First screen of the game: choose your player name. The name is saved on
/// device (shared_preferences) and pre-filled on the next launch.
class PlayerSetupScreen extends StatefulWidget {
  const PlayerSetupScreen({super.key});

  @override
  State<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends State<PlayerSetupScreen> {
  final ProfileRepository _profile = ProfileRepository();
  late final TextEditingController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadSavedName();
  }

  Future<void> _loadSavedName() async {
    final saved = await _profile.loadPlayerName();
    if (!mounted) return;
    setState(() {
      _controller.text = saved;
      _loading = false;
    });
  }

  Future<void> _continue() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    await _profile.savePlayerName(name);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const LobbyScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AcrylicBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.borderStrong),
                        ),
                        child: const AppLauncherIcon(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'BlueLink Party',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Local Wi-Fi multiplayer for up to 4 players',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 36),
                    GlassPanel(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'CHOOSE YOUR NAME',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _controller,
                            enabled: !_loading,
                            autofocus: true,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 16,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 16),
                            decoration: const InputDecoration(
                              hintText: 'Player name',
                              counterText: '',
                              prefixIcon: Icon(Icons.person_rounded,
                                  size: 20, color: AppColors.textMuted),
                            ),
                            onSubmitted: (_) => _continue(),
                          ),
                          const SizedBox(height: 16),
                          GlassButton(
                            label: 'Continue to Lobby',
                            icon: Icons.arrow_forward_rounded,
                            background: AppColors.accent.withValues(alpha: 0.16),
                            expanded: true,
                            onPressed: _loading ? null : _continue,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Your name is saved on this device.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
