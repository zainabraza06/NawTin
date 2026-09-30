import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/ai/ai.dart';
import 'package:nawtin/core/engine/engine.dart';

GameState st(
  List<int> a,
  List<int> b, {
  int hand0 = 0,
  int hand1 = 0,
  int turn = 0,
  int placesLeft = 1,
}) =>
    GameState.fromMasks(
      mask0: maskOf(a),
      mask1: maskOf(b),
      hand0: hand0,
      hand1: hand1,
      turn: turn,
      placesLeft: placesLeft,
    );

SearchResult find(GameState s, AiConfig c) => Searcher(c).search(s);

void main() {
  group('Zobrist', () {
    test('a transposition hashes the same, different positions do not', () {
      final a = Rules.apply(Rules.apply(GameState.initial(), const Move.place(0)), const Move.place(4));
      // same two tokens for seat 0 reached in the other order
      final b = Rules.apply(Rules.apply(GameState.initial(), const Move.place(4)), const Move.place(0));
      expect(Zobrist.hash(a), Zobrist.hash(b));
      final c = Rules.apply(Rules.apply(GameState.initial(), const Move.place(0)), const Move.place(5));
      expect(Zobrist.hash(a), isNot(Zobrist.hash(c)));
    });

    test('side to move and hand sizes are part of the hash', () {
      final x = st([0, 6], [20, 22], hand0: 3, hand1: 3, turn: 0);
      final y = st([0, 6], [20, 22], hand0: 3, hand1: 3, turn: 1);
      final z = st([0, 6], [20, 22], hand0: 2, hand1: 3, turn: 0);
      expect(Zobrist.hash(x), isNot(Zobrist.hash(y)));
      expect(Zobrist.hash(x), isNot(Zobrist.hash(z)));
    });
  });

  group('tactics', () {
    test('Easy completes a line when it can', () {
      final s = st([0, 1], [20, 22], hand0: 5, hand1: 5);
      final r = find(s, AiConfig.easy);
      expect(r.move.to, 2);
      expect(r.move.hasCapture, isTrue);
    });

    test('Easy blocks a one-move threat', () {
      // seat 1 has 0 and 1; seat 0 must take 2
      final s = st([12, 23], [0, 1], hand0: 5, hand1: 5);
      expect(find(s, AiConfig.easy).move.to, 2);
    });

    test('a capture prefers a loose token over a protected one', () {
      // seat 1 owns the finished line 12-13-14 plus loose 20
      final s = st([0, 1, 3, 5], [12, 13, 14, 20]);
      final m = find(s, AiConfig.easy).move;
      expect(m, const Move.slide(3, 2, capture: 20));
    });

    test('takes a winning capture', () {
      // seat 1 is down to three loose tokens; eating one wins
      final s = st([0, 1, 3, 5], [12, 14, 20]);
      final r = find(s, AiConfig.easy);
      expect(r.move.to, 2);
      expect(r.score, greaterThan(Evaluator.win - 50));
    });

    test('Hard arms a begi that is one slide away', () {
      // fixed 6,7,9 + swinging token on 0; sliding 18 -> 17 arms 0<->1
      final s = st([0, 6, 7, 9, 18], [12, 14, 20, 22]);
      final r = find(s, AiConfig.hard.withTime(4000).withDepth(4));
      expect(r.move, const Move.slide(18, 17), reason: 'got ${r.move}');
    });

    test('Medium sees a forming begi and blocks it', () {
      // seat 1 can arm 0<->1 by sliding 18 -> 17 and then swing to eat.
      // Seat 0 must take 17 first.
      final s = st([16, 4, 11, 15], [0, 6, 7, 9, 18]);
      final m = find(s, AiConfig.medium.withTime(4000)).move;
      expect(m, const Move.slide(16, 17), reason: 'got $m');
    });
  });

  group('search behaviour', () {
    test('always returns a legal move', () {
      var s = GameState.initial();
      for (var i = 0; i < 12 && !s.isOver; i++) {
        final m = find(s, AiConfig.easy.withTime(150)).move;
        expect(Rules.isLegal(s, m), isTrue, reason: '$m in $s');
        s = Rules.apply(s, m);
      }
    });

    test('handles the opening double placement (same seat moves twice)', () {
      final s0 = GameState.initial();
      final m1 = find(s0, AiConfig.medium.withTime(400)).move;
      final s1 = Rules.apply(s0, m1);
      expect(s1.turn, 0);
      final m2 = find(s1, AiConfig.medium.withTime(400)).move;
      expect(Rules.isLegal(s1, m2), isTrue);
    });

    test('is deterministic', () {
      final s = st([0, 6, 7], [20, 22, 18], hand0: 5, hand1: 5);
      const cfg = AiConfig.easy;
      expect(find(s, cfg).move, find(s, cfg).move);
    });

    test('respects the time cap', () {
      final cfg = AiConfig.hard.withTime(300);
      final sw = Stopwatch()..start();
      final r = find(GameState.initial(), cfg);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1500));
      expect(r.depth, greaterThanOrEqualTo(1));
    });

    test('deeper configs search deeper in the same time', () {
      final s = st([0, 2, 9], [20, 22, 13], hand0: 4, hand1: 4);
      final easy = find(s, AiConfig.easy.withTime(2000));
      final hard = find(s, AiConfig.hard.withTime(2000));
      expect(easy.depth, 2);
      expect(hard.depth, greaterThan(easy.depth));
    });

    test('the isolate service returns the same kind of move', () async {
      final s = st([0, 1], [20, 22], hand0: 5, hand1: 5);
      final m = await IsolateAiService().chooseMove(s, AiConfig.easy);
      expect(m.to, 2);
      expect(Rules.isLegal(s, m), isTrue);
    });
  });
}
