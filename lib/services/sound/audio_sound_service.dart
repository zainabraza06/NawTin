import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'sound_service.dart';

/// Plays the effects with a small pool of low-latency players so overlapping
/// sounds (a capture and a begi, say) do not cut each other off.
class AudioSoundService extends SoundService {
  AudioSoundService({this.voices = const {}}) {
    for (var i = 0; i < 4; i++) {
      final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      p.setPlayerMode(PlayerMode.lowLatency);
      _pool.add(p);
    }
  }

  /// Manifest keys of the voice lines that exist in this build.
  final Set<String> voices;

  final List<AudioPlayer> _pool = [];
  int _next = 0;

  @override
  Future<void> play(Sfx sfx) async {
    if (!enabled) return;
    await _fire(SoundCatalog.effect(sfx));
    if (SoundCatalog.voiced.contains(sfx) &&
        voices.contains(SoundCatalog.voiceManifestKey(language, sfx))) {
      // the spoken line lands just after the effect
      Timer(const Duration(milliseconds: 280), () {
        if (enabled) _fire(SoundCatalog.voice(language, sfx));
      });
    }
  }

  Future<void> _fire(String asset) async {
    try {
      final p = _pool[_next];
      _next = (_next + 1) % _pool.length;
      await p.stop();
      await p.play(AssetSource(asset));
    } catch (_) {
      // a missing codec or device must never break a move
    }
  }

  @override
  void dispose() {
    for (final p in _pool) {
      p.dispose();
    }
  }
}
