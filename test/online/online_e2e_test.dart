import 'dart:math';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:naw_tin_server/naw_tin_server.dart' as srv;
import 'package:nawtin/core/ai/ai.dart' as app_ai;
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/online/online_controller.dart';
import 'package:nawtin/features/online/online_state.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/services/ai_provider.dart';
import 'package:nawtin/services/online/online_config.dart';
import 'package:nawtin/services/online/online_service.dart';
import 'package:nawtin/services/prefs_store.dart';
import 'package:nawtin/services/turn_clock.dart';

import 'support.dart';

/// One phone: its own app container, storage and network path to the server.
class Phone {
  Phone(this.world, this.uid, this.name, {int skewMs = 0, MemoryPrefsStore? store})
      : store = store ?? MemoryPrefsStore() {
    this.store.write('debug.uid', uid);
    transport = InProcessTransport(world.server, 'ip-$uid');
    c = ProviderContainer(overrides: [
      prefsStoreProvider.overrideWithValue(this.store),
      onlineConfigProvider.overrideWithValue(OnlineConfig.parse('ws://localhost:8080/ws', release: false)),
      onlineTransportProvider.overrideWithValue(transport),
      onlineSchedulerProvider.overrideWithValue(ClockScheduler(world.clock, skewMs: skewMs)),
    ]);
    c.listen(onlineControllerProvider, (_, __) {});
    c.read(onlineProfileProvider.notifier).setName(name);
  }

  final World world;
  final String uid;
  final String name;
  final MemoryPrefsStore store;
  late final InProcessTransport transport;
  late final ProviderContainer c;

  OnlineGameController get ctl => c.read(onlineControllerProvider.notifier);
  OnlineState get s => c.read(onlineControllerProvider);
  GameState get state => s.game!.state;

  Future<void> connect() async {
    await ctl.connect();
    await pump();
  }

  /// The phone loses power / the app is killed: the container disappears, the
  /// storage on the device stays.
  void kill() => c.dispose();
}

class World {
  World() {
    Rules.placementRule = PlacementRule.symmetricOpening;
    clock = srv.FakeClock();
    server = srv.NawTinServer(
      config: const srv.ServerConfig(testAuth: true),
      verifier: srv.TestTokenVerifier(),
      clock: clock,
      ai: DirectAiService(),
      random: Random(5),
      log: (e, [f = const {}]) {},
    );
  }

  late final srv.FakeClock clock;
  late final srv.NawTinServer server;

  Future<void> advance(Duration d) async {
    var left = d;
    while (left > Duration.zero) {
      final step = left > const Duration(seconds: 1) ? const Duration(seconds: 1) : left;
      clock.advance(step);
      await pump(4);
      left -= step;
    }
  }

  srv.Room room(String code) => server.manager.rooms[code]!;

  /// Puts the server's game into an exact position and resyncs everyone.
  Future<void> setPosition(String code, GameState g) async {
    final r = room(code);
    r.game = g;
    for (final p in r.players) {
      r.sendGameState(p);
    }
    await pump();
  }

  /// Two phones in a started game. Returns (first mover, second mover).
  Future<(Phone, Phone)> startedGame({int skewA = 0, int skewB = 0}) async {
    final a = Phone(this, 'alice01', 'Alice', skewMs: skewA);
    final b = Phone(this, 'bobby02', 'Bobby', skewMs: skewB);
    await a.connect();
    await b.connect();
    a.ctl.createRoom();
    await pump();
    b.ctl.joinRoom(a.s.roomCode!.toLowerCase());
    await pump();
    b.ctl.setReady(true);
    await pump();
    a.ctl.start();
    await pump();
    expect(a.s.inGame && b.s.inGame, isTrue);
    return a.s.mySeat == 0 ? (a, b) : (b, a);
  }
}

