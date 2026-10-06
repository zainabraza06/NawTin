import 'dart:math';

import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  // depth-limited so the result does not depend on machine speed
  // variety only: the capture / safety preferences are tested separately below
  AiConfig cfg(int margin) => AiConfig.medium
      .withDepth(4)
      .withTime(600000)
      .strictTime()
      .withVariety(margin)
      .withCapturePreference(0)
      .withSafetyPreference(0);

  GameState afterRandom(int seed, int plies) {
    final rnd = Random(seed);
    var s = GameState.initial();
    for (var i = 0; i < plies && !s.isOver; i++) {
      final m = Rules.legalMoves(s);
      s = Rules.apply(s, m[rnd.nextInt(m.length)]);
    }
    return s;
  }

  test('with no variety the AI always plays the same move', () {
    final s = afterRandom(3, 8);
    final first = Searcher(cfg(0)).search(s).move;
    for (var i = 0; i < 6; i++) {
      expect(Searcher(cfg(0)).search(s).move, first);
    }
  });

  test('with variety it plays different (but equally good) moves in the same position', () {
    final s = GameState.initial(); // the opening: many placements are about equal
    final seen = <Move>{};
    for (var i = 0; i < 40; i++) {
      seen.add(Searcher(cfg(40), random: Random(i)).search(s).move);
    }
    expect(seen.length, greaterThan(2), reason: 'got only $seen');
  });

  test('every move it may pick is within the margin of the best (never a blunder)', () {
    const margin = 25;
    for (final seed in [1, 2, 3, 4]) {
      final s = afterRandom(seed, 12 + seed * 2);
      if (s.isOver) continue;
      final exact = cfg(0);
      final best = Searcher(exact).search(s);
      if (best.depth == 0) continue; // a single legal move
      for (var i = 0; i < 12; i++) {
        final m = Searcher(cfg(margin), random: Random(100 * seed + i)).search(s).move;
        final child = Rules.apply(s, m);
        final v = child.turn == s.turn
            ? Searcher(exact).valueOf(child, 3)
            : -Searcher(exact).valueOf(child, 3);
        expect(v, greaterThanOrEqualTo(best.score - margin - 1), reason: 'seed $seed picked $m worth $v, best ${best.score}');
      }
    }
  });

  test('a winning or losing line is never traded away for variety', () {
    // seat 1 is down to three loose tokens: eating one wins at once
    final s = GameState.fromMasks(
      mask0: maskOf([0, 1, 3, 5]),
      mask1: maskOf([12, 14, 20]),
      hand0: 0,
      hand1: 0,
      turn: 0,
      placesLeft: 1,
    );
    for (var i = 0; i < 15; i++) {
      final r = Searcher(cfg(500), random: Random(i)).search(s);
      expect(Rules.apply(s, r.move).isOver, isTrue, reason: 'must take the win, got ${r.move}');
    }
  });

  group('judging nearly-equal moves on principle, not by search-depth noise', () {
    AiConfig atDepth(int d) => AiConfig.easy.withDepth(d).withTime(600000).strictTime().withVariety(0);

    test('it takes an available capture at every search depth', () {
      // seat 0 can complete 0-1-2 at once (and eat); a deeper search may rate a quiet block slightly higher
      final s = GameState.fromMasks(mask0: maskOf([0, 1]), mask1: maskOf([20, 22]), hand0: 5, hand1: 5, turn: 0, placesLeft: 1);
      for (final d in [4, 5, 6, 7, 8]) {
        final m = Searcher(atDepth(d)).search(s).move;
        expect(m.hasCapture, isTrue, reason: 'depth $d played $m');
      }
    });

    test('it blocks a one-move threat at the search depths that used to ignore it', () {
      // seat 1 threatens 0-1-2; seat 0 must put a token on 2
      final s = GameState.fromMasks(mask0: maskOf([12, 23]), mask1: maskOf([0, 1]), hand0: 5, hand1: 5, turn: 0, placesLeft: 1);
      for (final d in [3, 4, 5, 7, 8, 9]) {
        expect(Searcher(atDepth(d)).search(s).move.to, 2, reason: 'depth $d');
      }
    });

    test('with the preferences off the same position is decided by raw values (they exist for a reason)', () {
      final s = GameState.fromMasks(mask0: maskOf([12, 23]), mask1: maskOf([0, 1]), hand0: 5, hand1: 5, turn: 0, placesLeft: 1);
      final raw = atDepth(8).withCapturePreference(0).withSafetyPreference(0);
      final tos = {for (final d in [6, 8]) Searcher(raw.withDepth(d)).search(s).move.to};
      expect(tos.contains(2), isFalse, reason: 'if raw search blocked at both depths these preferences would be unnecessary: $tos');
    });
  });
}
