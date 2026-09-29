import 'bits.dart';

/// Static topology of the Naw Tin board.
///
/// Point numbering: `index = ring * 8 + pos`
///  * ring 0 = outer square, 1 = middle square, 2 = inner square
///  * pos runs clockwise from the top-left corner:
///
/// ```
///   0 ---- 1 ---- 2
///   |             |
///   7             3
///   |             |
///   6 ---- 5 ---- 4
/// ```
/// Even `pos` = corner, odd `pos` = side midpoint. The centre is not a point.
///
/// Line numbering (16 lines of 3 points, each listed in travel order):
///  * 0..11  square sides: `ring * 4 + k`, k = 0 top, 1 right, 2 bottom, 3 left
///  * 12..15 cross lines through the side midpoints: 12 top, 13 right,
///    14 bottom, 15 left (outer, middle, inner midpoint)
abstract final class Board {
  static const int pointCount = 24;
  static const int lineCount = 16;
  static const int tokensPerPlayer = 9;
  static const int fullMask = 0xFFFFFF;
  static const int firstCrossLine = 12;

  static int point(int ring, int pos) => ring * 8 + pos;
  static int ringOf(int p) => p >> 3;
  static int posOf(int p) => p & 7;
  static bool isCorner(int p) => (p & 1) == 0;
  static bool isMidpoint(int p) => (p & 1) == 1;
  static bool isCrossLine(int line) => line >= firstCrossLine;

  /// The 16 lines as point triples, in travel order.
  static final List<List<int>> lines = List.unmodifiable(_buildLines());

  /// Bitmask of each line.
  static final List<int> lineMasks =
      List.unmodifiable([for (final l in lines) maskOf(l)]);

  /// The two lines each point sits on (always exactly 2).
  static final List<List<int>> linesOfPoint = List.unmodifiable([
    for (var p = 0; p < pointCount; p++)
      List<int>.unmodifiable([
        for (var l = 0; l < lineCount; l++)
          if (lineMasks[l] & bit(p) != 0) l,
      ]),
  ]);

  /// Adjacent points as a bitmask, per point. Two points are adjacent when
  /// they are neighbours on a drawn line (tokens only slide along lines).
  static final List<int> neighborMasks = List.unmodifiable(_buildNeighbors());

  /// Adjacent points as lists, per point.
  static final List<List<int>> neighbors = List.unmodifiable([
    for (final m in neighborMasks) List<int>.unmodifiable(bitsOf(m)),
  ]);

  /// All 32 undirected edges as `[a, b]` with `a < b`.
  static final List<List<int>> edges = List.unmodifiable([
    for (var a = 0; a < pointCount; a++)
      for (final b in neighbors[a])
        if (a < b) List<int>.unmodifiable([a, b]),
  ]);

  /// Index of the line containing both [a] and [b], or -1.
  static int lineBetween(int a, int b) {
    for (final l in linesOfPoint[a]) {
      if (lineMasks[l] & bit(b) != 0) return l;
    }
    return -1;
  }

  /// Layout coordinates on a 7x7 grid (0..6) for drawing: outer square spans
  /// 0..6, middle 1..5, inner 2..4. Returns `[x, y]`.
  static List<int> gridOf(int p) {
    final ring = ringOf(p);
    final o = ring; // square origin
    final s = 6 - 2 * ring; // side length
    final h = s ~/ 2; // half side, to the midpoint
    const dx = [0, 1, 2, 2, 2, 1, 0, 0]; // in units of h (0, 1 or 2)
    const dy = [0, 0, 0, 1, 2, 2, 2, 1];
    final q = posOf(p);
    return [o + dx[q] * h, o + dy[q] * h];
  }

  static List<List<int>> _buildLines() {
    final result = <List<int>>[];
    for (var ring = 0; ring < 3; ring++) {
      for (var k = 0; k < 4; k++) {
        result.add(List.unmodifiable([
          point(ring, 2 * k),
          point(ring, 2 * k + 1),
          point(ring, (2 * k + 2) % 8),
        ]));
      }
    }
    for (var k = 0; k < 4; k++) {
      final pos = 2 * k + 1;
      result.add(List.unmodifiable([pos, 8 + pos, 16 + pos]));
    }
    return result;
  }

  static List<int> _buildNeighbors() {
    final m = List<int>.filled(pointCount, 0);
    for (final l in lines) {
      // consecutive points on a line are adjacent; the two ends are not
      for (var i = 0; i < 2; i++) {
        m[l[i]] |= bit(l[i + 1]);
        m[l[i + 1]] |= bit(l[i]);
      }
    }
    return m;
  }
}