void main() {
  group('a whole online game between two controllers and the real server', () {
    test('create, join by sloppy code, ready, start: both see the same lobby and game', () async {
      final w = World();
      final (first, second) = await w.startedGame();
      expect(first.s.mySeat, 0);
      expect(second.s.mySeat, 1);
      expect(first.s.room!.coinFlipSeat0, first.uid);
      expect(second.s.room!.coinFlipSeat0, first.uid);
      expect(first.s.opponent!.name, second.name);
      expect(first.s.game!.state, GameState.initial());
      expect(second.s.game!.state, first.s.game!.state);
      expect(first.s.myTurn, isTrue);
      expect(second.s.myTurn, isFalse);
    });

    test('moves are mirrored; the opponent gets an animation derived from the confirmed event', () async {
      final w = World();
      final (a, b) = await w.startedGame();
      a.ctl.place(9);
      await pump();
      expect(a.s.optimistic, isNull, reason: 'confirmed by the server');
      expect(b.state, a.state);
      expect(b.state.mask0, bit(9));
      expect(b.s.fxSerial, 1);
      expect(b.s.lastResult!.move, const Move.place(9));
      expect(b.s.lastResult!.after, b.state);
      // out-of-turn tries do nothing on the wire
      b.ctl.place(3);
      await pump();
      expect(b.state, a.state);
      a.ctl.place(10);
      await pump();
      b.ctl.place(11);
      await pump();
      b.ctl.place(12);
      await pump();
      expect(a.state.mask1, maskOf([11, 12]));
      expect(a.state, b.state);
    });

    test('Machyas is two steps: both see the pending capture, only the actor can answer', () async {
      final w = World();
      final (a, b) = await w.startedGame();
      await w.setPosition(a.s.roomCode!,
          GameState.fromMasks(mask0: maskOf([0, 1]), mask1: maskOf([20, 22]), hand0: 5, hand1: 5));
      a.ctl.place(2);
      await pump();
      expect(a.s.game!.pendingStep, const Move.place(2));
      expect(b.s.game!.pendingStep, const Move.place(2));
      expect(b.s.game!.pendingTargets, maskOf([20, 22]));
      expect(a.state.mask0, maskOf([0, 1]), reason: 'not applied until the capture');
      b.ctl.capture(20); // not b's turn
      await pump();
      expect(b.s.game!.pendingStep, isNotNull);
      a.ctl.capture(5); // not a victim
      await pump();
      expect(a.s.error!.code, ErrorCodes.illegalCapture);
      a.ctl.capture(22);
      await pump();
      expect(a.state.mask0, maskOf([0, 1, 2]));
      expect(a.state.mask1, maskOf([20]));
      expect(b.state, a.state);
      expect(a.s.game!.pendingStep, isNull);
    });
  });

  group('both phones show the same clock, whatever their own clocks say', () {
    test('one phone 7 s fast, one 3 s slow', () async {
      final w = World();
      final (a, b) = await w.startedGame(skewA: 7000, skewB: -3000);
      await w.advance(const Duration(seconds: 12));
      // each phone has been pinging, so both have measured their offset
      final ra = a.ctl.remainingMs();
      final rb = b.ctl.remainingMs();
      expect((ra - rb).abs(), lessThan(50));
      expect(ra, closeTo(121500 - 12000, 60));
      await w.advance(const Duration(seconds: 30));
      expect((a.ctl.remainingMs() - b.ctl.remainingMs()).abs(), lessThan(50));
      expect(a.ctl.remainingMs(), closeTo(121500 - 42000, 60));
    });
  });

  group('connection loss', () {
    test('a dropped phone reconnects by itself, resyncs fully, and play continues', () async {
      final w = World();
      final (a, b) = await w.startedGame();
      a.ctl.place(9);
      await pump();
      a.transport.dropAll();
      await pump();
      expect(b.s.opponentReconnectDeadlineMs, isNotNull, reason: 'the opponent sees "reconnecting..."');
      expect(b.s.opponent!.connected, isFalse);
      expect(a.s.conn.phase, ConnPhase.reconnecting);

      await w.advance(const Duration(seconds: 3)); // backoff, then the new connection
      expect(a.s.conn.isOnline, isTrue);
      expect(a.state, b.state, reason: 'a full snapshot, not a replay');
      expect(b.s.opponentReconnectDeadlineMs, isNull);
      expect(b.s.opponent!.connected, isTrue);
      expect(b.s.events.map((e) => e.kind), containsAll(['disconnected', 'reconnected']));

      // the sequence numbers still line up: both can keep playing
      a.ctl.place(10);
      await pump();
      b.ctl.place(11);
      await pump();
      expect(b.s.error, isNull);
      expect(a.state, b.state);
      expect(a.state.mask1, bit(11));
    });

    test('an unacknowledged move typed while the line is down goes out after the resync', () async {
      final w = World();
      final (a, b) = await w.startedGame();
      a.transport.dropAll();
      await pump();
      a.ctl.place(9); // typed while offline: queued
      await pump();
      expect(b.state.mask0, 0);
      await w.advance(const Duration(seconds: 3));
      expect(b.state.mask0, bit(9), reason: 'delivered once, in order, after reconnecting');
      expect(a.state, b.state);
    });

    test('backgrounding and closing the app never forfeit: the 45 s window applies', () async {
      final w = World();
      final (a, b) = await w.startedGame();
      a.ctl.onLifecycle(AppLifecycleState.paused);
      a.ctl.onLifecycle(AppLifecycleState.detached);
      a.kill(); // the OS ends the app
      await pump();
      await w.advance(const Duration(seconds: 30));
      expect(b.s.room!.status, 'playing');
      expect(b.s.game!.isOver, isFalse);
      expect(b.s.opponentReconnectDeadlineMs, isNotNull);
      await w.advance(const Duration(seconds: 20));
      expect(b.s.game!.isOver, isTrue);
      expect(b.s.game!.endReason, EndReason.abandoned, reason: 'abandoned after the window, not "forfeit"');
      expect(b.state.result!.winner, b.s.mySeat);
    });

    test('app killed, then reopened inside the window: "Rejoin game" restores the match', () async {
      final w = World();
      final (a, b) = await w.startedGame();
      a.ctl.place(9);
      await pump();
      final saved = a.store; // survives the app being killed
      final uid = a.uid;
      a.kill();
      await pump();
      await w.advance(const Duration(seconds: 20));

      final a2 = Phone(w, uid, 'Alice', store: saved);
      expect(a2.s.rejoinCode, isNotNull, reason: 'the home screen offers "Rejoin game"');
      await a2.connect(); // hello carries resume=<room>
      await pump();
      expect(a2.s.inGame, isTrue);
      expect(a2.state, b.state);
      expect(b.s.opponent!.connected, isTrue);
      // the fresh process restarted its counter at 0: it must catch up, not be ignored
      a2.ctl.place(10);
      await pump();
      expect(b.state.mask0, maskOf([9, 10]));
      expect(a2.s.error, isNull);
    });

    test('the same account on a second device takes over; the first stops (no fighting)', () async {
      final w = World();
      final (a, b) = await w.startedGame();
      final second = Phone(w, a.uid, 'Alice');
      await second.connect();
      await pump();
      expect(a.s.conn.stopReason, StopReason.replaced);
      expect(second.s.inGame, isTrue, reason: 'the new device takes over the live game');
      expect(second.state, b.state);
      expect(b.s.opponent!.connected, isTrue, reason: 'a swap is not a disconnect');
      second.ctl.place(Rules.stepMoves(second.state).first.to);
      await pump();
      expect(second.s.error, isNull, reason: 'and can play on');
    });
  });

  group('leaving', () {
    test('the confirmed Leave button forfeits at once and forgets the room', () async {
      final w = World();
      final (a, b) = await w.startedGame();
      b.ctl.leaveGame();
      await pump();
      expect(a.s.game!.isOver, isTrue);
      expect(a.s.game!.endReason, EndReason.forfeit);
      expect(a.state.result!.winner, a.s.mySeat);
      expect(b.s.rejoinCode, isNull);
      expect(a.s.rejoinCode, isNull, reason: 'a finished game is not rejoinable');
    });

    test('rematch swaps seats and makes the new game rejoinable', () async {
      final w = World();
      final (a, b) = await w.startedGame();
      await w.setPosition(a.s.roomCode!, GameState.fromMasks(mask0: maskOf([0, 1, 3]), mask1: maskOf([12, 14, 20])));
      a.ctl.move(3, 2);
      await pump();
      a.ctl.capture(20);
      await pump();
      expect(a.s.game!.isOver, isTrue);
      expect(a.s.rejoinCode, isNull);
      a.ctl.offerRematch();
      await pump();
      expect(b.s.room!.rematchOfferedBy, a.uid);
      b.ctl.acceptRematch();
      await pump();
      expect(a.s.mySeat, 1);
      expect(b.s.mySeat, 0);
      expect(b.state, GameState.initial());
      expect(a.s.rejoinCode, isNotNull);
    });
  });

  group('offline and online count timeouts the same way: only in a row', () {
    /// Runs a story online and returns whether the lapsing player was disqualified.
    Future<bool> online({required bool ownMoveBetween}) async {
      final w = World();
      final (a, b) = await w.startedGame();
      await w.advance(const Duration(seconds: 125)); // a lapses (auto-plays token 1)
      if (ownMoveBetween) {
        a.ctl.place(_free(a)); // a plays the rest of the opening turn themselves
        await pump();
        b.ctl.place(_free(b));
        await pump();
        b.ctl.place(_free(b));
        await pump();
      }
      await w.advance(const Duration(seconds: 125)); // a lapses again
      return a.s.game!.isOver && a.s.game!.endReason == EndReason.disqualified;
    }

    /// The same story in the offline two-player game.
    Future<bool> offline({required bool ownMoveBetween}) async {
      final c = ProviderContainer(overrides: [aiServiceProvider.overrideWithValue(app_ai.DirectAiService())]);
      addTearDown(c.dispose);
      c.read(setupProvider.notifier).setMode(GameMode.friend);
      final game = c.read(gameControllerProvider.notifier)..newGame();
      GameUiState ui() => c.read(gameControllerProvider);
      Future<void> lapse() async {
        c.read(clockProvider.notifier).advance(120000);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (ui().status == GameStatus.animating) game.finishAnimation(ui().fxSerial);
      }

      void play() {
        game.tapPoint(Rules.stepMoves(ui().game).first.to);
        game.finishAnimation(ui().fxSerial);
      }

      await lapse();
      if (ownMoveBetween) {
        play();
        play();
        play();
      }
      await lapse();
      return ui().isOver && ui().game.result?.reason == GameEndReason.disqualified;
    }

    test('two lapses in a row disqualify, in both modes', () async {
      expect(await online(ownMoveBetween: false), isTrue);
      expect(await offline(ownMoveBetween: false), isTrue);
    });

    test('a move of your own in between clears the count, in both modes', () async {
      expect(await online(ownMoveBetween: true), isFalse);
      expect(await offline(ownMoveBetween: true), isFalse);
    });
  });
}

int _free(Phone p) => Rules.stepMoves(p.state).first.to;
