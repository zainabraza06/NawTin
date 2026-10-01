import 'package:test/test.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

void main() {
  group('pattern counts', () {
    test('32 begi + 16 treghi = 48', () {
      expect(SwingPattern.begi.length, 32);
      expect(SwingPattern.treghi.length, 16);
      expect(SwingPattern.all.length, 48);
    });

    test('begi: 24 side swings + 8 cross swings', () {
      expect(SwingPattern.begi.where((p) => !p.crossSwing).length, 24);
      expect(SwingPattern.begi.where((p) => p.crossSwing).length, 8);
    });

    test('treghi: 12 along a square side + 4 along a cross line', () {
      expect(SwingPattern.treghi.where((p) => !p.crossSwing).length, 12);
      expect(SwingPattern.treghi.where((p) => p.crossSwing).length, 4);
    });

    test('all 48 are distinct', () {
      final keys = {
        for (final p in SwingPattern.all)
          '${p.kind.name}:${p.fixedMask}:${p.stopsMask}',
      };
      expect(keys.length, 48);
    });
  });

  group('pattern structure', () {
    test('begi: 4 fixed tokens + 1 swinging, 2 stops', () {
      for (final p in SwingPattern.begi) {
        expect(p.stops.length, 2);
        expect(popCount(p.fixedMask), 4);
        expect(p.tokenCount, 5);
      }
    });

    test('treghi: 6 fixed tokens + 1 swinging, 3 stops', () {
      for (final p in SwingPattern.treghi) {
        expect(p.stops.length, 3);
        expect(popCount(p.fixedMask), 6);
        expect(p.tokenCount, 7);
      }
    });

    test('stops are consecutive neighbours along the travel line', () {
      for (final p in SwingPattern.all) {
        for (var i = 0; i < p.stops.length - 1; i++) {
          expect(Board.neighborMasks[p.stops[i]] & bit(p.stops[i + 1]),
              isNot(0));
          expect(Board.lineBetween(p.stops[i], p.stops[i + 1]), p.travelLine);
        }
      }
    });

    test('completed lines are parallel (disjoint) and never the travel line',
        () {
      for (final p in SwingPattern.all) {
        var union = 0;
        for (final l in p.stopLines) {
          expect(l, isNot(p.travelLine));
          expect(union & Board.lineMasks[l], 0, reason: '$p');
          union |= Board.lineMasks[l];
        }
      }
    });

    test('each stop line = its stop + two fixed tokens', () {
      for (final p in SwingPattern.all) {
        for (var i = 0; i < p.stops.length; i++) {
          final line = Board.lineMasks[p.stopLines[i]];
          expect(line & bit(p.stops[i]), isNot(0));
          expect(popCount(line & p.fixedMask), 2);
        }
        expect(p.fixedMask & p.stopsMask, 0);
      }
    });

    test('a cross-line begi swings between neighbouring rings', () {
      for (final p in SwingPattern.begi.where((p) => p.crossSwing)) {
        expect(Board.isCrossLine(p.travelLine), isTrue);
        expect(Board.isMidpoint(p.stops[0]) && Board.isMidpoint(p.stops[1]),
            isTrue);
      }
    });

    test('a side-swing begi runs corner <-> adjacent midpoint of one square',
        () {
      for (final p in SwingPattern.begi.where((p) => !p.crossSwing)) {
        expect(Board.ringOf(p.stops[0]), Board.ringOf(p.stops[1]));
        expect(
            Board.isCorner(p.stops[0]) != Board.isCorner(p.stops[1]), isTrue);
      }
    });

    test('treghi along a side runs corner, midpoint, corner', () {
      for (final p in SwingPattern.treghi.where((p) => !p.crossSwing)) {
        expect(Board.isCorner(p.stops[0]), isTrue);
        expect(Board.isMidpoint(p.stops[1]), isTrue);
        expect(Board.isCorner(p.stops[2]), isTrue);
      }
    });

    test('treghi along a cross line runs outer, middle, inner midpoint', () {
      for (final p in SwingPattern.treghi.where((p) => p.crossSwing)) {
        expect(p.stops.map(Board.ringOf).toList(), [0, 1, 2]);
      }
    });

    test('any two neighbouring stops of a treghi form a begi', () {
      for (final t in SwingPattern.treghi) {
        for (var i = 0; i < 2; i++) {
          final a = t.stops[i], b = t.stops[i + 1];
          final match =
              SwingPattern.begi.where((g) => g.stopsMask == (bit(a) | bit(b)));
          expect(match.length, 1);
          final g = match.single;
          expect(g.fixedMask & ~t.fixedMask, 0,
              reason: 'begi fixed tokens lie within the treghi');
          expect(g.crossSwing, t.crossSwing);
        }
      }
    });

    test('known begi: outer corner 0 <-> midpoint 1', () {
      final p =
          SwingPattern.begi.singleWhere((p) => p.stopsMask == maskOf([0, 1]));
      expect(bitsOf(p.fixedMask).toList(), [6, 7, 9, 17]);
      expect(p.stopLines, [3, 12]); // left side, top cross line
    });

    test('known cross begi: 1 <-> 9', () {
      final p =
          SwingPattern.begi.singleWhere((p) => p.stopsMask == maskOf([1, 9]));
      expect(p.crossSwing, isTrue);
      expect(bitsOf(p.fixedMask).toList(), [0, 2, 8, 10]);
    });

    test('known treghi: outer top side 0-1-2', () {
      final p = SwingPattern.treghi.singleWhere((p) => p.travelLine == 0);
      expect(bitsOf(p.fixedMask).toList(), [3, 4, 6, 7, 9, 17]);
    });

    test('known treghi: top cross line 1-9-17', () {
      final p = SwingPattern.treghi.singleWhere((p) => p.travelLine == 12);
      expect(bitsOf(p.fixedMask).toList(), [0, 2, 8, 10, 16, 18]);
    });
  });

  group('isArmed', () {
    final begi01 =
        SwingPattern.begi.singleWhere((p) => p.stopsMask == maskOf([0, 1]));

    test('armed with the token on either stop', () {
      expect(begi01.isArmed(maskOf([6, 7, 9, 17, 0]), 0), isTrue);
      expect(begi01.isArmed(maskOf([6, 7, 9, 17, 1]), 0), isTrue);
    });

    test('not armed when a fixed token is missing', () {
      expect(begi01.isArmed(maskOf([6, 7, 9, 0]), 0), isFalse);
    });

    test('not armed when the token is on neither stop', () {
      expect(begi01.isArmed(maskOf([6, 7, 9, 17, 12]), 0), isFalse);
    });

    test('not armed when the other stop is blocked by the opponent', () {
      expect(begi01.isArmed(maskOf([6, 7, 9, 17, 0]), maskOf([1])), isFalse);
      expect(begi01.isArmed(maskOf([6, 7, 9, 17, 1]), maskOf([0])), isFalse);
    });

    test('not armed when both stops hold own tokens', () {
      expect(begi01.isArmed(maskOf([6, 7, 9, 17, 0, 1]), 0), isFalse);
    });

    test('treghi armed with the token on any of the three stops', () {
      final t = SwingPattern.treghi.singleWhere((p) => p.travelLine == 0);
      final fixed = maskOf([3, 4, 6, 7, 9, 17]);
      for (final s in [0, 1, 2]) {
        expect(t.isArmed(fixed | bit(s), 0), isTrue);
      }
      expect(t.isArmed(fixed | bit(0), bit(2)), isFalse);
    });

    test('a full treghi with the token on a corner also arms one sub-begi', () {
      final armed = SwingPattern.armed(maskOf([3, 4, 6, 7, 9, 17, 0]), 0);
      expect(armed.where((p) => p.kind == PatternKind.treghi).length, 1);
      expect(armed.where((p) => p.kind == PatternKind.begi).length, 1);
    });
  });
}
