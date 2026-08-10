import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum SfxTrack {
  shoot,
  hit,
  death,
  kick,
  bounce,
  goal,
  whistle,
  win,
  tick,
}

class SfxService {
  SfxService._();

  static final SfxService instance = SfxService._();

  bool _muted = false;
  double _volume = 0.7;
  final Map<SfxTrack, AudioPlayer> _players = {};

  bool get muted => _muted;

  void setMuted(bool value) {
    _muted = value;
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
  }

  Future<void> play(SfxTrack track, {double? volume}) async {
    if (_muted) return;
    if (kIsWeb) return;
    try {
      final player = _players.putIfAbsent(
        track,
        () => AudioPlayer(),
      );
      await player.stop();
      await player.setVolume(_volume * (volume ?? 1.0));
      await player.play(AssetSource('audio/${track.name}.wav'));
    } catch (_) {}
  }
}

extension SfxPlay on SfxService {
  void shoot() {
    unawaited(play(SfxTrack.shoot, volume: 0.8));
  }

  void hit() {
    unawaited(play(SfxTrack.hit));
  }

  void death() {
    unawaited(play(SfxTrack.death));
  }

  void kick() {
    unawaited(play(SfxTrack.kick));
  }

  void bounce() {
    unawaited(play(SfxTrack.bounce, volume: 0.6));
  }

  void goal() {
    unawaited(play(SfxTrack.goal));
  }

  void whistle() {
    unawaited(play(SfxTrack.whistle));
  }

  void win() {
    unawaited(play(SfxTrack.win));
  }

  void tick() {
    unawaited(play(SfxTrack.tick, volume: 0.5));
  }
}