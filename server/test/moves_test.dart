import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Puts the room into an exact position (white-box) so rules can be probed.
void setPosition(TestEnv env, TestClient c, List<int> seat0, List<int> seat1,
    {int hand0 = 0, int hand1 = 0, int turn = 0, int placesLeft = 1}) {
  env.roomOf(c.code!).game = GameState.fromMasks(
    mask0: maskOf(seat0),
    mask1: maskOf(seat1),
    hand0: hand0,
    hand1: hand1,
    turn: turn,
    placesLeft: placesLeft,
  );
}

List<String> kinds(TestClient c, {int from = 0}) =>
    c.events().skip(from).map((e) => e['kind'] as String).toList();

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  group('illegal moves are rejected with a typed error', () {
    test('acting out of turn, in the lobby, or after the game', () async {
      final env = TestEnv();
      final (host, guest) = await env.lobby();
      await host.send(Msg.place, {'to': 0});
      expect(host.lastErrorCode, ErrorCodes.gameNotActive);

      await host.send(Msg.start);
      final first = host.seat == 0 ? host : guest;
      final second = host.seat == 0 ? guest : host;
      await second.send(Msg.place, {'to': 0});
      expect(second.lastErrorCode, ErrorCodes.notYourTurn);
      expect(first.state, GameState.initial(), reason: 'nothing changed');
    });

    test('occupied point, bad numbers and wrong phase', () async {
      final env = TestEnv();
      final (first, _) = await env.startedGame();
      await first.send(Msg.place, {'to': 0});
      expect(first.state.mask0, bit(0));
      await first.send(Msg.place, {'to': 0});
      expect(first.lastErrorCode, ErrorCodes.illegalMove);
      await first.send(Msg.place, {'to': 99});
      expect(first.lastErrorCode, ErrorCodes.badRequest);
      await first.send(Msg.place, {'to': 'nine'});
      expect(first.lastErrorCode, ErrorCodes.badRequest);
      await first.send(Msg.place, {});
      expect(first.lastErrorCode, ErrorCodes.badRequest);
      await first.send(Msg.move, {'from': 0, 'to': 1});
      expect(first.lastErrorCode, ErrorCodes.wrongPhase, reason: 'still placing');
      await first.send(Msg.capture, {'point': 3});
      expect(first.lastErrorCode, ErrorCodes.noCapturePending);
      expect(first.state.mask0, bit(0), reason: 'only the one valid placement happened');
    });

    test('sliding rules: your own token, one step along a line, onto an empty point', () async {
      final env = TestEnv();
      final (first, _) = await env.startedGame();
      setPosition(env, first, [0, 4, 18], [12, 14, 20]);
      await first.send(Msg.place, {'to': 9});
      expect(first.lastErrorCode, ErrorCodes.wrongPhase, reason: 'all tokens are placed');
      for (final bad in [
        {'from': 12, 'to': 13}, // opponent's token
        {'from': 0, 'to': 2}, // two steps
        {'from': 0, 'to': 9}, // not on a line from 0
        {'from': 5, 'to': 6}, // nothing there
      ]) {
        await first.send(Msg.move, bad);
        expect(first.lastErrorCode, ErrorCodes.illegalMove, reason: '$bad');
      }
      await first.send(Msg.move, {'from': 0, 'to': 1});
      expect(first.state.mask0 & bit(1), isNot(0));
    });
  });

  group('MACHYAS is a two-step turn on the server', () {
    Future<(TestClient, TestClient)> setup(TestEnv env) async {
      final (a, b) = await env.startedGame();
      setPosition(env, a, [0, 1], [20, 22], hand0: 5, hand1: 5);
      return (a, b);
    }

    test('a line asks for a capture; the opponent cannot interfere; the clock keeps running', () async {
      final env = TestEnv();
      final (a, b) = await setup(env);
      final deadline = a.clockInfo!['deadline'];
      await a.send(Msg.place, {'to': 2});

      final need = a.events(EventKind.captureRequired);
      expect(need.length, 1);
      expect((need.single['data'] as Map)['targets'], [20, 22]);
      expect(b.events(EventKind.captureRequired), isEmpty, reason: 'only the actor is asked');
      final pending = b.game['pending'] as Map;
      expect(pending['to'], 2);
      expect(pending['targets'], [20, 22]);
      expect(b.state.mask0, maskOf([0, 1]), reason: 'the step is not applied yet');

      await b.send(Msg.place, {'to': 9});
      expect(b.lastErrorCode, ErrorCodes.notYourTurn);
      await a.send(Msg.place, {'to': 5});
      expect(a.lastErrorCode, ErrorCodes.capturePending);
      expect(a.clockInfo!['deadline'], deadline, reason: 'the turn clock did not restart');
    });

    test('capture applies the step and the eaten token together, in order', () async {
      final env = TestEnv();
      final (a, b) = await setup(env);
      await a.send(Msg.place, {'to': 2});
      await a.send(Msg.capture, {'point': 5});
      expect(a.lastErrorCode, ErrorCodes.illegalCapture, reason: 'not an opponent token');
      final before = a.events().length;
      await a.send(Msg.capture, {'point': 20});

      expect(kinds(a, from: before), [EventKind.placed, EventKind.machyas, EventKind.eaten]);
      final s = a.state;
      expect(s.mask0, maskOf([0, 1, 2]));
      expect(s.mask1, maskOf([22]));
      expect(a.game['pending'], isNull);
      expect((a.game['stats'] as Map)['eaten'], [1, 0]);
      expect((a.game['stats'] as Map)['lines'], [1, 0]);
      expect(a.clockInfo!['seat'], 1);
      expect(b.state, s, reason: 'both players see the same confirmed state');
      final lastEvent = a.events().last;
      expect(a.game['rev'], lastEvent['rev'], reason: 'the snapshot closes the same batch');
    });

    test('protected tokens cannot be eaten, unless every token is protected', () async {
      final env = TestEnv();
      final (a, _) = await env.startedGame();
      setPosition(env, a, [0, 1, 3, 5], [12, 13, 14, 20]);
      await a.send(Msg.move, {'from': 3, 'to': 2});
      expect((a.events(EventKind.captureRequired).last['data'] as Map)['targets'], [20]);
      await a.send(Msg.capture, {'point': 13});
      expect(a.lastErrorCode, ErrorCodes.illegalCapture, reason: '13 is in a finished line');
      await a.send(Msg.capture, {'point': 20});
      expect(a.state.mask1, maskOf([12, 13, 14]));

      // all opponent tokens protected: anything goes
      final env2 = TestEnv();
      final (c, _) = await env2.startedGame();
      setPosition(env2, c, [0, 1, 3, 5], [12, 13, 14, 16, 17, 18]);
      await c.send(Msg.move, {'from': 3, 'to': 2});
      expect(((c.events(EventKind.captureRequired).last['data'] as Map)['targets'] as List).length, 6);
      await c.send(Msg.capture, {'point': 13});
      expect(c.lastErrorCode, isNot(ErrorCodes.illegalCapture));
      expect(c.state.mask1 & bit(13), 0);
    });
  });

  group('calls', () {
    test('BEGI is announced once, then swings are plain machyas', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      setPosition(env, a, [6, 7, 9, 17, 2], [12, 13, 14, 19, 23]);
      await a.send(Msg.move, {'from': 2, 'to': 1});
      await a.send(Msg.capture, {'point': 19});
      final begi = a.events(EventKind.begi);
      expect(begi.length, 1);
      expect((begi.single['data'] as Map)['ready'], false);
      expect(begi.single['seat'], 0);

      await b.send(Msg.move, {'from': 23, 'to': 22});
      await a.send(Msg.move, {'from': 1, 'to': 0});
      await a.send(Msg.capture, {'point': 22});
      expect(a.events(EventKind.begi).length, 1, reason: 'the swing is only a machyas');
      expect(a.events(EventKind.machyas).length, 2);
    });

    test('PHUTAS becomes available for the mover only, and the button clears it', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      setPosition(env, a, [0], [20], hand0: 5, hand1: 5);
      await a.send(Msg.place, {'to': 1});
      expect(a.events(EventKind.phutasAvailable).length, 1);
      expect(a.game['phutas'], {'seat': 0, 'lines': 1});

      await b.send(Msg.pressPhutas);
      expect(b.events(EventKind.phutasPressed), isEmpty, reason: 'not their threat');
      await a.send(Msg.pressPhutas);
      expect(a.events(EventKind.phutasPressed).length, 1);
      expect(b.events(EventKind.phutasPressed).length, 1, reason: 'the opponent sees the warning');
      expect(a.game['phutas'], isNull);
    });

    test('presets only: an emote carries a known id', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await a.send(Msg.emote, {'id': 'nice_one'});
      expect(b.events(EventKind.emote).single['data'], {'seat': 0, 'id': 'nice_one'});
      await env.advance(const Duration(seconds: 4));
      await a.send(Msg.emote, {'id': 'free text here'});
      expect(a.lastErrorCode, ErrorCodes.emoteUnknown);
    });
  });

  group('game over', () {
    test('reducing the opponent to two tokens ends the game for everyone', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      setPosition(env, a, [0, 1, 3], [12, 14, 20]);
      await a.send(Msg.move, {'from': 3, 'to': 2});
      await a.send(Msg.capture, {'point': 20});
      final over = a.events(EventKind.gameOver).single;
      expect(over['data'], {'winner': 0, 'reason': 'tokensReduced'});
      expect(b.events(EventKind.gameOver).length, 1);
      expect(a.status, 'finished');
      expect(a.state.result!.winner, 0);
      expect(a.clockInfo, isNull, reason: 'no clock once the game is over');
      await b.send(Msg.move, {'from': 12, 'to': 13});
      expect(b.lastErrorCode, ErrorCodes.gameNotActive);
    });
  });

  group('sequence numbers (idempotency)', () {
    test('a resent message is applied once and acknowledged', () async {
      final env = TestEnv();
      final (a, _) = await env.startedGame();
      await a.send(Msg.place, {'to': 0});
      final used = a.seq; // the number that placement was sent with
      final revAfter = a.game['rev'];
      await a.send(Msg.place, {'to': 0}, used); // the same seq again
      await a.send(Msg.place, {'to': 4}, used); // even with different content
      expect(a.errors(), isEmpty);
      expect(a.events(EventKind.placed).length, 1);
      expect(a.state.mask0, bit(0));
      expect(a.game['rev'], revAfter);
      expect(a.ofType(Msg.ack).length, 2);
      expect(a.last('game_state')!['ack'], used);
    });

    test('a gap is refused and the client is resynced', () async {
      final env = TestEnv();
      final (a, _) = await env.startedGame();
      await a.send(Msg.place, {'to': 0});
      final used = a.seq;
      final state = a.state;
      a.clearInbox();
      await a.send(Msg.place, {'to': 4}, used + 2); // used + 1 was lost
      expect(a.lastErrorCode, ErrorCodes.seqGap);
      expect(a.last('room_state'), isNotNull);
      expect(a.last('game_state'), isNotNull);
      expect(a.state, state, reason: 'the out-of-order message was not applied');
      await a.send(Msg.place, {'to': 4}, used + 1); // the missing one arrives
      expect(a.state.mask0, maskOf([0, 4]));
    });

    test('a sequenced message without a number is a bad request', () async {
      final env = TestEnv();
      final (a, _) = await env.startedGame();
      a.ch.clientSend({'v': 1, 't': 'place', 'to': 0});
      await pump();
      expect(a.lastErrorCode, ErrorCodes.badRequest);
      expect(a.state, GameState.initial());
    });
  });
}
