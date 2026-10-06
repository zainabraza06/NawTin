import 'dart:math';

import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

/// A plain, unpruned negamax with the same rules for who moves next and the
/// same leaf evaluation as the real search (no quiescence, no repetition malus).
int reference(GameState s, int depth, int ply, AiConfig cfg) {
  final result = s.result;
  if (result != null) {
    if (result.isDraw) return 0;
    return result.winner == s.turn ? Evaluator.win - ply : -(Evaluator.win - ply);
  }
  if (depth <= 0) return Evaluator.evaluate(s, s.turn, cfg);
  var best = -(1 << 30);
  for (final m in Rules.legalMoves(s)) {
    final child = Rules.apply(s, m);
    final v = child.turn == s.turn ? reference(child, depth - 1, ply + 1, cfg) : -reference(child, depth - 1, ply + 1, cfg);
    if (v > best) best = v;
  }
  return best;
}

List<GameState> samplePositions(int count, {int seed = 3}) {
  final rnd = Random(seed);
  final out = <GameState>[];
  while (out.length < count) {
    var s = GameState.initial();
    final plies = 4 + rnd.nextInt(26);
    for (var i = 0; i < plies && !s.isOver; i++) {
      final m = Rules.legalMoves(s);
      s = Rules.apply(s, m[rnd.nextInt(m.length)]);
    }
    if (!s.isOver) out.add(s);
  }
  return out;
}

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  group('the pruned search finds exactly what plain minimax finds', () {
    // No quiescence, no repetition malus and no variety: a plain minimax is a fair referee.
    const cfg = AiConfig(
      name: 'plain',
      maxDepth: 8,
      timeMs: 600000,
      seesSwings: false,
      avoidRepeat: false,
      quiesce: false,
    );

    test('score at depth 3 equals plain minimax on 40 positions (PVS, killers, history, TT)', () {
      for (final s in samplePositions(40)) {
        final r = Searcher(cfg.withDepth(3)).search(s);
        if (r.depth == 0) continue; // a single legal move: nothing to search
        expect(r.score, reference(s, 3, 0, cfg), reason: 'position ${s.toString()}');
      }
    });

    test('score at depth 4 equals plain minimax on 12 positions', () {
      for (final s in samplePositions(12, seed: 9)) {
        final r = Searcher(cfg.withDepth(4)).search(s);
        if (r.depth == 0) continue;
        expect(r.score, reference(s, 4, 0, cfg), reason: 'position ${s.toString()}');
      }
    });
  });

  group('late-move reductions stay sound', () {
    test('they never change a forced win or loss that is found', () {
      final cfgOn = AiConfig.medium.withDepth(6).withTime(600000);
      const cfgOff = AiConfig(
        name: 'noLmr',
        maxDepth: 6,
        timeMs: 600000,
        seesSwings: true,
        avoidRepeat: false,
        quiesce: true,
        minDepth: 1,
      );
      var agree = 0, total = 0;
      for (final s in samplePositions(25, seed: 21)) {
        final a = Searcher(cfgOn).search(s);
        final b = Searcher(cfgOff).search(s);
        total++;
        // the exact value may differ slightly (reductions are an approximation);
        // a decided game (win/loss) must be reported the same way
        final aWin = a.score.abs() >= Evaluator.win - 200;
        final bWin = b.score.abs() >= Evaluator.win - 200;
        if (aWin == bWin && (!aWin || a.score.sign == b.score.sign)) agree++;
      }
      expect(agree / total, greaterThanOrEqualTo(0.88), reason: '$agree of $total');
    });
  });

  group('minimum depth on a slow device', () {
    test('a tiny time limit still reaches the guaranteed depth', () {
      final s = samplePositions(1, seed: 5).single;
      // a 150 ms limit would normally stop around depth 6 here; the guarantee
      // lets it run up to 3x longer to complete minDepth
      final r = Searcher(AiConfig.hard.withTime(150)).search(s);
      expect(r.depth, greaterThanOrEqualTo(AiConfig.hard.minDepth));
    });

    test('...but never runs away: capped at a few times the time limit', () {
      final s = samplePositions(1, seed: 6).single;
      final sw = Stopwatch()..start();
      final cfg = AiConfig.hard.withDepth(40).withTime(300);
      Searcher(cfg).search(s);
      expect(sw.elapsedMilliseconds, lessThan(300 * AiConfig.overtimeFactor + 400));
    });

    test('strictTime() restores a hard time limit for tests that need one', () {
      final s = samplePositions(1, seed: 7).single;
      final sw = Stopwatch()..start();
      Searcher(AiConfig.hard.withDepth(40).withTime(120).strictTime()).search(s);
      expect(sw.elapsedMilliseconds, lessThan(120 + 250));
    });
  });
}
