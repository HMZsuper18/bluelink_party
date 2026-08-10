import 'package:equatable/equatable.dart';

/// Game modes selectable on the dashboard.
enum GameMode {
  battleSync(
    'Battle Sync',
    'Red vs Blue',
    minPlayers: 2,
    description: 'Red team faces Blue team — 1v1 or 2v2.',
  ),
  pixelFutbol(
    'Pixel Futbol',
    'Red vs Blue',
    minPlayers: 2,
    description: 'Red faces Blue — 1v1 with two players, full 2v2 with four.',
  ),
  screenShift(
    'Screen Shift',
    'Sidelined devices',
    minPlayers: 2,
    description: 'Every device shows only its own slice of a shared arena.',
  );

  const GameMode(
    this.label,
    this.subtitle, {
    required this.minPlayers,
    required this.description,
  });

  final String label;
  final String subtitle;
  final String description;

  /// Minimum number of filled slots required before the host can start.
  final int minPlayers;

  static GameMode fromKey(String key) {
    return values.firstWhere(
      (m) => m.key == key,
      orElse: () => GameMode.battleSync,
    );
  }

  String get key => name;
}

/// Wire-safe serializable description of a game mode selection.
class GameModeSelection extends Equatable {
  const GameModeSelection(this.mode);

  final GameMode mode;

  Map<String, dynamic> toJson() => {'key': mode.key};

  static GameModeSelection fromJson(Map<String, dynamic> json) {
    return GameModeSelection(GameMode.fromKey(json['key'] as String? ?? ''));
  }

  @override
  List<Object?> get props => [mode];
}
