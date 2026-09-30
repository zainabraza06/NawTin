import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings.dart';

/// Every sound the game makes.
enum Sfx { place, move, phutas, machyas, begi, treghi, warning, tick, win, lose, draw }

/// Where each sound lives. Effects are in `assets/audio/<name>.wav`.
///
/// Voice lines for a language are optional extras in
/// `assets/audio/voice/<language code>/<name>.wav` (for example
/// `voice/ur/machyas.wav`). Drop the files in, list the folder under `assets:`
/// in pubspec.yaml, and they play a moment after the effect when that language
/// is selected. No code changes are needed.
abstract final class SoundCatalog {
  /// Sounds that can have a spoken line.
  static const Set<Sfx> voiced = {Sfx.phutas, Sfx.machyas, Sfx.begi, Sfx.treghi, Sfx.win, Sfx.lose, Sfx.draw};

  static String effect(Sfx s) => 'audio/${s.name}.wav';

  static String voice(String language, Sfx s) => 'audio/voice/$language/${s.name}.wav';

  /// Full asset path (as listed in the asset manifest) of a voice line.
  static String voiceManifestKey(String language, Sfx s) => 'assets/${voice(language, s)}';
}

abstract class SoundService {
  /// Master switch (the mute toggle).
  bool enabled = true;

  /// Language whose voice lines may play on top of the effects.
  String language = 'en';

  Future<void> play(Sfx sfx);
  void dispose() {}
}

/// Silent. The default in tests and on platforms without audio.
class NullSoundService extends SoundService {
  @override
  Future<void> play(Sfx sfx) async {}
}

/// Records what would have played (for tests).
class RecordingSoundService extends SoundService {
  final List<Sfx> played = [];

  @override
  Future<void> play(Sfx sfx) async {
    if (enabled) played.add(sfx);
  }
}

/// Null unless the app injects the real player (see `main`).
final soundServiceProvider = Provider<SoundService>((ref) {
  final s = NullSoundService();
  _bindSettings(ref, s);
  return s;
});

/// Keeps a service in step with the mute switch and language setting.
void bindSoundSettings(Ref ref, SoundService s) => _bindSettings(ref, s);

void _bindSettings(Ref ref, SoundService s) {
  ref.listen<AppSettings>(settingsProvider, (_, n) {
    s.enabled = n.soundOn;
    s.language = n.language;
  }, fireImmediately: true);
}

/// Voice lines the app actually ships, read from the asset manifest.
Future<Set<String>> loadVoiceAssets() async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().where((a) => a.startsWith('assets/audio/voice/') && a.endsWith('.wav')).toSet();
  } catch (_) {
    return {};
  }
}
