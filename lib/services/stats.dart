import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/setup/game_setup.dart';
import 'prefs_store.dart';

/// Wins / losses / draws at one difficulty.
@immutable
class Record {
  const Record([this.wins = 0, this.losses = 0, this.draws = 0]);
  final int wins, losses, draws;

  int get games => wins + losses + draws;
  Record add({bool win = false, bool loss = false, bool draw = false}) =>
      Record(wins + (win ? 1 : 0), losses + (loss ? 1 : 0), draws + (draw ? 1 : 0));

  List<int> toJson() => [wins, losses, draws];
  static Record fromJson(Object? j) =>
      j is List && j.length == 3 && j.every((e) => e is int) ? Record(j[0] as int, j[1] as int, j[2] as int) : const Record();
}

/// Lifetime statistics, kept on the device.
@immutable
class PlayerStats {
  const PlayerStats({
    this.vsAi = const {},
    this.friendGames = 0,
    this.tokensEaten = 0,
    this.linesFormed = 0,
    this.swings = 0,
    this.streak = 0,
    this.bestStreak = 0,
  });

  /// Record per AI difficulty (by [Difficulty.name]).
  final Map<String, Record> vsAi;
  final int friendGames;

  /// Totals for the human across every game.
  final int tokensEaten, linesFormed, swings;

  /// Current and best winning streak against the AI.
  final int streak, bestStreak;

  Record recordFor(Difficulty d) => vsAi[d.name] ?? const Record();
  int get aiGames => vsAi.values.fold(0, (a, r) => a + r.games);
  int get totalGames => aiGames + friendGames;
  int get aiWins => vsAi.values.fold(0, (a, r) => a + r.wins);
  bool get isEmpty => totalGames == 0;

  Map<String, Object> toJson() => {
        'vsAi': {for (final e in vsAi.entries) e.key: e.value.toJson()},
        'friendGames': friendGames,
        'tokensEaten': tokensEaten,
        'linesFormed': linesFormed,
        'swings': swings,
        'streak': streak,
        'bestStreak': bestStreak,
      };

  static PlayerStats fromJson(Object? j) {
    if (j is! Map) return const PlayerStats();
    int n(String k) => j[k] is int ? j[k] as int : 0;
    final ai = <String, Record>{};
    final raw = j['vsAi'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String) ai[e.key as String] = Record.fromJson(e.value);
      }
    }
    return PlayerStats(
      vsAi: ai,
      friendGames: n('friendGames'),
      tokensEaten: n('tokensEaten'),
      linesFormed: n('linesFormed'),
      swings: n('swings'),
      streak: n('streak'),
      bestStreak: n('bestStreak'),
    );
  }
}

/// What one finished game adds to the statistics.
@immutable
class GameRecord {
  const GameRecord({
    required this.mode,
    required this.difficulty,
    required this.humanWon,
    required this.draw,
    required this.tokensEaten,
    required this.linesFormed,
    required this.swings,
  });

  final GameMode mode;
  final Difficulty difficulty;

  /// vs AI: the human won. Two-player: unused.
  final bool humanWon;
  final bool draw;
  final int tokensEaten, linesFormed, swings;
}

class StatsController extends Notifier<PlayerStats> {
  static const _key = 'stats.v1';

  @override
  PlayerStats build() {
    final raw = ref.read(prefsStoreProvider).read(_key);
    if (raw == null) return const PlayerStats();
    try {
      return PlayerStats.fromJson(jsonDecode(raw));
    } catch (_) {
      return const PlayerStats();
    }
  }

  void record(GameRecord g) {
    final s = state;
    var vsAi = s.vsAi;
    var friend = s.friendGames;
    var streak = s.streak;
    if (g.mode == GameMode.vsAi) {
      final r = s.recordFor(g.difficulty).add(win: g.humanWon && !g.draw, loss: !g.humanWon && !g.draw, draw: g.draw);
      vsAi = {...s.vsAi, g.difficulty.name: r};
      streak = g.humanWon && !g.draw ? s.streak + 1 : (g.draw ? s.streak : 0);
    } else {
      friend++;
    }
    _set(PlayerStats(
      vsAi: vsAi,
      friendGames: friend,
      tokensEaten: s.tokensEaten + g.tokensEaten,
      linesFormed: s.linesFormed + g.linesFormed,
      swings: s.swings + g.swings,
      streak: streak,
      bestStreak: streak > s.bestStreak ? streak : s.bestStreak,
    ));
  }

  void reset() => _set(const PlayerStats());

  void _set(PlayerStats s) {
    state = s;
    ref.read(prefsStoreProvider).write(_key, jsonEncode(s.toJson()));
  }
}

final statsProvider = NotifierProvider<StatsController, PlayerStats>(StatsController.new);
