import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/engine/engine.dart';

/// Builds a position from point lists. `turn` is the seat to act.
GameState st(
  List<int> seat0,
  List<int> seat1, {
  int hand0 = 0,
  int hand1 = 0,
  int turn = 0,
  int placesLeft = 1,
}) =>
    GameState.fromMasks(
      mask0: maskOf(seat0),
      mask1: maskOf(seat1),
      hand0: hand0,
      hand1: hand1,
      turn: turn,
      placesLeft: placesLeft,
    );

/// Plays a list of moves, asserting each is legal.
GameState play(GameState s, List<Move> moves) {
  for (final m in moves) {
    expect(Rules.isLegal(s, m), isTrue, reason: '$m in $s');
    s = Rules.apply(s, m);
  }
  return s;
}

void main() {
  // Most tests below pin the ORIGINAL placement order (opening + closing
  // double); the symmetric opening (the app default) has its own group.
  setUp(() => Rules.placementRule = PlacementRule.openingAndClosingDouble);
  tearDown(() => Rules.placementRule = PlacementRule.symmetricOpening);

  placementRuleTests();
  group('lines and protection', () {
    test('linesCompletedAt sees only lines through the point', () {
      final top = maskOf([0, 1, 2]);
      expect(Rules.linesCompletedAt(top, 1), 1 << 0);
      expect(Rules.linesCompletedAt(top, 9), 0); // 9 is not even owned
      final corner = maskOf([0, 1, 2, 6, 7]);
      expect(Rules.linesCompletedAt(corner, 7), 1 << 3); // only (6,7,0)
      // corner 0 lies on two lines and completes both at once
      expect(Rules.linesCompletedAt(corner, 0), (1 << 0) | (1 << 3));
      expect(Rules.completedLines(corner), (1 << 0) | (1 << 3));
    });

    test('a token is protected only while on a completed line', () {
      final own = maskOf([12, 13, 14, 21]);
      expect(Rules.protectedMask(own), maskOf([12, 13, 14]));
      // 13 leaves the line: nobody is protected any more
      expect(Rules.protectedMask(maskOf([12, 14, 21])), 0);
    });

    test('fixed tokens of an open begi line are not protected', () {
      // begi 0<->1: fixed 6,7 (left side) and 9,17 (top cross line)
      final onCorner = maskOf([6, 7, 9, 17, 0]);
      expect(Rules.protectedMask(onCorner), maskOf([0, 6, 7]));
      final onMid = maskOf([6, 7, 9, 17, 1]);
      expect(Rules.protectedMask(onMid), maskOf([1, 9, 17]));
    });

    test('a token on two completed lines is protected once', () {
      final own = maskOf([0, 1, 2, 6, 7]);
      expect(Rules.protectedMask(own), maskOf([0, 1, 2, 6, 7]));
    });
  });

  group('initial state and phases', () {
    test('9 tokens each, seat 0 places two', () {
      final s = GameState.initial();
      expect(s.hand0, 9);
      expect(s.hand1, 9);
      expect(s.turn, 0);
      expect(s.placesLeft, 2);
      expect(s.phase, GamePhase.placement);
      expect(s.totalTokens(0), 9);
      expect(s.lostTokens(1), 0);
    });

    test('placement can go on any of the 24 empty points', () {
      final moves = Rules.legalMoves(GameState.initial());
      expect(moves.length, 24);
      expect(moves.every((m) => m.isPlacement && !m.hasCapture), isTrue);
    });

    test('first turn: seat 0 places two tokens, then play alternates', () {
      var s = GameState.initial();
      s = Rules.apply(s, const Move.place(0));
      expect(s.turn, 0, reason: 'still seat 0 for the second token');
      expect(s.placesLeft, 1);
      expect(s.hand0, 8);
      s = Rules.apply(s, const Move.place(4));
      expect(s.turn, 1);
      expect(s.hand0, 7);
      s = Rules.apply(s, const Move.place(9));
      expect(s.turn, 0);
      expect(s.hand1, 8);
      s = Rules.apply(s, const Move.place(11));
      expect(s.turn, 1, reason: 'seat 0 places only one token now');
    });

    test('a placement onto an occupied point is illegal', () {
      final s = st([0], [1], hand0: 5, hand1: 5);
      expect(Rules.isLegal(s, const Move.place(0)), isFalse);
      expect(Rules.isLegal(s, const Move.place(1)), isFalse);
      expect(Rules.isLegal(s, const Move.place(2)), isTrue);
    });

    test('scripted full placement ends in the movement phase, seat 0 to move',
        () {
      // Chosen so that no line is ever completed (no captures).
      const a = [0, 2, 4, 6, 9, 11, 13, 15, 17];
      const b = [1, 3, 5, 7, 8, 10, 12, 14, 21];
      var s = GameState.initial();
      s = play(s, [Move.place(a[0]), Move.place(a[1])]);
      for (var i = 0; i < 7; i++) {
        s = play(s, [Move.place(b[i]), Move.place(a[i + 2])]);
        expect(s.phase, GamePhase.placement);
      }
      expect(s.hand0, 0);
      expect(s.hand1, 2);
      expect(s.turn, 1);
      s = play(s, [Move.place(b[7])]);
      expect(s.turn, 1, reason: 'seat 0 has nothing left to place');
      expect(s.phase, GamePhase.placement);
      s = play(s, [Move.place(b[8])]);
      expect(s.phase, GamePhase.movement);
      expect(s.turn, 0);
      expect(s.totalTokens(0), 9);
      expect(s.totalTokens(1), 9);
      expect(s.isOver, isFalse);
    });
  });

  group('captures during placement', () {
    test('completing a line by placing lets the mover eat a token', () {
      final s = st([0, 1], [8, 16], hand0: 5, hand1: 5);
      const step = Move.place(2);
      expect(Rules.linesFormedByStep(s, step), 1 << 0);
      expect(Rules.captureTargets(s, step), maskOf([8, 16]));
      final moves = Rules.legalMoves(s);
      // 20 empty points; the completing one is expanded into 2 captures
      expect(moves.length, 19 + 2);
      expect(moves.where((m) => m.to == 2 && m.hasCapture).length, 2);
      expect(moves.contains(const Move.place(2)), isFalse,
          reason: 'a completing placement must name a capture');
      final after = Rules.apply(s, const Move.place(2, capture: 8));
      expect(after.mask1, maskOf([16]));
      expect(after.totalTokens(1), 6); // 1 on board + 5 unplaced
      expect(after.lostTokens(1), 3);
      expect(after.turn, 1);
    });

    test('a capture must target an opponent token', () {
      final s = st([0, 1], [8, 16], hand0: 5, hand1: 5);
      expect(Rules.isLegal(s, const Move.place(2, capture: 5)), isFalse);
      expect(Rules.isLegal(s, const Move.place(2)), isFalse);
      expect(Rules.isLegal(s, const Move.place(3, capture: 8)), isFalse);
    });

    test('lines count on the second token of the opening turn', () {
      // first token already down; second token (placesLeft 1 but same seat)
      // completes a line - and a completed line inside the opening turn keeps
      // the turn with the same seat only while placements remain.
      final s = st([0, 1], [8, 16], hand0: 5, hand1: 5, placesLeft: 2);
      final after = Rules.apply(s, const Move.place(2, capture: 16));
      expect(after.mask1, maskOf([8]));
      expect(after.turn, 0, reason: 'opening turn still has one placement');
      expect(after.placesLeft, 1);
    });

    test('nothing to eat when the opponent has no token on the board', () {
      final s = st([0, 1], [], hand0: 5, hand1: 6);
      expect(Rules.captureTargets(s, const Move.place(2)), 0);
      expect(Rules.isLegal(s, const Move.place(2)), isTrue);
    });
  });

  group('movement generation', () {
    test('a token slides only along lines to adjacent empty points', () {
      final s = st([1], [], hand0: 0, hand1: 0);
      // second seat has no tokens; only generation matters here
      final moves = Rules.stepMoves(s);
      expect(moves.map((m) => m.to).toSet(), {0, 2, 9});
      expect(moves.every((m) => m.from == 1), isTrue);
    });

    test('occupied neighbours block a slide', () {
      final s = st([1, 0], [9], hand0: 0, hand1: 0);
      final targets = Rules.stepMoves(s)
          .where((m) => m.from == 1)
          .map((m) => m.to)
          .toSet();
      expect(targets, {2});
    });

    test('corners have two moves, middle midpoints up to four', () {
      expect(Rules.stepMoves(st([0], [])).length, 2);
      expect(Rules.stepMoves(st([9], [])).length, 4);
      expect(Rules.stepMoves(st([17], [])).length, 3);
    });

    test('tokens cannot jump to the far end of a line or across the centre',
        () {
      final moves = Rules.stepMoves(st([0], []));
      expect(moves.map((m) => m.to).toSet(), {1, 7});
    });

    test('slide completing a line captures; protected tokens are skipped', () {
      // seat 1 has a finished line 12-13-14 plus loose token 20
      final s = st([0, 1, 3], [12, 13, 14, 20]);
      const step = Move.slide(3, 2);
      expect(Rules.linesFormedByStep(s, step), 1 << 0);
      expect(Rules.captureTargets(s, step), maskOf([20]));
      final after = Rules.apply(s, const Move.slide(3, 2, capture: 20));
      expect(after.mask1, maskOf([12, 13, 14]));
      expect(after.mask0, maskOf([0, 1, 2]));
      expect(after.turn, 1);
    });

    test('all opponent tokens protected: any token may be eaten', () {
      final s = st([0, 1, 3], [12, 13, 14, 16, 17, 18]);
      expect(Rules.captureTargets(s, const Move.slide(3, 2)),
          maskOf([12, 13, 14, 16, 17, 18]));
      expect(Rules.isLegal(s, const Move.slide(3, 2, capture: 13)), isTrue);
    });

    test('a token that just left its line is no longer protected', () {
      // seat 1 had 12-13-14 and moved 13 away to 21; now 12/14/21 are loose
      final s = st([0, 1, 3], [12, 14, 21]);
      expect(Rules.captureTargets(s, const Move.slide(3, 2)),
          maskOf([12, 14, 21]));
    });

    test('a slide that completes nothing has no capture', () {
      final s = st([0, 5, 3], [12, 13, 14]);
      expect(Rules.captureTargets(s, const Move.slide(0, 1)), 0);
      expect(Rules.isLegal(s, const Move.slide(0, 1, capture: 12)), isFalse);
    });

    test('a token cannot slide out of a placement-phase hand rule', () {
      final s = st([0], [5], hand0: 3, hand1: 3);
      expect(Rules.isLegal(s, const Move.slide(0, 1)), isFalse);
    });

    test('placing is illegal once the hand is empty', () {
      final s = st([0, 6, 3], [12, 13, 14]);
      expect(Rules.isLegal(s, const Move.place(9)), isFalse);
    });

    test('legalMoves expands each capture as its own move', () {
      final s = st([0, 1, 3], [12, 13, 14, 20, 22]);
      final moves = Rules.legalMoves(s);
      final completing = moves.where((m) => m.from == 3 && m.to == 2).toList();
      expect(completing.map((m) => m.capture).toSet(), {20, 22});
      // every generated move is legal
      expect(moves.every((m) => Rules.isLegal(s, m)), isTrue);
    });
  });

  group('end of game', () {
    test('opponent reduced to 2 tokens on the board loses', () {
      final s = st([0, 1, 3], [12, 14, 20]);
      final after = Rules.apply(s, const Move.slide(3, 2, capture: 20));
      expect(after.isOver, isTrue);
      expect(after.result!.winner, 0);
      expect(after.result!.reason, GameEndReason.tokensReduced);
    });

    test('unplaced tokens count toward the total', () {
      // seat 1: 1 on board + 1 in hand = 2 after losing one? 0 + 1 = 1 -> loses
      final s = st([0, 1], [8], hand0: 5, hand1: 1);
      final after = Rules.apply(s, const Move.place(2, capture: 8));
      expect(after.result!.winner, 0);
      // with 3 left in hand the game goes on
      final s2 = st([0, 1], [8], hand0: 5, hand1: 3);
      final after2 = Rules.apply(s2, const Move.place(2, capture: 8));
      expect(after2.isOver, isFalse);
      expect(after2.totalTokens(1), 3);
    });

    test('a player with no legal move loses', () {
      // seat 1 tokens 0, 2, 4 are boxed in once seat 0 slides 15 -> 7
      final s = st([1, 3, 5, 15], [0, 2, 4]);
      final after = Rules.apply(s, const Move.slide(15, 7));
      expect(after.isOver, isTrue);
      expect(after.result!.winner, 0);
      expect(after.result!.reason, GameEndReason.noLegalMoves);
    });

    test('three-fold repetition is a draw', () {
      var s = st([0, 4, 18], [12, 14, 20]);
      const cycle = [
        Move.slide(0, 1),
        Move.slide(20, 21),
        Move.slide(1, 0),
        Move.slide(21, 20),
      ];
      // back to the start position after 4 plies: it has now occurred twice
      s = play(s, cycle);
      expect(s.isOver, isFalse);
      s = play(s, cycle.sublist(0, 3));
      expect(s.isOver, isFalse);
      s = play(s, [cycle[3]]); // third occurrence of the start position
      expect(s.isOver, isTrue);
      expect(s.result!.isDraw, isTrue);
      expect(s.result!.reason, GameEndReason.repetition);
    });

    test('a capture resets the repetition count', () {
      final s = st([0, 1, 3, 5], [12, 14, 20, 22]);
      final after = Rules.apply(s, const Move.slide(3, 2, capture: 20));
      expect(after.history.count(after.positionKey), 1);
    });

    test('disqualify ends the game for the other seat', () {
      final s = GameState.initial().disqualify(1);
      expect(s.result!.winner, 0);
      expect(s.result!.reason, GameEndReason.disqualified);
    });
  });

  group('calls', () {
    test('MACHYAS is reported for a capturing move', () {
      final s = st([0, 1], [8, 16], hand0: 5, hand1: 5);
      final r = MoveResult.resolve(s, const Move.place(2, capture: 8));
      expect(r.isMachyas, isTrue);
      expect(r.completedLines, 1 << 0);
      expect(r.autoCalls, contains(Call.machyas));
    });

    test('PHUTAS: placing a second token on a line sets up a new threat', () {
      final s = st([0], [20], hand0: 5, hand1: 5);
      final r = MoveResult.resolve(s, const Move.place(1));
      expect(r.phutasLines, 1 << 0);
      expect(r.canPhutas, isTrue);
    });

    test('PHUTAS is not offered again for a threat that already existed', () {
      final s = st([0, 1], [20], hand0: 5, hand1: 5);
      expect(Analysis.threatLines(s, 0), 1 << 0);
      final r = MoveResult.resolve(s, const Move.place(23));
      expect(r.canPhutas, isFalse);
    });

    test('a line whose third point is taken is not a threat', () {
      final s = st([0, 1], [2], hand0: 5, hand1: 5);
      expect(Analysis.threatLines(s, 0), 0);
    });

    test('PHUTAS in movement needs an off-line token beside the gap', () {
      final s = st([0, 1, 4], [12, 14, 20]);
      // 4 is not next to gap 2: no threat yet
      expect(Analysis.threatLines(s, 0), 0);
      final r = MoveResult.resolve(s, const Move.slide(4, 3));
      expect(r.phutasLines, 1 << 0);
      // a token on the line itself never counts: 1 is beside 2 but on the line
      expect(Analysis.threatLines(st([0, 1], [12, 14, 20]), 0), 0);
    });

    test('BEGI is announced once, when it first forms', () {
      // seat 0 sits on 2 with fixed tokens 6,7,9,17; sliding 2 -> 1 completes
      // the cross line and arms the 0<->1 begi
      final s = st([6, 7, 9, 17, 2], [12, 13, 14, 19, 23]);
      final r1 = MoveResult.resolve(s, const Move.slide(2, 1, capture: 19));
      expect(r1.isMachyas, isTrue);
      expect(r1.swingEvents.length, 1);
      expect(r1.swingEvents.single.seat, 0);
      expect(r1.announcedSwing!.call, Call.begi);
      expect(r1.autoCalls, [Call.machyas, Call.begi]);
      expect(r1.canPhutas, isFalse, reason: 'swing lines are never a Phutas');

      // seat 1 answers, then the swing 1 -> 0 is a plain MACHYAS
      final mid = play(r1.after, [const Move.slide(23, 22)]);
      final r2 = MoveResult.resolve(mid, const Move.slide(1, 0, capture: 22));
      expect(r2.isMachyas, isTrue);
      expect(r2.swingEvents, isEmpty);
      expect(r2.autoCalls, [Call.machyas]);
      expect(r2.canPhutas, isFalse);
    });

    test('a begi is not armed while the opponent blocks the far stop', () {
      final own = maskOf([6, 7, 9, 17, 1]);
      expect(SwingPattern.armed(own, bit(0)), isEmpty);
      expect(SwingPattern.armed(own, 0), isNotEmpty);
    });

    test('TREGHI outranks the begi it contains and is announced once', () {
      // begi 0<->1 is already armed; sliding 5 -> 4 adds the last fixed
      // token of the 0-1-2 treghi
      final s = st([0, 3, 5, 6, 7, 9, 17], [12, 13, 14, 20]);
      final r = MoveResult.resolve(s, const Move.slide(5, 4));
      expect(r.isMachyas, isFalse);
      expect(r.swingEvents.length, 1);
      expect(r.announcedSwing!.call, Call.treghi);
      expect(r.autoCalls, [Call.treghi]);
      final again = play(r.after, [const Move.slide(20, 21)]);
      // swinging 0 -> 1 completes the cross line; the begi 1<->2 it now arms
      // lives inside the treghi, so nothing new is announced
      final r2 = MoveResult.resolve(again, const Move.slide(0, 1, capture: 21));
      expect(r2.swingEvents, isEmpty);
      expect(r2.isMachyas, isTrue);
      expect(r2.autoCalls, [Call.machyas]);
    });

    test('every one of the 48 patterns arms and pays out as a swing', () {
      // Put the fixed tokens plus the swinging token on the first stop, then
      // slide it through each stop: every stop must complete a line.
      for (final p in SwingPattern.all) {
        var own = p.fixedMask | bit(p.stops.first);
        expect(SwingPattern.armed(own, 0), contains(p), reason: '$p');
        for (var i = 0; i < p.stops.length - 1; i++) {
          final from = p.stops[i], to = p.stops[i + 1];
          own = (own & ~bit(from)) | bit(to);
          expect(Rules.linesCompletedAt(own, to), 1 << p.stopLines[i + 1],
              reason: '$p stop $to');
        }
      }
    });
  });

  group('agreed edge cases', () {
    test("seat 1's closing double: the second token can complete a line", () {
      // seat 0 is out of tokens; seat 1 has two left and places both in a row
      final s = st([8, 10, 12, 22], [0, 1], hand0: 0, hand1: 2, turn: 1);
      final r1 = MoveResult.resolve(s, const Move.place(2, capture: 8));
      expect(r1.isMachyas, isTrue);
      expect(r1.after.turn, 1, reason: 'seat 0 has nothing to place');
      expect(r1.after.phase, GamePhase.placement);
      final r2 = MoveResult.resolve(r1.after, const Move.place(20));
      expect(r2.after.phase, GamePhase.movement);
      expect(r2.after.turn, 0, reason: 'seat 0 moves first afterwards');

      // and the last token itself may complete the line and eat (Machyas)
      final s2 = st([8, 10, 12, 22], [0, 1], hand0: 0, hand1: 2, turn: 1);
      final a = Rules.apply(s2, const Move.place(20));
      expect(a.turn, 1);
      final r3 = MoveResult.resolve(a, const Move.place(2, capture: 12));
      expect(r3.isMachyas, isTrue);
      expect(r3.after.phase, GamePhase.movement);
      expect(r3.after.turn, 0);
    });

    test('a setup that is blocked and then unblocked is announced again, '
        'credited to the player who benefits', () {
      final s = st([0, 6, 7, 9, 17], [1, 12, 13, 14], turn: 1);
      expect(SwingPattern.armed(s.mask0, s.mask1), isEmpty);
      final r = MoveResult.resolve(s, const Move.slide(1, 2)); // opponent moves
      expect(r.swingEvents.length, 1);
      expect(r.swingEvents.single.seat, 0);
      expect(r.swingEvents.single.call, Call.begi);
      expect(r.swingEvents.single.readyOnly, isFalse);
    });

    test('a begi formed during placement is "ready only"', () {
      final s = st([0, 6, 7, 9], [20], hand0: 5, hand1: 5);
      final r = MoveResult.resolve(s, const Move.place(17));
      expect(r.swingEvents.length, 1);
      expect(r.swingEvents.single.call, Call.begi);
      expect(r.swingEvents.single.readyOnly, isTrue);
    });

    test('an announced begi that grows into a treghi announces Treghi', () {
      // begi 0<->1 is armed; the last treghi token arrives (5 -> 4)
      final s = st([0, 3, 5, 6, 7, 9, 17], [12, 13, 14, 20]);
      expect(SwingPattern.armed(s.mask0, s.mask1).map((p) => p.kind),
          [PatternKind.begi]);
      final r = MoveResult.resolve(s, const Move.slide(5, 4));
      expect(r.announcedSwing!.call, Call.treghi);
    });
  });

  group('random play-outs', () {
    test('engine invariants hold over many random games', () {
      final rnd = Random(2024);
      var finished = 0;
      var sawMovement = 0;
      for (var g = 0; g < 150; g++) {
        var s = GameState.initial();
        var plies = 0;
        while (!s.isOver && plies < 600) {
          final moves = Rules.legalMoves(s);
          expect(moves, isNotEmpty, reason: 'unfinished game must have moves');
          s = Rules.apply(s, moves[rnd.nextInt(moves.length)]);
          plies++;
          expect(s.mask0 & s.mask1, 0);
          expect(s.mask0 | s.mask1, lessThanOrEqualTo(Board.fullMask));
          expect(s.totalTokens(0), inInclusiveRange(0, 9));
          expect(s.totalTokens(1), inInclusiveRange(0, 9));
          expect(s.phase == GamePhase.movement, s.hand0 + s.hand1 == 0);
          if (s.phase == GamePhase.placement) {
            expect(s.handOf(s.turn), greaterThan(0));
          }
        }
        if (s.phase == GamePhase.movement) sawMovement++;
        if (s.isOver) finished++;
      }
      expect(sawMovement, greaterThan(0));
      expect(finished, greaterThan(0));
    });
  });
}

