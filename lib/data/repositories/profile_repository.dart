import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the player's display name locally. The short player id is kept in
/// memory only: it is regenerated on every launch so that multiple app
/// instances (e.g. two desktop copies on one machine) never share an identity,
/// which would make the host reject one of them as a duplicate.
class ProfileRepository {
  static const _nameKey = 'bluelink_party.player_name';

  static const _idAlphabet = 'abcdefghjkmnpqrstuvwxyz23456789';

  Future<String> loadPlayerId() async {
    return _generateId();
  }

  Future<String> loadPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey) ?? '';
  }

  Future<void> savePlayerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name.trim());
  }

  String _generateId() {
    final random = Random.secure();
    return List.generate(8, (_) => _idAlphabet[random.nextInt(_idAlphabet.length)])
        .join();
  }
}
