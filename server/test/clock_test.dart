import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

import 'support.dart';

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

const turn = Duration(seconds: 120);
const grace = Duration(milliseconds: 1500);

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  group('server-owned clock', () {
    test('every game_state carries the same absolute deadline for both players', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      final now = env.clock.now();
      expect(a.clockInfo!['deadline'], now.add(turn + grace).millisecondsSinceEpoch);
      expect(b.clockInfo, a.clockInfo);
      expect(a.last('game_state')!['ts'], now.millisecondsSinceEpoch, reason: 'ts lets clients correct clock offset');
    });

    test('each confirmed move restarts the clock for whoever acts next', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await env.advance(const Duration(seconds: 30));
      await a.send(Msg.place, {'to': 0});
      // the opening double: seat 0 still to act, with a fresh full clock
      expect(a.clockInfo!['seat'], 0);
      expect(a.clockInfo!['deadline'], env.clock.now().add(turn + grace).millisecondsSinceEpoch);
      await env.advance(const Duration(seconds: 10));
      await a.send(Msg.place, {'to': 1});
      expect(b.clockInfo!['seat'], 1);
      expect(b.clockInfo!['deadline'], env.clock.now().add(turn + grace).millisecondsSinceEpoch);
    });

    test('there is no pause online: the clock runs while a player is away', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      final deadline = a.clockInfo!['deadline'];
      await b.ch.drop();
      await env.advance(const Duration(seconds: 30));
      await b.reconnect(resume: a.code);
      expect(b.clockInfo!['deadline'], deadline, reason: 'same absolute deadline, not extended');
    });
  });

  group('timeouts', () {
    test('first timeout: the server plays a legal move for the player', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await env.advance(turn + grace + const Duration(milliseconds: 100));

      final t = a.events(EventKind.timeout).single;
      expect(t['data'], {'seat': 0, 'count': 1, 'auto': true, 'disqualified': false});
      expect(popCount(a.state.mask0), 1, reason: 'one placement was auto-played');
      expect(a.game['timeouts'], [1, 0]);
      expect(a.status, 'playing');
      expect(b.events(EventKind.timeout).length, 1);
      // seat 0 is still on its opening double, with a fresh clock
      expect(a.clockInfo!['seat'], 0);
    });

    test('a second timeout in a row disqualifies', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await env.advance(turn + grace + const Duration(milliseconds: 100));
      await env.advance(turn + grace + const Duration(milliseconds: 100));

      final t = a.events(EventKind.timeout);
      expect(t.length, 2);
      expect(t.last['data'], {'seat': 0, 'count': 2, 'auto': false, 'disqualified': true});
      expect(a.events(EventKind.gameOver).single['data'], {'winner': 1, 'reason': 'disqualified'});
      expect(b.status, 'finished');
      expect(b.state.result!.winner, 1);
    });

    test('a move the player makes themselves clears the warning', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await env.advance(turn + grace + const Duration(milliseconds: 100)); // lapse 1 (auto token 1)
      await a.send(Msg.place, {'to': _free(a)}); // own second opening token
      expect(a.game['timeouts'], [0, 0]);
      // seat 1 plays its opening, then seat 0 lapses again: only a first warning
      await b.send(Msg.place, {'to': _free(b)});
      await b.send(Msg.place, {'to': _free(b)});
      await env.advance(turn + grace + const Duration(milliseconds: 100));
      expect(a.status, 'playing');
      expect(a.game['timeouts'], [1, 0]);
    });

    test('a timeout while a capture is pending also picks the token to eat', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      setPosition(env, a, [0, 1], [20, 22], hand0: 5, hand1: 5);
      await a.send(Msg.place, {'to': 2}); // completes 0-1-2, waiting for a capture
      expect(a.game['pending'], isNotNull);
      await env.advance(turn + grace + const Duration(milliseconds: 100));

      final s = b.state;
      expect(s.mask0 & bit(2), isNot(0), reason: 'the chosen step stands');
      expect(popCount(s.mask1), 1, reason: 'a legal token was eaten for them');
      expect(b.events(EventKind.eaten).length, 1);
      final eaten = (b.events(EventKind.eaten).single['data'] as Map)['point'];
      expect([20, 22], contains(eaten));
      expect(a.game['pending'], isNull);
    });

    test('an auto-move never eats a protected token', () async {
      final env = TestEnv();
      final (a, _) = await env.startedGame();
      setPosition(env, a, [0, 1, 3, 5], [12, 13, 14, 20]);
      await a.send(Msg.move, {'from': 3, 'to': 2});
      await env.advance(turn + grace + const Duration(milliseconds: 100));
      expect(a.state.mask1, maskOf([12, 13, 14]), reason: 'only the loose token 20 was legal');
    });
  });
}

int _free(TestClient c) => Rules.stepMoves(c.state).first.to;
