import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import 'haptics.dart';
import 'prefs_store.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.soundOn = true,
    this.hapticsOn = true,
    this.language = 'en',
    this.lowPower = false,
    this.reduceMotion = false,
  });

  final bool soundOn;
  final bool hapticsOn;

  /// ISO code. Only English ships now; voice lines for other languages slot in
  /// under assets/audio/voice/<code>/ (see SoundCatalog).
  final String language;
  final bool lowPower;
  final bool reduceMotion;

  MotionPrefs get motion => MotionPrefs(lowPower: lowPower, reduceMotion: reduceMotion);

  AppSettings copyWith({
    bool? soundOn,
    bool? hapticsOn,
    String? language,
    bool? lowPower,
    bool? reduceMotion,
  }) =>
      AppSettings(
        soundOn: soundOn ?? this.soundOn,
        hapticsOn: hapticsOn ?? this.hapticsOn,
        language: language ?? this.language,
        lowPower: lowPower ?? this.lowPower,
        reduceMotion: reduceMotion ?? this.reduceMotion,
      );

  Map<String, Object> toJson() => {
        'soundOn': soundOn,
        'hapticsOn': hapticsOn,
        'language': language,
        'lowPower': lowPower,
        'reduceMotion': reduceMotion,
      };

  /// Tolerant: missing or wrongly typed fields fall back to the defaults.
  static AppSettings fromJson(Object? j) {
    if (j is! Map) return const AppSettings();
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    return AppSettings(
      soundOn: b('soundOn', true),
      hapticsOn: b('hapticsOn', true),
      language: j['language'] is String ? j['language'] as String : 'en',
      lowPower: b('lowPower', false),
      reduceMotion: b('reduceMotion', false),
    );
  }
}

/// Loads the saved settings on start and saves after every change.
class SettingsController extends Notifier<AppSettings> {
  static const _key = 'settings.v1';

  @override
  AppSettings build() {
    AppSettings loaded = const AppSettings();
    final raw = ref.read(prefsStoreProvider).read(_key);
    if (raw != null) {
      try {
        loaded = AppSettings.fromJson(jsonDecode(raw));
      } catch (_) {
        // corrupt value: start from defaults
      }
    }
    Haptics.enabled = loaded.hapticsOn;
    return loaded;
  }

  void _set(AppSettings s) {
    state = s;
    Haptics.enabled = s.hapticsOn;
    ref.read(prefsStoreProvider).write(_key, jsonEncode(s.toJson()));
  }

  void setSound(bool v) => _set(state.copyWith(soundOn: v));
  void setHaptics(bool v) => _set(state.copyWith(hapticsOn: v));
  void setLanguage(String code) => _set(state.copyWith(language: code));
  void setLowPower(bool v) => _set(state.copyWith(lowPower: v));
  void setReduceMotion(bool v) => _set(state.copyWith(reduceMotion: v));
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
