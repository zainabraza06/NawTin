import 'dart:math' as math;

import '../engine/engine.dart';
import 'ai_config.dart';
import 'evaluator.dart';
import 'zobrist.dart';

/// Outcome of a search.
final class SearchResult {
  const SearchResult(this.move, this.score, this.depth, this.nodes);

  final Move move;

  /// Score for the side to move (centipawn-ish; +-Evaluator.win = decided).
  final int score;

  /// Deepest fully completed iteration.
  final int depth;
  final int nodes;
}

enum _Bound { exact, lower, upper }

class _Entry {
  _Entry(this.depth, this.score, this.bound, this.move);
  final int depth;
  final int score;
  final _Bound bound;
  final Move? move;
}

class _Abort implements Exception {
  const _Abort();
}

/// Negamax with alpha-beta pruning, iterative deepening under a time cap, a
/// Zobrist transposition table and capture-first move ordering.
///
/// Two details of Naw Tin shape the recursion:
///  * a capture is part of the move, so every capture choice is its own branch;
///  * the same seat can move twice in a row (each player's opening double
///    placement, and the closing double under the original rule), so the score is only negated, and the
///    window only flipped, when the side to move actually changes.
class Searcher {
  Searcher(this.cfg, {math.Random? random}) : _random = random ?? math.Random();

  final AiConfig cfg;
  final math.Random _random;

  final Map<int, _Entry> _tt = {};
  final Stopwatch _clock = Stopwatch();
  int _nodes = 0;
  int _reached = 0; // deepest iteration completed in this search
  bool _selecting = false; // the final choice among near-equal moves is running

  // Move-ordering memory, reset every search. A quiet move that caused a
  // cut-off is likely to cause one again in a sibling position (killer: same
  // ply; history: same step anywhere), so it is tried earlier. Better ordering
  // means more pruning, which means more depth in the same time.
  static const int _maxPly = 64;
  final List<Move?> _killer1 = List<Move?>.filled(_maxPly, null);
  final List<Move?> _killer2 = List<Move?>.filled(_maxPly, null);
  final List<int> _history = List<int>.filled((Board.pointCount + 1) * Board.pointCount, 0);

  static const int _inf = 1 << 30;
  static const int _ttLimit = 300000;

  // Point preference used only for ordering quiet moves: well-connected points
  // first (middle midpoints 4 neighbours, then 3, then corners).
  static final List<int> _pointRank = List.unmodifiable([
    for (var p = 0; p < Board.pointCount; p++) Board.neighbors[p].length,
  ]);

  /// Finds the best move for the side to move in [root]. With [onlyStep] the
  /// search is restricted to moves that make that step (used to pick which
  /// token to eat once the player has already chosen where to place/slide).
  SearchResult search(GameState root, {Move? onlyStep}) {
    var legal = Rules.legalMoves(root);
    if (onlyStep != null) {
      final same = legal.where((m) => m.step == onlyStep).toList();
      if (same.isNotEmpty) legal = same;
    }
    assert(legal.isNotEmpty, 'search called on a finished game');
    if (legal.length == 1) return SearchResult(legal.first, 0, 0, 0);

    _clock
      ..reset()
      ..start();
    _nodes = 0;
    _reached = 0;
    _tt.clear();
    _killer1.fillRange(0, _maxPly, null);
    _killer2.fillRange(0, _maxPly, null);
    _history.fillRange(0, _history.length, 0);

    var ordered = _order(legal, root, null, 0);
    var best = ordered.first;
    var bestScore = 0;
    var reached = 0;

    // few tokens left: branching is small, so calculate further
    final tokens = root.totalTokens(0) + root.totalTokens(1);
    final maxDepth = cfg.maxDepth + (tokens <= 8 ? cfg.endgameDepthBonus : (tokens <= 11 ? cfg.endgameDepthBonus ~/ 2 : 0));
    try {
      for (var depth = 1; depth <= maxDepth; depth++) {
        var alpha = -_inf;
        Move iterBest = ordered.first;
        var iterScore = -_inf;
        final scores = <Move, int>{};
        var first = true;
        for (final m in ordered) {
          final child = Rules.apply(root, m);
          // principal variation search: the best-so-far move gets the full
          // window; the others only have to prove they are not better
          var v = first
              ? _childScore(root, child, depth - 1, alpha, _inf, 1)
              : _childScore(root, child, depth - 1, alpha, alpha + 1, 1);
          if (!first && v > alpha) v = _childScore(root, child, depth - 1, alpha, _inf, 1);
          first = false;
          v -= _repeatPenalty(root, child);
          scores[m] = v;
          if (v > iterScore) {
            iterScore = v;
            iterBest = m;
          }
          if (v > alpha) alpha = v;
        }
        // depth finished: commit it and search the best move first next time
        best = iterBest;
        bestScore = iterScore;
        reached = depth;
        _reached = depth;
        ordered = [
          iterBest,
          ...ordered.where((m) => m != iterBest).toList()
            ..sort((a, b) => scores[b]!.compareTo(scores[a]!)),
        ];
        if (bestScore.abs() >= Evaluator.win - 200) break; // forced result
        // next iteration is too dear (but never stop before the guaranteed depth)
        if (depth >= cfg.minDepth && _clock.elapsedMilliseconds > cfg.timeMs * 0.6) break;
      }
    } on _Abort {
      // out of time mid-iteration: keep the last completed depth
    }
    if (reached >= 2 && bestScore.abs() < Evaluator.win - 200) {
      _selecting = true;
      try {
        best = _chooseAmongNearBest(root, ordered, best, bestScore, reached);
      } finally {
        _selecting = false;
      }
    }
    return SearchResult(best, bestScore, reached, _nodes);
  }

