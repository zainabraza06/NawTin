import '../engine/engine.dart';
import 'ai_config.dart';
import 'eval_weights.dart';

/// Static evaluation of a position, from the point of view of one seat.
///
/// Terms (each weighted by phase: placement, movement, endgame):
///  * material: tokens on the board plus unplaced
///  * completed lines and protected tokens
///  * threats (a line completable next turn) and double threats
///  * mobility and blocked tokens (movement)
///  * begi/treghi potential (Medium/Hard only)
///  * point connectivity: middle midpoints have 4 neighbours, outer/inner
///    midpoints 3, corners 2
///  * exposure: my open-line tokens are unprotected, so an enemy threat
///    against a set-up begi/treghi is punished
abstract final class Evaluator {
  /// Score above which a position counts as decided.
  static const int win = 100000;

  static final List<int> _conn = List.unmodifiable([
    for (var p = 0; p < Board.pointCount; p++) Board.neighbors[p].length,
  ]);

  static int evaluate(GameState s, int me, AiConfig cfg) {
    final you = 1 - me;
    final mine = s.maskOf(me), theirs = s.maskOf(you);
    final occupied = mine | theirs;
    final myTotal = s.totalTokens(me), theirTotal = s.totalTokens(you);
    final placement = s.phase == GamePhase.placement;
    final endgame = myTotal <= 4 || theirTotal <= 4;

    // phase weights
    final w = cfg.weights;
    var wMaterial = w.material, wLine = w.line, wProtect = w.protect, wThreat = w.threat, wDouble = w.doubleThreat;
    var wMobility = 0, wBlocked = 0, wConn = w.conn, wSwing = w.swing;
    final wExposure = w.exposure;
    if (placement) {
      wConn = w.connPlace;
      wThreat = w.threatPlace;
      wSwing = w.swingPlace;
    } else {
      wMobility = w.mobilityMove;
      wBlocked = w.blockedMove;
    }
    if (endgame) {
      wMaterial = w.materialEnd;
      wMobility = w.mobilityEnd;
      wBlocked = w.blockedEnd;
      wConn = w.connEnd;
      wSwing = w.swingEnd;
    }

    var score = wMaterial * (myTotal - theirTotal);

    // lines and protection
    final myLines = Rules.completedLines(mine);
    final theirLines = Rules.completedLines(theirs);
    score += wLine * (popCount(myLines) - popCount(theirLines));
    score += wProtect *
        (popCount(Rules.protectedMask(mine)) -
            popCount(Rules.protectedMask(theirs)));

    // threats: the side to move cashes a threat immediately, so it is worth more
    final myThreat = popCount(Analysis.threatLines(s, me));
    final theirThreat = popCount(Analysis.threatLines(s, you));
    final myTempo = s.turn == me ? 3 : 2, theirTempo = s.turn == you ? 3 : 2;
    score += wThreat * (myThreat * myTempo - theirThreat * theirTempo) ~/ 2;
    if (myThreat >= 2) score += wDouble * (s.turn == me ? 2 : 1);
    if (theirThreat >= 2) score -= wDouble * (s.turn == you ? 2 : 1);

    // mobility and blocked tokens
    if (wMobility > 0) {
      final empty = Board.fullMask & ~occupied;
      var myMoves = 0, theirMoves = 0, myBlocked = 0, theirBlocked = 0;
      for (final p in bitsOf(mine)) {
        final n = popCount(Board.neighborMasks[p] & empty);
        myMoves += n;
        if (n == 0) myBlocked++;
      }
      for (final p in bitsOf(theirs)) {
        final n = popCount(Board.neighborMasks[p] & empty);
        theirMoves += n;
        if (n == 0) theirBlocked++;
      }
      score += wMobility * (myMoves - theirMoves);
      score += wBlocked * (theirBlocked - myBlocked);
    }

    // connectivity of occupied points
    var myConn = 0, theirConn = 0;
    for (final p in bitsOf(mine)) {
      myConn += _conn[p];
    }
    for (final p in bitsOf(theirs)) {
      theirConn += _conn[p];
    }
    score += wConn * (myConn - theirConn);

    if (cfg.seesSwings) {
      score += wSwing *
          (_swingPotential(mine, theirs, w) - _swingPotential(theirs, mine, w)) ~/ 20;

      // an armed setup whose fixed tokens the enemy is about to eat
      if (theirThreat > 0 && SwingPattern.armed(mine, theirs).isNotEmpty) {
        score -= wExposure * 2;
      }
      if (myThreat > 0 && SwingPattern.armed(theirs, mine).isNotEmpty) {
        score += wExposure * 2;
      }
    }
    return score;
  }

  /// Progress towards begi/treghi: squared count of fixed tokens in place for
  /// every pattern the enemy has not blocked, a bonus for a swinging token on
  /// a stop, and a big bonus when the setup is armed and ready to swing.
  static int _swingPotential(int own, int opp, EvalWeights w) {
    var total = 0;
    final pats = SwingPattern.all;
    for (var i = 0; i < pats.length; i++) {
      final p = pats[i];
      final fixed = p.fixedMask;
      final held = own & fixed;
      if ((held & (held - 1)) == 0) continue; // fewer than two fixed tokens: never matters
      final have = popCount(held);
      if (have < _need[i] - 2) continue; // too far away to matter yet
      if ((opp & (fixed | p.stopsMask)) != 0) continue; // the enemy blocks it
      final isTreghi = _isTreghi[i];
      final onStop = (own & p.stopsMask) != 0 ? 1 : 0;
      if (have == _need[i] && onStop == 1) {
        total += isTreghi ? w.armedTreghi : w.armedBegi; // armed
      } else {
        total += have * have * (isTreghi ? w.progTreghi : w.progBegi) + onStop * w.onStop;
      }
    }
    return total;
  }

  // per-pattern constants, computed once (same order as SwingPattern.all)
  static final List<int> _need = [for (final p in SwingPattern.all) popCount(p.fixedMask)];
  static final List<bool> _isTreghi = [for (final p in SwingPattern.all) p.kind == PatternKind.treghi];
}
