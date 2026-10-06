import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/prefs_store.dart';

enum GameMode { vsAi, friend }

enum Difficulty {
  easy('Easy', 'Up to 4 turns each', 120, 'Completes lines, blocks threats, sees capture chains and begi or treghi set-ups. Plays a little differently each game.'),
  medium('Medium', 'Up to 6 turns each', 90, 'Plans two-line and swinging set-ups and calculates endgames further. Hard to predict.'),
  hard('Hard', 'Up to 9 turns each', 60, 'Looks furthest ahead, calculates endgames to the end, builds begi and treghi on purpose and never repeats itself.');

  const Difficulty(this.label, this.depth, this.turnSeconds, this.blurb);
  final String label;
  final String depth;

  /// Per-turn clock for this level.
  final int turnSeconds;
  final String blurb;

  String get clock => '${turnSeconds ~/ 60}:${(turnSeconds % 60).toString().padLeft(2, '0')}';
}

/// Everything the mode-setup screen decides.
@immutable
class GameSetup {
  const GameSetup({
    this.mode = GameMode.vsAi,
    this.difficulty = Difficulty.medium,
    this.humanFirst = true,
    this.friendNames = const ['Player 1', 'Player 2'],
  });

  final GameMode mode;
  final Difficulty difficulty;

  /// vs AI: the human takes seat 0 (places and moves first) when true.
  final bool humanFirst;
  final List<String> friendNames;

  static const String aiName = 'Naw Bot';

  /// Seat that the AI plays, or null in two-player mode.
  int? get aiSeat => mode == GameMode.vsAi ? (humanFirst ? 1 : 0) : null;

  List<String> get names {
    if (mode == GameMode.friend) return friendNames;
    return humanFirst ? ['You', aiName] : [aiName, 'You'];
  }

  int get turnSeconds => mode == GameMode.vsAi ? difficulty.turnSeconds : 120;

  GameSetup copyWith({
    GameMode? mode,
    Difficulty? difficulty,
    bool? humanFirst,
    List<String>? friendNames,
  }) =>
      GameSetup(
        mode: mode ?? this.mode,
        difficulty: difficulty ?? this.difficulty,
        humanFirst: humanFirst ?? this.humanFirst,
        friendNames: friendNames ?? this.friendNames,
      );
}

/// Remembers the last difficulty, who went first and the friend names.
class SetupController extends Notifier<GameSetup> {
  static const _key = 'setup.v1';

  @override
  GameSetup build() {
    final raw = ref.read(prefsStoreProvider).read(_key);
    if (raw == null) return const GameSetup();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const GameSetup();
      final names = j['names'];
      return GameSetup(
        difficulty: Difficulty.values.firstWhere(
          (d) => d.name == j['difficulty'],
          orElse: () => Difficulty.medium,
        ),
        humanFirst: j['humanFirst'] is bool ? j['humanFirst'] as bool : true,
        friendNames: names is List && names.length == 2 && names.every((n) => n is String && n.trim().isNotEmpty)
            ? [names[0] as String, names[1] as String]
            : const ['Player 1', 'Player 2'],
      );
    } catch (_) {
      return const GameSetup();
    }
  }

  void _save() {
    final s = state;
    ref.read(prefsStoreProvider).write(
          _key,
          jsonEncode({'difficulty': s.difficulty.name, 'humanFirst': s.humanFirst, 'names': s.friendNames}),
        );
  }

  // the mode is chosen on the home screen each time, so it is not saved
  void setMode(GameMode m) => state = state.copyWith(mode: m);

  void setDifficulty(Difficulty d) {
    state = state.copyWith(difficulty: d);
    _save();
  }

  void setHumanFirst(bool v) {
    state = state.copyWith(humanFirst: v);
    _save();
  }

  void setFriendNames(String a, String b) {
    state = state.copyWith(friendNames: [a, b]);
    _save();
  }
}

final setupProvider = NotifierProvider<SetupController, GameSetup>(SetupController.new);
