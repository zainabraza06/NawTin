import '../../core/engine/engine.dart';

/// One scripted step of a demo. [pick] shows the "eat a token" targeting
/// before the move lands; [phutas] presses PHUTAS after the move.
class DemoStep {
  const DemoStep(this.move, {this.pick = false, this.phutas = false});
  final Move move;
  final bool pick;
  final bool phutas;
}

class DemoScript {
  const DemoScript(this.start, this.steps);
  final GameState start;
  final List<DemoStep> steps;
}

GameState _pos(List<int> a, List<int> b, {int h0 = 0, int h1 = 0, int places = 1}) =>
    GameState.fromMasks(
      mask0: maskOf(a),
      mask1: maskOf(b),
      hand0: h0,
      hand1: h1,
      turn: 0,
      placesLeft: places,
    );

/// The looping demos on the How to Play cards. Each one is verified against
/// the real rules engine in the tests, so what the card shows is what the
/// game does.
abstract final class DemoScripts {
  /// The board itself: 24 points, 16 lines, nothing moving.
  static final board = DemoScript(GameState.initial(), const []);

  /// Opening double placement, then one token each.
  static final placement = DemoScript(GameState.initial(), const [
    DemoStep(Move.place(0)),
    DemoStep(Move.place(4)),
    DemoStep(Move.place(9)),
    DemoStep(Move.place(11)),
    DemoStep(Move.place(13)),
  ]);

  /// Two on a line and the third point is free: PHUTAS, then the payoff.
  static final phutas = DemoScript(
    _pos([0], [20], h0: 5, h1: 5),
    const [
      DemoStep(Move.place(1), phutas: true),
      DemoStep(Move.place(23)),
      DemoStep(Move.place(2, capture: 20), pick: true),
    ],
  );

  /// Make three, eat one. The finished line 12-13-14 is protected, so only
  /// the loose tokens can be chosen.
  static final machyas = DemoScript(
    _pos([0, 1, 3, 5], [12, 13, 14, 20, 22]),
    const [DemoStep(Move.slide(3, 2, capture: 22), pick: true)],
  );

  /// One token swings between 1 and 0; every stop completes a line.
  static final begi = DemoScript(
    _pos([6, 7, 9, 17, 2], [12, 13, 14, 19, 23]),
    const [
      DemoStep(Move.slide(2, 1, capture: 19), pick: true),
      DemoStep(Move.slide(23, 22)),
      DemoStep(Move.slide(1, 0, capture: 22), pick: true),
    ],
  );

  /// The last fixed token arrives and a triple mill is ready to swing.
  static final treghi = DemoScript(
    _pos([0, 3, 5, 6, 7, 9, 17], [12, 13, 14, 20, 23]),
    const [
      DemoStep(Move.slide(5, 4)),
      DemoStep(Move.slide(20, 21)),
      DemoStep(Move.slide(0, 1, capture: 21), pick: true),
      DemoStep(Move.slide(23, 22)),
      DemoStep(Move.slide(1, 2, capture: 22), pick: true),
    ],
  );

  static final all = [board, placement, phutas, machyas, begi, treghi];
}