  /// The exact value of [s] for the side to move, searched to [depth] plies with
  /// a full window (no early stop, no time limit beyond the usual cap). Used by
  /// analysis tools; unlike [search] it also works when there is one legal move.
  int valueOf(GameState s, int depth) {
    _clock
      ..reset()
      ..start();
    _nodes = 0;
    _reached = depth; // do not stretch the clock: analysis sets its own limits
    _tt.clear();
    _killer1.fillRange(0, _maxPly, null);
    _killer2.fillRange(0, _maxPly, null);
    _history.fillRange(0, _history.length, 0);
    try {
      return _negamax(s, depth, -_inf, _inf, 0);
    } on _Abort {
      return Evaluator.evaluate(s, s.turn, cfg);
    }
  }

  /// The final choice among moves that are about equally good. Values that close
  /// are decided by noise (they flip between odd and even search depths), so the
  /// choice is made on principle instead:
  ///   1. a move that eats a token ([AiConfig.capturePreference]);
  ///   2. if the best move leaves the opponent a line to complete next turn, a
  ///      nearly-as-good move that does not ([AiConfig.safetyPreference]);
  ///   3. otherwise a random one of the nearly-equal moves, so the AI does not
  ///      play the same game every time ([AiConfig.varietyMargin]).
  /// A move qualifies with an exact value within the margin of the best one.
  Move _chooseAmongNearBest(GameState root, List<Move> ordered, Move best, int bestScore, int depth) {
    final reach = [cfg.varietyMargin, cfg.capturePreference, cfg.safetyPreference].reduce(math.max);
    if (reach <= 0) return best;
    // Candidates: every move within twice the largest margin at the last depth.
    // Their values are then averaged with the value one depth shallower, which
    // cancels the odd/even oscillation of the search (a quiet move can look
    // 50 points better or worse depending on the parity of the depth).
    final wide = reach * 2;
    final deep = <Move, int>{best: bestScore};
    // captures are tested first, so the capture rule still works if time runs out
    final order = [
      ...ordered.where((m) => m != best && m.hasCapture),
      ...ordered.where((m) => m != best && !m.hasCapture),
    ];
    final line = bestScore - wide;
    try {
      for (final m in order) {
        final child = Rules.apply(root, m);
        final penalty = _repeatPenalty(root, child);
        // cheap pass/fail test first; the exact value only for the few that pass
        final quick = _childScore(root, child, depth - 1, line - 1 + penalty, line + penalty, 1) - penalty;
        if (quick < line) continue;
        deep[m] = _childScore(root, child, depth - 1, line - 1 + penalty, _inf, 1) - penalty;
      }
    } on _Abort {
      // keep what was found so far
    }
    final values = <Move, int>{};
    var smoothed = depth >= 3 && deep.length > 1;
    if (smoothed) {
      try {
        for (final e in deep.entries) {
          final child = Rules.apply(root, e.key);
          var w = _childScore(root, child, depth - 2, -_inf, _inf, 1);
          w -= _repeatPenalty(root, child);
          values[e.key] = (e.value + w) ~/ 2;
        }
      } on _Abort {
        smoothed = false;
      }
    }
    if (!smoothed) {
      values
        ..clear()
        ..addAll(deep);
    }
    final top = values.values.reduce(math.max);
    final leader = values.entries.firstWhere((e) => e.value == top).key;
    int gap(Move m) => top - values[m]!;

    bool unsafe(Move m) {
      final child = Rules.apply(root, m);
      if (child.isOver) return false;
      return Analysis.threatLines(child, 1 - root.turn) != 0 && child.turn != root.turn;
    }

    if (cfg.capturePreference > 0) {
      // a capture that is nearly as good as the best move wins; variety then
      // only chooses among the captures (never trades one for a quiet move)
      final caps = [for (final m in values.keys) if (m.hasCapture && gap(m) <= cfg.capturePreference) m];
      if (caps.isNotEmpty) {
        final topCap = caps.map((m) => values[m]!).reduce(math.max);
        final pool = [for (final m in caps) if (topCap - values[m]! <= cfg.varietyMargin) m];
        return pool[_random.nextInt(pool.length)];
      }
    }
    var pool = [for (final m in values.keys) if (gap(m) <= cfg.varietyMargin) m];
    if (cfg.safetyPreference > 0 && !leader.hasCapture && unsafe(leader)) {
      final safe = [for (final m in values.keys) if (gap(m) <= cfg.safetyPreference && !unsafe(m)) m];
      if (safe.isNotEmpty) {
        final topSafe = safe.map((m) => values[m]!).reduce(math.max);
        pool = [for (final m in safe) if (topSafe - values[m]! <= cfg.varietyMargin) m];
      }
    }
    if (pool.isEmpty) pool = [leader];
    return pool[_random.nextInt(pool.length)];
  }

