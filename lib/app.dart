import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/player_setup/presentation/player_setup_screen.dart';

class BlueLinkPartyApp extends StatelessWidget {
  const BlueLinkPartyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueLink Party',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const PlayerSetupScreen(),
    );
  }
}