import 'dart:math' as math;

import '../engine/engine.dart';
import 'ai_config.dart';
import 'searcher.dart';

/// How one self-play game ended.
final class GameOutcome {
  const GameOutcome(this.winner, this.plies, this.reason, this.capped);

  /// Winning seat, or null for a draw / unfinished game.
  final int? winner;
  final int plies;
  final GameEndReason? reason;

  /// True when the ply limit ended it (counted as a draw).
  final bool capped;
}

/// Plays one game between two configs. [openingPlies] random legal moves are
/// played first (seeded by [seed]) so repeated games are not identical.
GameOutcome playGame(
  AiConfig seat0,
  AiConfig seat1, {
  int maxPlies = 300,
  int openingPlies = 0,
  int seed = 0,
}) {
  final rnd = math.Random(seed);
  var s = GameState.initial();
  var plies = 0;
  while (!s.isOver && plies < maxPlies) {
    final Move m;
    if (plies < openingPlies) {
      final moves = Rules.legalMoves(s);
      m = moves[rnd.nextInt(moves.length)];
    } else {
      m = Searcher(s.turn == 0 ? seat0 : seat1).search(s).move;
    }
    s = Rules.apply(s, m);
    plies++;
  }
  final r = s.result;
  return GameOutcome(r?.winner, plies, r?.reason, r == null);
}

/// Aggregate of a match between config A and config B (seats alternate).
final class MatchStats {
  int aWins = 0, bWins = 0, draws = 0;
  int seat0Wins = 0, seat1Wins = 0;
  int plies = 0, games = 0;

  double get aScore => (aWins + draws / 2) / games;

  void add(GameOutcome o, {required bool aIsSeat0}) {
    games++;
    plies += o.plies;
    final w = o.winner;
    if (w == null) {
      draws++;
      return;
    }
    if (w == 0) {
      seat0Wins++;
    } else {
      seat1Wins++;
    }
    final aWon = (w == 0) == aIsSeat0;
    aWon ? aWins++ : bWins++;
  }

  @override
  String toString() =>
      'A $aWins - $bWins B, draws $draws | seat0 wins $seat0Wins, seat1 wins $seat1Wins '
      '| avg plies ${(plies / games).toStringAsFixed(0)}';
}

/// Plays [games] games between A and B, swapping seats every game. With
/// [mirrorOpenings] each pair of games shares an opening (fair for different
/// engines); turn it off for identical engines so every game is independent.
MatchStats playMatch(
  AiConfig a,
  AiConfig b, {
  int games = 10,
  int maxPlies = 300,
  int openingPlies = 6,
  int seed = 1,
  bool mirrorOpenings = true,
  void Function(int game, GameOutcome outcome, bool aIsSeat0)? onGame,
}) {
  final stats = MatchStats();
  for (var g = 0; g < games; g++) {
    final aIsSeat0 = g.isEven;
    // each pair of games uses the same opening so seats are compared fairly
    final o = playGame(
      aIsSeat0 ? a : b,
      aIsSeat0 ? b : a,
      maxPlies: maxPlies,
      openingPlies: openingPlies,
      seed: mirrorOpenings ? seed + g ~/ 2 : seed + g,
    );
    stats.add(o, aIsSeat0: aIsSeat0);
    onGame?.call(g, o, aIsSeat0);
  }
  return stats;
}
