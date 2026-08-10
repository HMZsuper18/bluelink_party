enum GamePhase {
  lobby('lobby'),
  countdown('countdown'),
  inGame('in_game'),
  matchResult('match_result');

  const GamePhase(this.key);

  final String key;

  static GamePhase fromKey(String key) {
    return values.firstWhere(
      (phase) => phase.key == key,
      orElse: () => GamePhase.lobby,
    );
  }
}
