import 'dart:math';

import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

void main() {
  group('room codes', () {
    test('the alphabet has no ambiguous characters', () {
      for (final bad in ['0', 'O', '1', 'I']) {
        expect(roomCodeAlphabet.contains(bad), isFalse, reason: bad);
      }
      expect(roomCodeAlphabet.length, 32);
    });

    test('normalising and validating typed codes', () {
      expect(normalizeRoomCode(' k7t-q3m '), 'K7TQ3M');
      expect(isValidRoomCode('K7TQ3M'), isTrue);
      expect(isValidRoomCode('K7TQ3'), isFalse);
      expect(isValidRoomCode('K7TQ30'), isFalse, reason: 'contains 0');
      expect(isValidRoomCode('K7TQ3I'), isFalse, reason: 'contains I');
    });
  });

  group('snapshot codec', () {
    test('round-trips every position of random games', () {
      final rnd = Random(5);
      for (var g = 0; g < 40; g++) {
        var s = GameState.initial();
        for (var i = 0; i < 200 && !s.isOver; i++) {
          final moves = Rules.legalMoves(s);
          s = Rules.apply(s, moves[rnd.nextInt(moves.length)]);
          final back = decodeSnapshot(encodeSnapshot(s));
          expect(back, s);
          expect(back.result?.winner, s.result?.winner);
          expect(back.result?.reason, s.result?.reason);
          expect(back.phase, s.phase);
        }
      }
    });

    test('online-only end reasons survive on the wire', () {
      final s = GameState.initial().disqualify(0);
      final json = encodeSnapshot(s, endReasonOverride: EndReason.forfeit);
      expect(snapshotEndReason(json), EndReason.forfeit);
      expect(decodeSnapshot(json).result!.winner, 1);
    });

    test('rejects malformed or hostile snapshots', () {
      final good = encodeSnapshot(GameState.initial());
      expect(() => decodeSnapshot(null), throwsFormatException);
      expect(() => decodeSnapshot({...good, 'mask0': 1 << 30}), throwsFormatException);
      expect(() => decodeSnapshot({...good, 'mask0': 3, 'mask1': 3}), throwsFormatException);
      expect(() => decodeSnapshot({...good, 'turn': 2}), throwsFormatException);
      expect(() => decodeSnapshot({...good, 'hand0': 99}), throwsFormatException);
      expect(() => decodeSnapshot({...good, 'result': {'winner': 5, 'reason': 'tokensReduced'}}),
          throwsFormatException);
    });
  });

  group('move codec', () {
    test('placements, slides and captures', () {
      for (final m in [
        const Move.place(9),
        const Move.slide(3, 2),
        const Move.slide(3, 2, capture: 20),
        const Move.place(2, capture: 5),
      ]) {
        expect(decodeMove(encodeMove(m)), m);
      }
    });

    test('rejects out-of-range points', () {
      expect(() => decodeMove({'from': -1, 'to': 24}), throwsFormatException);
      expect(() => decodeMove({'to': 'x'}), throwsFormatException);
      expect(() => decodeMove(5), throwsFormatException);
    });
  });

  test('every wire constant is unique', () {
    final types = <String>{
      Msg.hello, Msg.createRoom, Msg.joinRoom, Msg.ready, Msg.start, Msg.place,
      Msg.move, Msg.capture, Msg.pressPhutas, Msg.emote, Msg.offerRematch,
      Msg.acceptRematch, Msg.leave, Msg.report, Msg.ping, Msg.welcome, Msg.error,
      Msg.roomState, Msg.gameState, Msg.event, Msg.pong, Msg.ack,
    };
    expect(types.length, 22);
    expect(Msg.sequenced.contains(Msg.ping), isFalse);
    expect(Msg.sequenced.contains(Msg.hello), isFalse);
  });

  group('display names', () {
    test('generated names are always valid and short', () {
      final rnd = Random(3);
      final seen = <String>{};
      for (var i = 0; i < 1000; i++) {
        final n = generateName(rnd);
        expect(validateName(n), n, reason: n);
        expect(n.length, lessThanOrEqualTo(16));
        seen.add(n);
      }
      expect(seen.length, greaterThan(100));
    });

    test('the same rules the server enforces', () {
      expect(validateName('  Sam   Lee '), 'Sam Lee');
      expect(validateName('Bob'), 'Bob');
      expect(validateName('sh1t'), isNull);
      expect(validateName('a'), isNull);
    });
  });
}
