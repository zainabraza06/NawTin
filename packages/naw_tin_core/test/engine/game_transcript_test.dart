import 'dart:math';

import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  List<Move> randomGame(int seed) {
    final rnd = Random(seed);
    var s = GameState.initial();
    final moves = <Move>[];
    while (!s.isOver && moves.length < 120) {
      final l = Rules.legalMoves(s);
      final m = l[rnd.nextInt(l.length)];
      moves.add(m);
      s = Rules.apply(s, m);
    }
    return moves;
  }

  test('a game written out and read back is the same game', () {
    for (final seed in [1, 2, 3, 4, 5]) {
      final moves = randomGame(seed);
      final text = GameTranscript({'mode': 'vsAi', 'level': 'hard', 'ai': '1'}, moves).encode();
      final back = GameTranscript.parse(text)!;
      expect(back.moves, moves);
      expect(back.meta['level'], 'hard');
      expect(back.meta['ai'], '1');
    }
  });

  test('replaying a record reproduces every position, ending in the same result', () {
    final moves = randomGame(7);
    var s = GameState.initial();
    for (final m in moves) {
      s = Rules.apply(s, m);
    }
    final positions = GameTranscript({}, moves).positions();
    expect(positions.length, moves.length + 1);
    expect(positions.last, s);
    expect(positions.last.result?.winner, s.result?.winner);
    expect(positions.last.result?.reason, s.result?.reason);
  });

  test('the text format is compact and readable', () {
    final t = const GameTranscript({'mode': 'friend'}, [Move.place(9), Move.slide(3, 2, capture: 20)]).encode();
    expect(t, 'NAWTIN1 mode=friend\np9 s3-2x20');
  });

  test('anything that is not a record is rejected, not half-read', () {
    expect(GameTranscript.parse(''), isNull);
    expect(GameTranscript.parse('hello world'), isNull);
    expect(GameTranscript.parse('NAWTIN1 mode=x\np9 zz'), isNull);
    expect(GameTranscript.parse('NAWTIN1 mode=x\np9 s3'), isNull);
    expect(GameTranscript.parse('NAWTIN1 mode=x')!.moves, isEmpty);
  });

  test('an impossible move is reported when replaying', () {
    final rec = GameTranscript.parse('NAWTIN1 mode=x\np9 p9')!; // the same point twice
    expect(rec.positions, throwsStateError);
  });
}
