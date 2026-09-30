import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/engine/engine.dart';

void main() {
  test('the default: both players open with two tokens', () {
    expect(Rules.placementRule, PlacementRule.symmetricOpening);
    var s = GameState.initial();
    expect(s.turn, 0);
    expect(s.placesLeft, 2);
    s = Rules.apply(s, const Move.place(0));
    s = Rules.apply(s, const Move.place(4));
    expect(s.turn, 1);
    expect(s.placesLeft, 2, reason: 'player 2 also opens with two tokens');
    s = Rules.apply(s, const Move.place(9));
    expect(s.turn, 1);
    s = Rules.apply(s, const Move.place(11));
    expect(s.turn, 0);
    expect(s.placesLeft, 1);
  });

  test('nobody ever has to skip a turn or place twice at the end', () {
    // 18 tokens, no captures: turns strictly alternate after the openings
    const a = [0, 2, 4, 6, 9, 11, 13, 15, 17];
    const b = [1, 3, 5, 7, 8, 10, 12, 14, 21];
    var s = GameState.initial();
    final order = <int>[];
    final seq = [a[0], a[1], b[0], b[1], for (var i = 2; i < 9; i++) ...[a[i], b[i]]];
    for (final p in seq) {
      order.add(s.turn);
      s = Rules.apply(s, Move.place(p));
    }
    expect(order, [0, 0, 1, 1, for (var i = 0; i < 7; i++) ...[0, 1]]);
    expect(s.phase, GamePhase.movement);
    expect(s.turn, 0, reason: 'player 1 makes the first slide');
  });
}