void placementRuleTests() {
  group('PlacementRule.symmetricOpening', () {
    setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

    test('both seats open with two tokens, then strict alternation', () {
      var s = GameState.initial();
      s = play(s, [const Move.place(0), const Move.place(4)]);
      expect(s.turn, 1);
      expect(s.placesLeft, 2);
      s = play(s, [const Move.place(9)]);
      expect(s.turn, 1, reason: 'seat 1 places a second opening token');
      s = play(s, [const Move.place(11)]);
      expect(s.turn, 0);
      expect(s.placesLeft, 1);
      s = play(s, [const Move.place(13)]);
      expect(s.turn, 1);
      expect(s.placesLeft, 1);
    });

    test('there is no closing double: seat 1 places last, seat 0 moves first',
        () {
      const a = [0, 2, 4, 6, 9, 11, 13, 15, 17];
      const b = [1, 3, 5, 7, 8, 10, 12, 14, 21];
      var s = GameState.initial();
      s = play(s, [Move.place(a[0]), Move.place(a[1])]);
      s = play(s, [Move.place(b[0]), Move.place(b[1])]);
      for (var i = 2; i < 9; i++) {
        s = play(s, [Move.place(a[i])]);
        expect(s.turn, 1);
        s = play(s, [Move.place(b[i])]);
      }
      expect(s.phase, GamePhase.movement);
      expect(s.turn, 0);
      expect(s.totalTokens(0), 9);
      expect(s.totalTokens(1), 9);
    });

    test('random play-outs keep the invariants', () {
      final rnd = Random(77);
      for (var g = 0; g < 60; g++) {
        var s = GameState.initial();
        var plies = 0;
        while (!s.isOver && plies < 400) {
          final moves = Rules.legalMoves(s);
          expect(moves, isNotEmpty);
          s = Rules.apply(s, moves[rnd.nextInt(moves.length)]);
          plies++;
          expect(s.totalTokens(0), inInclusiveRange(0, 9));
          expect(s.totalTokens(1), inInclusiveRange(0, 9));
          if (s.phase == GamePhase.placement) {
            expect(s.handOf(s.turn), greaterThan(0));
          }
        }
      }
    });
  });
}
