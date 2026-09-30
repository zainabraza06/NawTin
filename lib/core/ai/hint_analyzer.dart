import '../engine/engine.dart';

enum HintKind { bothThreaten, opponentThreat, swingForming, yourChance, calm }

/// A warning shown by the first (1 ad) hint: it names the danger but never
/// reveals the move.
final class HintAdvice {
  const HintAdvice(this.kind, this.message);
  final HintKind kind;
  final String message;
}

abstract final class HintAnalyzer {
  /// Warning-only hint for [seat] (the player asking) in [s].
  static HintAdvice warning(GameState s, int seat) {
    final you = 1 - seat;
    final mine = Analysis.threatLines(s, seat) != 0;
    final theirs = Analysis.threatLines(s, you) != 0;

    if (theirs && mine && s.turn == seat) {
      return const HintAdvice(
        HintKind.bothThreaten,
        'Both of you are one move from a line, and it is your turn. Take yours first!',
      );
    }
    if (theirs) {
      return const HintAdvice(
        HintKind.opponentThreat,
        'Careful: your opponent is one move from completing a line.',
      );
    }
    final forming = formingSwing(s, you);
    if (forming != null) {
      return HintAdvice(
        HintKind.swingForming,
        forming.kind == PatternKind.treghi
            ? 'A treghi is forming for your opponent. Block one of its points soon.'
            : 'A begi is forming for your opponent. Block one of its points soon.',
      );
    }
    if (mine) {
      return const HintAdvice(HintKind.yourChance, 'You can make three this turn. Look for the line.');
    }
    return const HintAdvice(
      HintKind.calm,
      'No immediate danger. Build towards two lines at once.',
    );
  }

  /// A begi/treghi that [seat] is one step from arming: either every fixed
  /// token is in place and only the swinging token is missing, or the swinging
  /// token is on a stop and exactly one fixed token is missing. Blocked
  /// patterns (the enemy sits on a fixed point or stop) do not count.
  static SwingPattern? formingSwing(GameState s, int seat) {
    final own = s.maskOf(seat);
    final opp = s.maskOf(1 - seat);
    SwingPattern? found;
    for (final p in SwingPattern.all) {
      if ((opp & (p.fixedMask | p.stopsMask)) != 0) continue;
      if (p.isArmed(own, opp)) continue; // already armed, not "forming"
      final have = popCount(own & p.fixedMask);
      final need = popCount(p.fixedMask);
      final onStop = (own & p.stopsMask) != 0;
      final formingNow = (have == need && !onStop) || (have == need - 1 && onStop);
      if (!formingNow) continue;
      // prefer reporting a treghi over a begi
      if (found == null || p.kind == PatternKind.treghi) found = p;
    }
    return found;
  }
}
