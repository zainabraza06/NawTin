import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum GameMode { vsAi, friend }

enum Difficulty {
  easy('Easy', 'Depth 2', 120, 'Completes lines and blocks one-move threats. Cannot see begi or treghi.'),
  medium('Medium', 'Depth 3-4', 90, 'Also blocks a forming begi and plans simple two-line setups.'),
  hard('Hard', 'Depth 5-6', 60, 'Builds begi and treghi on purpose, even during placement.');

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

  /// vs AI: the human takes seat 0 (moves first, opening double) when true.
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

class SetupController extends Notifier<GameSetup> {
  @override
  GameSetup build() => const GameSetup();

  void setMode(GameMode m) => state = state.copyWith(mode: m);
  void setDifficulty(Difficulty d) => state = state.copyWith(difficulty: d);
  void setHumanFirst(bool v) => state = state.copyWith(humanFirst: v);
  void setFriendNames(String a, String b) => state = state.copyWith(friendNames: [a, b]);
}

final setupProvider = NotifierProvider<SetupController, GameSetup>(SetupController.new);