  // ------------------------------------------------------------ recursion

  /// Value of [child] from [parent]'s side-to-move perspective.
  int _childScore(GameState parent, GameState child, int depth, int alpha, int beta, int ply) {
    if (child.turn == parent.turn) {
      return _negamax(child, depth, alpha, beta, ply);
    }
    return -_negamax(child, depth, -beta, -alpha, ply);
  }

  int _negamax(GameState s, int depth, int alpha, int beta, int ply) {
    _nodes++;
    if ((_nodes & 1023) == 0) {
      var limit = _reached >= cfg.minDepth ? cfg.timeMs : cfg.timeMs * AiConfig.overtimeFactor;
      // choosing among near-equal moves gets some extra time of its own, so a
      // slow or busy phone still gets to apply the capture / safety rules
      if (_selecting) limit += cfg.timeMs ~/ 2;
      if (_clock.elapsedMilliseconds > limit) throw const _Abort();
    }
    final result = s.result;
    if (result != null) {
      if (result.isDraw) return 0;
      return result.winner == s.turn ? Evaluator.win - ply : -(Evaluator.win - ply);
    }
    if (depth <= 0) {
      return cfg.quiesce ? _quiesce(s, alpha, beta, ply, 2) : Evaluator.evaluate(s, s.turn, cfg);
    }

    final alpha0 = alpha; // bound type is judged against the original window
    final key = Zobrist.hash(s);
    final entry = _tt[key];
    Move? ttMove;
    if (entry != null) {
      ttMove = entry.move;
      if (entry.depth >= depth) {
        switch (entry.bound) {
          case _Bound.exact:
            return entry.score;
          case _Bound.lower:
            if (entry.score >= beta) return entry.score;
            if (entry.score > alpha) alpha = entry.score;
          case _Bound.upper:
            if (entry.score <= alpha) return entry.score;
            if (entry.score < beta) beta = entry.score;
        }
      }
    }

    final moves = _order(Rules.legalMoves(s), s, ttMove, ply);
    final k1 = ply < _maxPly ? _killer1[ply] : null;
    final k2 = ply < _maxPly ? _killer2[ply] : null;
    var best = -_inf;
    Move? bestMove;
    var index = 0;
    for (final m in moves) {
      final child = Rules.apply(s, m);
      int v;
      if (index == 0) {
        v = _childScore(s, child, depth - 1, alpha, beta, ply + 1);
      } else {
        // later moves: a cheap test against the best so far, looked at
        // properly (full depth, then full window) only if they beat it
        var d = depth - 1;
        final reducible = cfg.lateReductions &&
            index >= 3 &&
            depth >= 3 &&
            !m.hasCapture &&
            m != ttMove &&
            m != k1 &&
            m != k2 &&
            !child.isOver;
        if (reducible) d -= (index >= 8 && depth >= 5) ? 2 : 1;
        v = _childScore(s, child, d, alpha, alpha + 1, ply + 1);
        if (v > alpha && d < depth - 1) v = _childScore(s, child, depth - 1, alpha, alpha + 1, ply + 1);
        if (v > alpha && v < beta) v = _childScore(s, child, depth - 1, alpha, beta, ply + 1);
      }
      index++;
      v -= _repeatPenalty(s, child);
      if (v > best) {
        best = v;
        bestMove = m;
      }
      if (v > alpha) alpha = v;
      if (alpha >= beta) {
        if (!m.hasCapture) _rememberCutoff(m, ply, depth);
        break;
      }
    }

    if (_tt.length > _ttLimit) _tt.clear();
    final bound = best <= alpha0 ? _Bound.upper : (best >= beta ? _Bound.lower : _Bound.exact);
    _tt[key] = _Entry(depth, best, bound, bestMove);
    return best;
  }

