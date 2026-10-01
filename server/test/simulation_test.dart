import 'dart:math';

import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Reads the confirmed moves out of a client's inbox: a move happened whenever
/// a `game_state` with no pending capture differs from the previous one.
/// De-duplicated by `rev`, so it survives the client reconnecting (new inbox).
class MoveLog {
  final List<Move> moves = [];
  final List<GameState> afterEach = [];
  GameState _prev = GameState.initial();
  int _lastRev = 0;

  void collect(TestClient c) {
    for (final m in c.ofType('game_state')) {
      final rev = m['rev'] as int;
      if (rev <= _lastRev) continue;
      _lastRev = rev;
      if (m['pending'] != null) continue;
      final s = decodeSnapshot(m['snapshot']);
      if (s == _prev && s.isOver == _prev.isOver) continue;
      final lm = m['lastMove'] as Map?;
      if (lm == null) continue;
      moves.add(decodeMove(lm));
      afterEach.add(s);
      _prev = s;
    }
  }
}

Future<GameState> playFullGame(int seed, {required bool disconnects}) async {
  Rules.placementRule = PlacementRule.symmetricOpening;
  final env = TestEnv(seed: seed);
  final rnd = Random(seed * 31 + 7);
  final (a, b) = await env.startedGame();
  final byTurn = <int, TestClient>{0: a, 1: b};
  final log = MoveLog();

  var plies = 0;
  while (plies < 900) {
    final s = a.state;
    if (s.isOver) break;
    final actor = byTurn[s.turn]!;
    await playOne(actor, rnd);
    log.collect(a);
    plies++;
    // people take a few seconds per move (and the flood limit counts real time)
    await env.advance(const Duration(seconds: 3));

    if (disconnects && plies == 11) {
      // the player who is NOT about to move loses their connection for 20 s
      final idle = byTurn[1 - a.state.turn]!;
      await idle.ch.drop();
      await env.advance(const Duration(seconds: 20));
      await idle.reconnect(resume: a.code);
      expect(idle.state, a.state, reason: 'full state sync after reconnecting');
    }
    if (disconnects && plies == 40 && !a.state.isOver) {
      // the player whose turn it is drops and comes back before acting
      final mover = byTurn[a.state.turn]!;
      await mover.ch.drop();
      await env.advance(const Duration(seconds: 30));
      await mover.reconnect(resume: a.code);
      expect(mover.state, a.state);
    }
    // the clients must never disagree with each other
    expect(b.state, a.state, reason: 'ply $plies');
  }
  log.collect(a);

  // the game really was played (not a trivially empty comparison)
  expect(log.moves.length, greaterThan(20), reason: 'seed $seed');
  expect(log.moves.any((m) => m.hasCapture), isTrue, reason: 'seed $seed had at least one capture');

  // a purely local replay of the same confirmed moves in the shared engine
  var local = GameState.initial();
  for (var i = 0; i < log.moves.length; i++) {
    expect(Rules.isLegal(local, log.moves[i]), isTrue, reason: 'move $i ${log.moves[i]}');
    local = Rules.apply(local, log.moves[i]);
    expect(local, log.afterEach[i], reason: 'after move $i the server and the engine agree');
  }
  final server = env.roomOf(a.code!).game!;
  expect(a.state, local);
  expect(server, local, reason: 'the server holds exactly the replayed state');
  expect(local.result?.winner, a.state.result?.winner);
  expect(local.result?.reason, a.state.result?.reason);
  expect(a.state.isOver, isTrue, reason: 'the game finished within the ply budget');
  expect(a.status, 'finished');
  expect(a.events(EventKind.gameOver).length, greaterThanOrEqualTo(1));
  return local;
}

void main() {
  test('full games through the server match a local replay of the same moves', () async {
    var winners = <int?>[];
    for (final seed in [1, 2, 3, 4]) {
      final end = await playFullGame(seed, disconnects: false);
      winners.add(end.result!.winner);
    }
    expect(winners.length, 4);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('with mid-game disconnects and reconnects the result is still identical', () async {
    for (final seed in [5, 6, 7]) {
      await playFullGame(seed, disconnects: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a game with timeouts, a capture choice and a rematch stays consistent', () async {
    Rules.placementRule = PlacementRule.symmetricOpening;
    final env = TestEnv(seed: 11);
    final rnd = Random(99);
    final (a, b) = await env.startedGame();
    for (var i = 0; i < 6; i++) {
      await playOne(a.state.turn == 0 ? a : b, rnd);
      await env.advance(const Duration(seconds: 3));
    }
    // one player goes silent for good: the server auto-plays once, then
    // disqualifies on the second timeout in a row
    final silent = a.state.turn;
    final other = silent == 0 ? b : a;
    for (var i = 0; i < 8 && !a.state.isOver; i++) {
      if (a.state.turn == silent) {
        await env.advance(const Duration(seconds: 125));
      } else {
        await playOne(other, rnd);
        await env.advance(const Duration(seconds: 3));
      }
    }
    expect(a.status, 'finished');
    expect(a.state.result!.winner, 1 - silent);
    expect(a.events(EventKind.timeout).length, 2);
    expect(a.events(EventKind.gameOver).last['data'], {'winner': 1 - silent, 'reason': 'disqualified'});
    expect(env.roomOf(a.code!).game, a.state);

    await a.send(Msg.offerRematch);
    await b.send(Msg.acceptRematch);
    expect(a.status, 'playing');
    expect(a.state, GameState.initial());
    for (var i = 0; i < 6; i++) {
      final actor = a.state.turn == a.seat ? a : b;
      await playOne(actor, rnd);
      await env.advance(const Duration(seconds: 3));
    }
    expect(b.state, a.state);
  });
}
