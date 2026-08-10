/// The two sides of a match: Red vs Blue. Each team seats up to [Team.capacity]
/// players (seat indices 0 and 1).
enum Team {
  red('RED'),
  blue('BLUE');

  const Team(this.tag);

  final String tag;

  /// Maximum number of players that can sit on one team.
  static const int capacity = 2;

  static const List<Team> all = [Team.red, Team.blue];

  static Team fromTag(String? tag) {
    return all.firstWhere(
      (t) => t.tag == tag,
      orElse: () => Team.red,
    );
  }

  /// Key used for the serialized teams map.
  String get key => tag;
}
