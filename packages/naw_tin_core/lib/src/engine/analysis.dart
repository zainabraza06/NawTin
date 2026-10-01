import 'bits.dart';
import 'board.dart';
import 'game_state.dart';
import 'patterns.dart';

/// Read-only position analysis shared by the Phutas button, hints and the AI.
abstract final class Analysis {
  /// Lines (16-bit line mask) that [seat] could complete on its next turn:
  ///  * placement: two own tokens, an empty third point, a token left to place
  ///  * movement: the same, and an own token OFF that line is adjacent to the
  ///    empty point (a token already on the line would only break it).
  static int threatLines(GameState s, int seat) {
    final own = s.maskOf(seat);
    final opp = s.maskOf(1 - seat);
    final placing = s.handOf(seat) > 0;
    var threats = 0;
    for (var l = 0; l < Board.lineCount; l++) {
      final lm = Board.lineMasks[l];
      if (popCount(own & lm) != 2) continue;
      final gap = lm & ~own;
      if (gap & opp != 0) continue; // third point is taken by the opponent
      if (placing) {
        threats |= 1 << l;
      } else {
        final gapPoint = gap.bitLength - 1;
        if (Board.neighborMasks[gapPoint] & own & ~lm != 0) threats |= 1 << l;
      }
    }
    return threats;
  }

  /// Line mask of every line a begi/treghi in [armed] completes at one of its
  /// stops. These are swing lines, never a Phutas.
  static int swingLines(Iterable<SwingPattern> armed) {
    var m = 0;
    for (final p in armed) {
      for (final l in p.stopLines) {
        m |= 1 << l;
      }
    }
    return m;
  }
}
