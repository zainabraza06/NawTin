import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Ends the game with a quick win for [a] (the player in seat 0).
Future<void> finishGame(TestEnv env, TestClient a) async {
  env.roomOf(a.code!).game = GameState.fromMasks(
    mask0: maskOf([0, 1, 3]),
    mask1: maskOf([12, 14, 20]),
  );
  await a.send(Msg.move, {'from': 3, 'to': 2});
  await a.send(Msg.capture, {'point': 20});
}

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  group('rematch', () {
    test('offer and accept: seats swap, fresh game, fresh stats', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await finishGame(env, a);
      expect(a.status, 'finished');
      final oldSeats = {a.uid: a.seat, b.uid: b.seat};
      expect(oldSeats, {a.uid: 0, b.uid: 1});

      await a.send(Msg.offerRematch);
      expect((b.room['rematch'] as Map)['offeredBy'], a.uid);
      expect(b.status, 'finished');
      await b.send(Msg.acceptRematch);

      expect(a.status, 'playing');
      expect(a.seat, 1, reason: 'the winner now moves second');
      expect(b.seat, 0, reason: 'the loser now moves first');
      expect((a.room['coinFlip'] as Map)['seat0'], b.uid);
      expect(a.state, GameState.initial());
      expect((a.game['stats'] as Map)['eaten'], [0, 0]);
      expect(a.game['timeouts'], [0, 0]);
      expect(a.clockInfo!['seat'], 0);
      expect((a.room['rematch'] as Map)['offeredBy'], isNull);

      // swaps back on the next rematch
      env.roomOf(a.code!).game = GameState.fromMasks(
        mask0: maskOf([0, 1, 3]),
        mask1: maskOf([12, 14, 20]),
      );
      await b.send(Msg.move, {'from': 3, 'to': 2});
      await b.send(Msg.capture, {'point': 20});
      await b.send(Msg.offerRematch);
      await a.send(Msg.acceptRematch);
      expect(a.seat, 0);
    });

    test('both offering at once starts the game', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await finishGame(env, a);
      await a.send(Msg.offerRematch);
      await b.send(Msg.offerRematch);
      expect(a.status, 'playing');
    });

    test('you cannot accept without an offer, or your own offer', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await b.send(Msg.acceptRematch);
      expect(b.lastErrorCode, ErrorCodes.rematchUnavailable, reason: 'game still on');
      await finishGame(env, a);
      await b.send(Msg.acceptRematch);
      expect(b.lastErrorCode, ErrorCodes.rematchUnavailable, reason: 'nobody offered');
      await a.send(Msg.offerRematch);
      await a.send(Msg.acceptRematch);
      expect(a.lastErrorCode, ErrorCodes.rematchUnavailable, reason: 'own offer');
      expect(a.status, 'finished');
    });

    test('no rematch after the opponent has left', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await finishGame(env, a);
      await b.send(Msg.leave);
      await a.send(Msg.offerRematch);
      expect(a.lastErrorCode, ErrorCodes.rematchUnavailable);
    });

    test('the room closes if nobody asks within 5 minutes', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await finishGame(env, a);
      await env.advance(const Duration(minutes: 4, seconds: 50));
      expect(a.status, 'finished');
      await env.advance(const Duration(seconds: 15));
      expect(a.status, 'closed');
      expect(b.status, 'closed');
      expect(env.server.manager.rooms, isEmpty);
    });
  });
}
