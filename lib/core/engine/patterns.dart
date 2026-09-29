import 'bits.dart';
import 'board.dart';

enum PatternKind { begi, treghi }

/// One BEGI (double mill) or TREGHI (triple mill) setup.
///
/// A swinging token walks back and forth over [stops] (2 for begi, 3 for
/// treghi). At every stop it completes a different line ([stopLines]); those
/// lines are all parallel because the swing is perpendicular to each of them.
/// The other two points of every one of those lines must already hold the
/// player's tokens: that is [fixedMask] (4 tokens for begi, 6 for treghi).
///
/// Generation (nothing is hand-listed, so the counts are a real check):
///  * begi   - one per board edge (a, b). The swing runs along the edge; the
///             completed lines are "the other line" of a and of b. 32 edges
///             -> 32 begi (24 side swings, 8 cross swings).
///  * treghi - one per line (p0, p1, p2). The swing runs along the line; the
///             completed lines are the other line of each of its 3 points.
///             16 lines -> 16 treghi (12 along a square side, 4 along a cross
///             line).
final class SwingPattern {
  const SwingPattern._({
    required this.kind,
    required this.crossSwing,
    required this.travelLine,
    required this.stops,
    required this.stopLines,
    required this.fixedMask,
    required this.stopsMask,
  });

  final PatternKind kind;

  /// True when the swing runs along a cross line (between rings), false when
  /// it runs along a square side.
  final bool crossSwing;

  /// The line the swinging token travels along (for a begi: the line that
  /// contains both stops).
  final int travelLine;

  /// The points the token visits, in order (2 for begi, 3 for treghi).
  final List<int> stops;

  /// The line completed at each stop (same order as [stops]).
  final List<int> stopLines;

  /// Points that must already hold the player's tokens.
  final int fixedMask;

  /// Bitmask of [stops].
  final int stopsMask;

  int get tokenCount => popCount(fixedMask) + 1;

  /// Whether this setup is ready for [own] right now: every fixed token is in
  /// place, the swinging token sits on exactly one stop, and every other stop
  /// is empty (so the token is free to swing there).
  bool isArmed(int own, int opp) {
    if ((own & fixedMask) != fixedMask) return false;
    final atStop = own & stopsMask;
    // exactly one bit set: non-zero and a power of two
    if (atStop == 0 || (atStop & (atStop - 1)) != 0) return false;
    final otherStops = stopsMask & ~atStop;
    return (otherStops & (own | opp)) == 0;
  }

  @override
  String toString() =>
      '${kind.name}(stops: $stops, fixed: ${bitsOf(fixedMask).toList()})';

  static SwingPattern _make(
    PatternKind kind,
    int travelLine,
    List<int> stops,
    bool cross,
  ) {
    final stopLines = <int>[];
    for (final p in stops) {
      // "the other line" through this stop
      stopLines.add(Board.linesOfPoint[p].firstWhere((l) => l != travelLine));
    }
    var union = 0;
    for (final l in stopLines) {
      final m = Board.lineMasks[l];
      if (union & m != 0) {
        throw StateError('Stop lines of $stops are not parallel');
      }
      union |= m;
    }
    final stopsMask = maskOf(stops);
    return SwingPattern._(
      kind: kind,
      crossSwing: cross,
      travelLine: travelLine,
      stops: List.unmodifiable(stops),
      stopLines: List.unmodifiable(stopLines),
      fixedMask: union & ~stopsMask,
      stopsMask: stopsMask,
    );
  }

  static List<SwingPattern> _buildBegi() => [
        for (final e in Board.edges)
          _make(
            PatternKind.begi,
            Board.lineBetween(e[0], e[1]),
            [e[0], e[1]],
            Board.ringOf(e[0]) != Board.ringOf(e[1]),
          ),
      ];

  static List<SwingPattern> _buildTreghi() => [
        for (var l = 0; l < Board.lineCount; l++)
          _make(PatternKind.treghi, l, Board.lines[l], Board.isCrossLine(l)),
      ];

  /// The 32 begi setups.
  static final List<SwingPattern> begi = List.unmodifiable(_buildBegi());

  /// The 16 treghi setups.
  static final List<SwingPattern> treghi = List.unmodifiable(_buildTreghi());

  /// All 48 setups, begi first.
  static final List<SwingPattern> all =
      List.unmodifiable([...begi, ...treghi]);

  /// Setups armed for [own] (with [opp] as the other player's tokens).
  static List<SwingPattern> armed(int own, int opp) => [
        for (final p in all)
          if (p.isArmed(own, opp)) p,
      ];
}
