import 'bits.dart';
import 'board.dart';
import 'game_state.dart';
import 'move.dart';

/// Order of placement turns.
enum PlacementRule {
  /// Agreed rules: seat 0 opens with two tokens, then turns alternate; seat 0
  /// runs out first, so seat 1 places its last two in a row.
  openingAndClosingDouble,

  /// Both seats open with two tokens, then strict alternation (no closing
  /// double). In 100 Hard-vs-Hard games this gave seat 0 61 wins and seat 1
  /// 35, against 24 and 74 for the agreed rules.
  symmetricOpening,
}

/// Pure rules of Naw Tin: move generation, line completion, protection,
/// captures, turn order and end-of-game detection. No UI, no side effects.
abstract final class Rules {
  /// Which placement order is in force. The agreed rules are the default; the
  /// alternative exists because self-play showed the closing double favours
  /// seat 1 (see `PlacementRule`).
  static PlacementRule placementRule = PlacementRule.openingAndClosingDouble;

  // ---------------------------------------------------------------- lines

  /// Bitmask (16 bits, one per line) of the lines through [point] that are
  /// fully covered by [own].
  static int linesCompletedAt(int own, int point) {
    var m = 0;
    for (final l in Board.linesOfPoint[point]) {
      final lm = Board.lineMasks[l];
      if (own & lm == lm) m |= 1 << l;
    }
    return m;
  }

  /// All lines currently completed by [own], as a 16-bit line mask.
  static int completedLines(int own) {
    var m = 0;
    for (var l = 0; l < Board.lineCount; l++) {
      final lm = Board.lineMasks[l];
      if (own & lm == lm) m |= 1 << l;
    }
    return m;
  }

  /// Tokens of [own] that are protected: those on a currently completed line.
  /// This is recomputed from the board every time, so a token loses
  /// protection the moment it leaves its line, and the fixed tokens of an
  /// open begi/treghi line are correctly unprotected.
  static int protectedMask(int own) {
    var prot = 0;
    for (var l = 0; l < Board.lineCount; l++) {
      final lm = Board.lineMasks[l];
      if (own & lm == lm) prot |= lm;
    }
    return prot;
  }

  // ---------------------------------------------------------- move generation

  /// Placements (placement phase) or one-step slides (movement phase) for
  /// the seat to act, without capture choices.
  static List<Move> stepMoves(GameState s) {
    if (s.isOver) return const [];
    final me = s.turn;
    final moves = <Move>[];
    if (s.handOf(me) > 0) {
      for (final to in bitsOf(s.emptyMask)) {
        moves.add(Move.place(to));
      }
    } else {
      final empty = s.emptyMask;
      for (final from in bitsOf(s.maskOf(me))) {
        for (final to in bitsOf(Board.neighborMasks[from] & empty)) {
          moves.add(Move.slide(from, to));
        }
      }
    }
    return moves;
  }

  /// Every legal move. A step that completes a line is expanded into one move
  /// per legal capture, so each capture choice is its own branch.
  static List<Move> legalMoves(GameState s) {
    final moves = <Move>[];
    for (final step in stepMoves(s)) {
      final targets = captureTargets(s, step);
      if (targets == 0) {
        moves.add(step);
      } else {
        for (final t in bitsOf(targets)) {
          moves.add(step.withCapture(t));
        }
      }
    }
    return moves;
  }

  /// Whether the seat to act (in movement) has at least one slide.
  static bool canSlide(int own, int occupied) {
    for (final from in bitsOf(own)) {
      if (Board.neighborMasks[from] & ~occupied != 0) return true;
    }
    return false;
  }

  // -------------------------------------------------------------- captures

  /// The mover's tokens after [step] (capture ignored).
  static int ownAfterStep(GameState s, Move step) {
    final own = s.maskOf(s.turn);
    return step.isPlacement
        ? own | bit(step.to)
        : (own & ~bit(step.from)) | bit(step.to);
  }

  /// Lines completed by [step] (16-bit line mask); non-zero means MACHYAS.
  static int linesFormedByStep(GameState s, Move step) =>
      linesCompletedAt(ownAfterStep(s, step), step.to);

