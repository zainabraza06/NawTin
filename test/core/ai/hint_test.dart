import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/ai/hint_analyzer.dart';
import 'package:nawtin/core/engine/engine.dart';

GameState st(
  List<int> a,
  List<int> b, {
  int hand0 = 0,
  int hand1 = 0,
  int turn = 0,
}) =>
    GameState.fromMasks(
      mask0: maskOf(a),
      mask1: maskOf(b),
      hand0: hand0,
      hand1: hand1,
      turn: turn,
    );

void main() {
  test('warns when the opponent is one move from a line', () {
    // seat 1 has 0 and 1 in the top line and a token left to place
    final s = st([20, 22], [0, 1], hand0: 5, hand1: 5, turn: 0);
    final a = HintAnalyzer.warning(s, 0);
    // seat 0 also threatens 20-21-22, and it is seat 0's move
    expect(a.kind, HintKind.bothThreaten);

    final s2 = st([12, 23], [0, 1], hand0: 5, hand1: 5, turn: 0);
    final b = HintAnalyzer.warning(s2, 0);
    expect(b.kind, HintKind.opponentThreat);
    expect(b.message, contains('one move from completing a line'));
  });

  test('warns about a forming begi before it is armed', () {
    // seat 1 owns the four fixed tokens of the 0<->1 begi but nothing on a stop
    final s = st([16, 4, 11, 15], [6, 7, 9, 17], turn: 0);
    final a = HintAnalyzer.warning(s, 0);
    expect(a.kind, HintKind.swingForming);
    expect(a.message, contains('begi'));
  });

  test('a blocked setup is not reported', () {
    // same fixed tokens, but seat 0 sits on stop 0
    final s = st([0, 4, 11, 15], [6, 7, 9, 17], turn: 0);
    expect(HintAnalyzer.formingSwing(s, 1), isNull);
  });

  test('points out your own chance to make three', () {
    final s = st([0, 1], [20, 12, 23], hand0: 5, hand1: 5, turn: 0);
    expect(HintAnalyzer.warning(s, 0).kind, HintKind.yourChance);
  });

  test('a quiet position gets calm advice, never a move', () {
    final s = GameState.initial();
    final a = HintAnalyzer.warning(s, 0);
    expect(a.kind, HintKind.calm);
    expect(a.message.toLowerCase(), isNot(contains('place on')));
  });
}
