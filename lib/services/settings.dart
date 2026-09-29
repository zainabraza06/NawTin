import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.soundOn = true,
    this.language = 'en',
    this.lowPower = false,
    this.reduceMotion = false,
  });

  final bool soundOn;

  /// ISO code. Only English ships now; the selector is ready for local-language
  /// voice lines (Stage 7).
  final String language;
  final bool lowPower;
  final bool reduceMotion;

  MotionPrefs get motion => MotionPrefs(lowPower: lowPower, reduceMotion: reduceMotion);

  AppSettings copyWith({bool? soundOn, String? language, bool? lowPower, bool? reduceMotion}) =>
      AppSettings(
        soundOn: soundOn ?? this.soundOn,
        language: language ?? this.language,
        lowPower: lowPower ?? this.lowPower,
        reduceMotion: reduceMotion ?? this.reduceMotion,
      );
}

/// In-memory for now; Stage 7 persists these with the stats.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void setSound(bool v) => state = state.copyWith(soundOn: v);
  void setLanguage(String code) => state = state.copyWith(language: code);
  void setLowPower(bool v) => state = state.copyWith(lowPower: v);
  void setReduceMotion(bool v) => state = state.copyWith(reduceMotion: v);
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