  /// Captures-only extension so the horizon does not cut a capture sequence
  /// in half. Only runs when the side to move really can complete a line.
  int _quiesce(GameState s, int alpha, int beta, int ply, int qDepth) {
    _nodes++;
    final stand = Evaluator.evaluate(s, s.turn, cfg);
    if (qDepth == 0 || Analysis.threatLines(s, s.turn) == 0) return stand;
    if (stand >= beta) return stand;
    var best = stand;
    if (best > alpha) alpha = best;
    for (final m in Rules.legalMoves(s)) {
      if (!m.hasCapture) continue;
      final child = Rules.apply(s, m);
      int v;
      if (child.isOver) {
        final r = child.result!;
        v = r.isDraw ? 0 : (r.winner == s.turn ? Evaluator.win - ply : -(Evaluator.win - ply));
      } else if (child.turn == s.turn) {
        v = _quiesce(child, alpha, beta, ply + 1, qDepth - 1);
      } else {
        v = -_quiesce(child, -beta, -alpha, ply + 1, qDepth - 1);
      }
      if (v > best) best = v;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    return best;
  }

  /// Hard only: a small malus for walking back into a position that has
  /// already occurred while ahead in material, so it does not drift into a
  /// draw by repetition.
  int _repeatPenalty(GameState parent, GameState child) {
    if (!cfg.avoidRepeat || child.isOver || parent.phase != GamePhase.movement) return 0;
    final me = parent.turn;
    if (parent.totalTokens(me) <= parent.totalTokens(1 - me)) return 0;
    return child.history.count(child.positionKey) >= 2 ? 60 : 0;
  }

  // -------------------------------------------------------------- ordering

  int _hIndex(Move m) => (m.from + 1) * Board.pointCount + m.to;

  void _rememberCutoff(Move m, int ply, int depth) {
    if (ply < _maxPly && _killer1[ply] != m) {
      _killer2[ply] = _killer1[ply];
      _killer1[ply] = m;
    }
    final i = _hIndex(m);
    _history[i] = math.min(_history[i] + depth * depth, 4000);
  }

  /// Best move from the table first, then captures, then this ply's killer
  /// moves, then moves with a good history, then well-connected destinations.
  List<Move> _order(List<Move> moves, GameState s, Move? ttMove, int ply) {
    final k1 = ply < _maxPly ? _killer1[ply] : null;
    final k2 = ply < _maxPly ? _killer2[ply] : null;
    int score(Move m) {
      if (m == ttMove) return 100000;
      var v = _pointRank[m.to];
      if (m.hasCapture) {
        v += 10000;
        // prefer eating a token that is close to a line of its own
        v += _pointRank[m.capture];
      } else {
        if (m == k1) {
          v += 6000;
        } else if (m == k2) {
          v += 5000;
        }
        v += math.min(_history[_hIndex(m)], 4000);
      }
      return v;
    }

    final scored = [for (final m in moves) (score(m), m)];
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final e in scored) e.$2];
  }
}