  /// Opponent tokens that may be eaten after [step]: the unprotected ones, or
  /// all of them when every opponent token is protected. Returns 0 when the
  /// step completes no line (or there is nothing to eat).
  static int captureTargets(GameState s, Move step) {
    if (linesFormedByStep(s, step) == 0) return 0;
    final opp = s.maskOf(1 - s.turn);
    final unprotected = opp & ~protectedMask(opp);
    return unprotected != 0 ? unprotected : opp;
  }

  // ------------------------------------------------------------ legality

  /// Whether [m] is legal in [s] (used by asserts and the controller).
  static bool isLegal(GameState s, Move m) {
    if (s.isOver) return false;
    if (m.to < 0 || m.to >= Board.pointCount) return false;
    if (s.emptyMask & bit(m.to) == 0) return false;
    final me = s.turn;
    if (m.isPlacement) {
      if (s.handOf(me) == 0) return false;
    } else {
      if (s.handOf(me) > 0) return false;
      if (s.maskOf(me) & bit(m.from) == 0) return false;
      if (Board.neighborMasks[m.from] & bit(m.to) == 0) return false;
    }
    final targets = captureTargets(s, m);
    if (targets == 0) return !m.hasCapture;
    return m.hasCapture && targets & bit(m.capture) != 0;
  }

  // ----------------------------------------------------------------- apply

  /// Plays [m] and returns the next position (with `result` set if the game
  /// ended). [m] must be legal; this is asserted in debug builds.
  static GameState apply(GameState s, Move m) {
    assert(!s.isOver, 'Game is already over');
    assert(isLegal(s, m), 'Illegal move $m in $s');

    final me = s.turn;
    final you = 1 - me;
    final mine = ownAfterStep(s, m);
    var theirs = s.maskOf(you);
    final myHand = s.handOf(me) - (m.isPlacement ? 1 : 0);

    final captured = m.hasCapture;
    if (captured) theirs &= ~bit(m.capture);

    final mask0 = me == 0 ? mine : theirs;
    final mask1 = me == 0 ? theirs : mine;
    final hand0 = me == 0 ? myHand : s.hand0;
    final hand1 = me == 0 ? s.hand1 : myHand;

    // The opening turn lets seat 0 place two tokens; otherwise play passes.
    final continuesTurn = m.isPlacement && s.placesLeft > 1;
    var nextTurn = continuesTurn ? me : you;
    var nextPlaces = continuesTurn ? s.placesLeft - 1 : 1;
    // Seat 0 places 2 + 7 tokens while seat 1 places 9 singles, so seat 0 runs
    // dry first. A seat with nothing left to place is skipped until every
    // token is down (seat 1 then places its last two in a row).
    if (hand0 + hand1 > 0 && (nextTurn == 0 ? hand0 : hand1) == 0) {
      nextTurn = 1 - nextTurn;
      nextPlaces = 1;
    }

    if (placementRule == PlacementRule.symmetricOpening &&
        nextTurn == 1 &&
        hand1 == Board.tokensPerPlayer &&
        m.isPlacement) {
      nextPlaces = 2; // seat 1 also opens with two tokens
    }
    final key = GameState.keyOf(mask0, mask1, nextTurn);
    // Placements and captures cannot be undone, so the position run restarts.
    final history = (m.isPlacement || captured)
        ? PositionHistory(key)
        : s.history.add(key);

    GameResult? result;
    final theirTotal = popCount(theirs) + (you == 0 ? hand0 : hand1);
    if (theirTotal <= 2) {
      result = GameResult.win(me, GameEndReason.tokensReduced);
    } else if ((nextTurn == 0 ? hand0 : hand1) == 0 &&
        !canSlide(nextTurn == 0 ? mask0 : mask1, mask0 | mask1)) {
      result = GameResult.win(me, GameEndReason.noLegalMoves);
    } else if (history.count(key) >= 3) {
      result = const GameResult.draw(GameEndReason.repetition);
    }

    return GameState(
      mask0: mask0,
      mask1: mask1,
      hand0: hand0,
      hand1: hand1,
      turn: nextTurn,
      placesLeft: nextPlaces,
      history: history,
      result: result,
    );
  }
}
