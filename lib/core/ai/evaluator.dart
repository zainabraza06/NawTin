import '../engine/engine.dart';
import 'ai_config.dart';

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
    var wMaterial = 100, wLine = 8, wProtect = 4, wThreat = 16, wDouble = 30;
    var wMobility = 0, wBlocked = 0, wConn = 2, wSwing = 10, wExposure = 14;
    if (placement) {
      wConn = 4;
      wThreat = 20;
      wSwing = 14;
    } else {
      wMobility = 4;
      wBlocked = 5;
    }
    if (endgame) {
      wMaterial = 160;
      wMobility = 7;
      wBlocked = 8;
      wConn = 1;
      wSwing = 5;
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
          (_swingPotential(mine, theirs) - _swingPotential(theirs, mine)) ~/ 20;

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
  static int _swingPotential(int own, int opp) {
    var total = 0;
    for (final p in SwingPattern.all) {
      if ((opp & (p.fixedMask | p.stopsMask)) != 0) continue;
      final have = popCount(own & p.fixedMask);
      final need = popCount(p.fixedMask);
      if (have < need - 2) continue; // too far away to matter yet
      final isTreghi = p.kind == PatternKind.treghi;
      final onStop = (own & p.stopsMask) != 0 ? 1 : 0;
      if (have == need && onStop == 1) {
        total += isTreghi ? 260 : 120; // armed
      } else {
        total += have * have * (isTreghi ? 5 : 8) + onStop * 12;
      }
    }
    return total;
  }
}
