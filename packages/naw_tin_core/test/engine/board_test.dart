import 'package:test/test.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

void main() {
  group('Board points', () {
    test('has 24 points and 16 lines', () {
      expect(Board.pointCount, 24);
      expect(Board.lines.length, 16);
      expect(Board.lineMasks.length, 16);
    });

    test('corners and midpoints alternate around each ring', () {
      for (var p = 0; p < 24; p++) {
        expect(Board.isCorner(p), Board.posOf(p).isEven);
        expect(Board.isMidpoint(p), Board.posOf(p).isOdd);
      }
    });

    test('grid coordinates are unique and inside 0..6, centre unused', () {
      final seen = <String>{};
      for (var p = 0; p < 24; p++) {
        final g = Board.gridOf(p);
        expect(g[0], inInclusiveRange(0, 6));
        expect(g[1], inInclusiveRange(0, 6));
        expect(g[0] == 3 && g[1] == 3, isFalse,
            reason: 'centre is not a point');
        expect(seen.add('${g[0]},${g[1]}'), isTrue);
      }
      expect(Board.gridOf(0), [0, 0]);
      expect(Board.gridOf(2), [6, 0]);
      expect(Board.gridOf(9), [3, 1]);
      expect(Board.gridOf(20), [4, 4]);
    });
  });

  group('Board lines', () {
    test('every line has exactly 3 distinct points', () {
      for (final l in Board.lines) {
        expect(l.length, 3);
        expect(l.toSet().length, 3);
        expect(popCount(maskOf(l)), 3);
      }
    });

    test('12 square sides + 4 cross lines', () {
      var sides = 0, cross = 0;
      for (var l = 0; l < 16; l++) {
        Board.isCrossLine(l) ? cross++ : sides++;
      }
      expect(sides, 12);
      expect(cross, 4);
      // square sides stay inside one ring
      for (var l = 0; l < 12; l++) {
        expect(Board.lines[l].map(Board.ringOf).toSet().length, 1);
      }
      // cross lines run outer, middle, inner through a midpoint
      for (var l = 12; l < 16; l++) {
        expect(Board.lines[l].map(Board.ringOf).toList(), [0, 1, 2]);
        expect(Board.lines[l].every(Board.isMidpoint), isTrue);
      }
    });

    test('all 16 lines are distinct', () {
      expect(Board.lineMasks.toSet().length, 16);
    });

    test('every point sits on exactly 2 lines', () {
      for (var p = 0; p < 24; p++) {
        expect(Board.linesOfPoint[p].length, 2, reason: 'point $p');
      }
    });

    test('known lines', () {
      expect(Board.lines[0], [0, 1, 2]); // outer top
      expect(Board.lines[3], [6, 7, 0]); // outer left
      expect(Board.lines[8], [16, 17, 18]); // inner top
      expect(Board.lines[12], [1, 9, 17]); // top cross line
      expect(Board.lines[15], [7, 15, 23]); // left cross line
    });

    test('lineBetween finds the shared line or -1', () {
      expect(Board.lineBetween(0, 1), 0);
      expect(Board.lineBetween(0, 2), 0);
      expect(Board.lineBetween(1, 17), 12);
      expect(Board.lineBetween(0, 4), -1);
      expect(Board.lineBetween(0, 9), -1);
    });
  });

  group('Board adjacency', () {
    test('has 32 edges', () {
      expect(Board.edges.length, 32);
    });

    test('is symmetric', () {
      for (var a = 0; a < 24; a++) {
        for (final b in Board.neighbors[a]) {
          expect(Board.neighborMasks[b] & bit(a), isNot(0));
        }
      }
    });

    test('corners have 2 neighbours, outer/inner midpoints 3, middle midpoints 4',
        () {
      for (var p = 0; p < 24; p++) {
        final expected =
            Board.isCorner(p) ? 2 : (Board.ringOf(p) == 1 ? 4 : 3);
        expect(Board.neighbors[p].length, expected, reason: 'point $p');
      }
    });

    test('adjacent points share a line; the two ends of a line are not adjacent',
        () {
      for (final e in Board.edges) {
        expect(Board.lineBetween(e[0], e[1]), isNot(-1));
      }
      for (final l in Board.lines) {
        expect(Board.neighborMasks[l[0]] & bit(l[2]), 0);
      }
    });

    test('known neighbours', () {
      expect(Board.neighbors[0], [1, 7]);
      expect(Board.neighbors[1], [0, 2, 9]);
      expect(Board.neighbors[9], [1, 8, 10, 17]);
      expect(Board.neighbors[17], [9, 16, 18]);
    });

    test('corners never connect between rings', () {
      for (var p = 0; p < 24; p++) {
        if (!Board.isCorner(p)) continue;
        for (final n in Board.neighbors[p]) {
          expect(Board.ringOf(n), Board.ringOf(p));
        }
      }
    });
  });
}
