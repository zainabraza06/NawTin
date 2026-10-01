import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:naw_tin_server/naw_tin_server.dart' as srv;
import 'package:nawtin/features/online/online_controller.dart';
import 'package:nawtin/features/online/online_state.dart';
import 'package:nawtin/services/online/online_config.dart';
import 'package:nawtin/services/prefs_store.dart';

import 'support.dart';

class _Rig {
  _Rig({String? stored, int skewMs = 0})
      : clock = srv.FakeClock(),
        transport = ScriptedTransport(),
        store = MemoryPrefsStore() {
    if (stored != null) store.write('online.room', stored);
    c = ProviderContainer(overrides: [
      prefsStoreProvider.overrideWithValue(store),
      onlineConfigProvider.overrideWithValue(OnlineConfig.parse('ws://localhost:8080/ws', release: false)),
      onlineTransportProvider.overrideWithValue(transport),
      onlineSchedulerProvider.overrideWithValue(ClockScheduler(clock, skewMs: skewMs)),
    ]);
    addTearDown(c.dispose);
    ctl = c.read(onlineControllerProvider.notifier);
    c.listen(onlineControllerProvider, (_, __) {});
  }

  final srv.FakeClock clock;
  final ScriptedTransport transport;
  final MemoryPrefsStore store;
  late final ProviderContainer c;
  late final OnlineGameController ctl;

  OnlineState get s => c.read(onlineControllerProvider);
  ScriptedChannel get ch => transport.last;

  Future<void> advance(Duration d) async {
    clock.advance(d);
    await pump();
  }

  Future<void> online({Map<String, Object?>? resume, String uid = 'me'}) async {
    await ctl.connect();
    await pump();
    ch.serverSend({'t': 'welcome', 'ts': clock.now().millisecondsSinceEpoch, 'userId': uid, if (resume != null) 'resume': resume});
    await pump();
  }

  Future<void> server(Map<String, Object?> m) async {
    ch.serverSend(m);
    await pump();
  }

  Map<String, Object?> room({
    String status = 'lobby',
    String code = 'K7TQ3M',
    int mySeat = 0,
    bool oppConnected = true,
    int lastSeq = 0,
    String host = 'me',
    String? rematchBy,
  }) =>
      {
        't': 'room_state',
        'code': code,
        'status': status,
        'expiresAt': clock.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        'host': host,
        'players': [
          {'userId': 'me', 'name': 'Me', 'avatar': 1, 'connected': true, 'ready': true, 'seat': status == 'playing' || status == 'finished' ? mySeat : null, 'pingMs': 30, 'lastSeq': lastSeq},
          {'userId': 'opp', 'name': 'Opp', 'avatar': 2, 'connected': oppConnected, 'ready': true, 'seat': status == 'playing' || status == 'finished' ? 1 - mySeat : null, 'pingMs': 50, 'lastSeq': 0},
        ],
        'rules': {'placementRule': 'symmetricOpening', 'turnSeconds': 120, 'reconnectSeconds': 45},
        'coinFlip': status == 'lobby' ? null : {'seat0': mySeat == 0 ? 'me' : 'opp'},
        'rematch': {'offeredBy': rematchBy},
        'rev': 1,
      };

  Map<String, Object?> game(
    GameState g, {
    int rev = 2,
    Move? pending,
    List<int> targets = const [],
    ({int seat, Move move})? last,
    int deadlineFromNow = 120000,
    int clockSeat = 0,
    int? ts,
  }) =>
      {
        't': 'game_state',
        'rev': rev,
        'ts': ts ?? clock.now().millisecondsSinceEpoch,
        'snapshot': encodeSnapshot(g),
        'pending': pending == null ? null : {'from': pending.from, 'to': pending.to, 'targets': targets},
        'clock': {'seat': clockSeat, 'deadline': clock.now().millisecondsSinceEpoch + deadlineFromNow, 'totalMs': 120000, 'graceMs': 1500},
        'timeouts': [0, 0],
        'stats': {'eaten': [0, 0], 'lines': [0, 0], 'swings': [0, 0]},
        'phutas': null,
        'lastMove': last == null ? null : {'seat': last.seat, ...encodeMove(last.move)},
      };
}

void main() {
  group('lobby', () {
    test('a room_state becomes a lobby view and the room is remembered for "Rejoin game"', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room());
      expect(r.s.room!.code, 'K7TQ3M');
      expect(r.s.room!.status, 'lobby');
      expect(r.s.isHost, isTrue);
      expect(r.s.me!.name, 'Me');
      expect(r.s.opponent!.name, 'Opp');
      expect(r.s.opponent!.connected, isTrue);
      expect(r.s.room!.turnSeconds, 120);
      expect(r.s.room!.expiresAtMs, isNotNull);
      expect(r.s.rejoinCode, 'K7TQ3M');
      expect(r.store.read('online.room'), 'K7TQ3M');
    });

    test('the saved room is cleared when the game ends or the room closes', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      expect(r.s.rejoinCode, 'K7TQ3M');
      await r.server(r.room(status: 'finished'));
      expect(r.s.rejoinCode, isNull);
      expect(r.store.read('online.room'), '');
      await r.server(r.room(status: 'playing'));
      expect(r.s.rejoinCode, 'K7TQ3M', reason: 'a rematch makes it rejoinable again');
      await r.server(r.room(status: 'closed'));
      expect(r.s.rejoinCode, isNull);
      expect(r.s.roomEnd, RoomEnd.closed);
    });

    test('game_over clears the saved room too', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      await r.server({'t': 'event', 'rev': 5, 'kind': 'game_over', 'seat': null, 'data': {'winner': 0, 'reason': 'forfeit'}});
      expect(r.store.read('online.room'), '');
    });

    test('the profile name is validated like on the server and saved', () async {
      final r = _Rig();
      final p = r.c.read(onlineProfileProvider.notifier);
      expect(validateName(r.c.read(onlineProfileProvider).name), isNotNull, reason: 'a valid default is generated');
      expect(p.setName('sh1t'), isFalse);
      expect(p.setName('x'), isFalse);
      expect(p.setName('Zainab'), isTrue);
      expect(r.c.read(onlineProfileProvider).name, 'Zainab');
      expect(r.store.read('online.profile'), contains('Zainab'));
    });
  });

  group('welcome and rejoin', () {
    test('a stored room is offered at start and sent as resume in hello', () async {
      final r = _Rig(stored: 'K7TQ3M');
      expect(r.s.rejoinCode, 'K7TQ3M');
      await r.online(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      expect(r.ch.hello!['resume'], 'K7TQ3M');
      expect(r.s.rejoinCode, 'K7TQ3M');
      expect(r.s.userId, 'me');
    });

    test('if the server no longer has the room the saved id is dropped', () async {
      final r = _Rig(stored: 'K7TQ3M');
      await r.online(); // welcome without a resume entry
      expect(r.s.rejoinCode, isNull);
      expect(r.store.read('online.room'), '');
    });

    test('mid-room, a server that forgot the room shows "room ended"', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      r.ch.networkDrop();
      await pump();
      for (var i = 0; i < 60 && r.transport.channels.length < 2; i++) {
        await r.advance(const Duration(milliseconds: 250));
      }
      r.ch.serverSend({'t': 'welcome', 'ts': r.clock.now().millisecondsSinceEpoch, 'userId': 'me'});
      await pump();
      expect(r.s.roomEnd, RoomEnd.closed);
      expect(r.s.game, isNull);
    });

    test('rejoin() asks for the saved room without restarting the sequence', () async {
      final r = _Rig(stored: 'K7TQ3M');
      await r.online(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      await r.server(r.room(status: 'playing', lastSeq: 4));
      r.ctl.rejoin();
      expect(r.ch.of('join_room').last['code'], 'K7TQ3M');
      r.ctl.setReady(true);
      expect(r.ch.of('ready').last['seq'], 5);
    });
  });

  group('debug server address', () {
    test('a typed address is saved and becomes the server config (debug builds)', () async {
      final store = MemoryPrefsStore();
      final c = ProviderContainer(overrides: [prefsStoreProvider.overrideWithValue(store)]);
      addTearDown(c.dispose);
      expect(c.read(debugServerProvider), isNull);
      c.read(debugServerProvider.notifier).set('ws://192.168.1.20:8080/ws');
      expect(c.read(onlineConfigProvider).url!.host, '192.168.1.20');
      expect(store.read('debug.server'), 'ws://192.168.1.20:8080/ws');
      // it survives a restart
      final c2 = ProviderContainer(overrides: [prefsStoreProvider.overrideWithValue(store)]);
      addTearDown(c2.dispose);
      expect(c2.read(onlineConfigProvider).url!.host, '192.168.1.20');
      // an unsafe or empty value falls back safely
      c2.read(debugServerProvider.notifier).set('http://nope');
      expect(c2.read(onlineConfigProvider).isAvailable, isFalse);
      c2.read(debugServerProvider.notifier).set('');
      expect(c2.read(debugServerProvider), isNull);
    });
  });

  group('actions and guards', () {
    test('creating or joining while offline says so, nothing is sent', () async {
      final r = _Rig();
      r.ctl.createRoom();
      expect(r.s.error!.code, 'not_connected');
      r.ctl.joinRoom('K7TQ3M');
      expect(r.transport.channels, isEmpty);
    });

    test('a badly typed code is caught locally; a sloppy one is cleaned up', () async {
      final r = _Rig();
      await r.online();
      r.ctl.joinRoom('abc');
      expect(r.s.error!.code, ErrorCodes.roomNotFound);
      expect(r.ch.of('join_room'), isEmpty);
      r.ctl.joinRoom(' k7t-q3m ');
      expect(r.ch.of('join_room').single['code'], 'K7TQ3M');
    });

    test('moves are only sent on my turn, and show an optimistic highlight until confirmed', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing', mySeat: 1));
      await r.server(r.game(GameState.initial()));
      r.ctl.place(9); // seat 0 is to move: not mine
      expect(r.ch.of('place'), isEmpty);
      expect(r.s.optimistic, isNull);

      await r.server(r.room(status: 'playing', mySeat: 0));
      r.ctl.place(9);
      expect(r.ch.of('place').single['to'], 9);
      expect(r.s.optimistic, const Move.place(9));
      // the server confirms: the highlight goes, the server state is what we show
      final after = Rules.apply(GameState.initial(), const Move.place(9));
      await r.server(r.game(after, rev: 3, last: (seat: 0, move: const Move.place(9))));
      expect(r.s.optimistic, isNull);
      expect(r.s.game!.state, after);
    });

    test('a rejected move clears the highlight and shows the typed error', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      await r.server(r.game(GameState.initial()));
      r.ctl.place(9);
      await r.server({'t': 'error', 'code': 'illegal_move', 'message': 'That move is not allowed.', 'ref': 1});
      expect(r.s.optimistic, isNull);
      expect(r.s.error!.code, 'illegal_move');
      expect(r.s.error!.message, 'That move is not allowed.');
      r.ctl.clearError();
      expect(r.s.error, isNull);
    });

    test('createRoom / joinRoom of a different room restart the numbering', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(lastSeq: 0));
      r.ctl.setReady(true);
      r.ctl.setReady(false);
      expect(r.ch.of('ready').map((m) => m['seq']), [1, 2]);
      r.ctl.joinRoom('ZZZZZZ');
      await r.server(r.room(code: 'ZZZZZZ', lastSeq: 0));
      r.ctl.setReady(true);
      expect(r.ch.of('ready').last['seq'], 1);
    });
  });

  group('mirroring the server game', () {
    test('a capture in progress is shown with its legal targets, and capture answers it', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      final g = GameState.fromMasks(mask0: maskOf([0, 1]), mask1: maskOf([20, 22]), hand0: 5, hand1: 5);
      await r.server(r.game(g, pending: const Move.place(2), targets: [20, 22]));
      expect(r.s.game!.pendingStep, const Move.place(2));
      expect(r.s.game!.pendingTargets, maskOf([20, 22]));
      expect(r.s.myTurn, isTrue);
      r.ctl.capture(20);
      expect(r.ch.of('capture').single['point'], 20);
    });

    test('capture is not sent when nothing is pending', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      await r.server(r.game(GameState.initial()));
      r.ctl.capture(5);
      expect(r.ch.of('capture'), isEmpty);
    });

    test('a confirmed move that lines up is re-derived for the existing animations', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing', mySeat: 1));
      final g0 = GameState.initial();
      await r.server(r.game(g0));
      expect(r.s.fxSerial, 0);
      final g1 = Rules.apply(g0, const Move.place(9));
      await r.server(r.game(g1, rev: 3, last: (seat: 0, move: const Move.place(9))));
      expect(r.s.fxSerial, 1);
      expect(r.s.lastResult!.move, const Move.place(9));
      expect(r.s.lastResult!.after, g1);
    });

    test('a move that does not line up (missed updates) is shown without an animation', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing', mySeat: 1));
      final g0 = GameState.initial();
      await r.server(r.game(g0));
      var g = g0;
      for (final p in [9, 10, 11]) {
        g = Rules.apply(g, Move.place(p));
      }
      await r.server(r.game(g, rev: 6, last: (seat: 1, move: const Move.place(11))));
      expect(r.s.game!.state, g, reason: 'the snapshot always wins');
      expect(r.s.fxSerial, 0);
      expect(r.s.lastResult, isNull);
    });

    test('a pending capture is not animated yet', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      final g = GameState.fromMasks(mask0: maskOf([0, 1]), mask1: maskOf([20, 22]), hand0: 5, hand1: 5);
      await r.server(r.game(g));
      await r.server(r.game(g, rev: 3, pending: const Move.place(2), targets: [20], last: (seat: 1, move: const Move.place(22))));
      expect(r.s.fxSerial, 0);
    });

    test('events are logged (capped) and the opponent\'s absence tracks the reconnect deadline', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      for (var i = 0; i < 70; i++) {
        await r.server({'t': 'event', 'rev': i, 'kind': 'emote', 'seat': 1, 'data': {'id': 'nice_one'}});
      }
      expect(r.s.events.length, 60);
      expect(r.s.events.last.serial, 70);
      final deadline = r.clock.now().millisecondsSinceEpoch + 45000;
      await r.server({'t': 'event', 'rev': 80, 'kind': 'disconnected', 'seat': 1, 'data': {'seat': 1, 'reconnectDeadline': deadline, 'reason': 'dropped'}});
      expect(r.s.opponentReconnectDeadlineMs, deadline);
      await r.server({'t': 'event', 'rev': 81, 'kind': 'reconnected', 'seat': 1, 'data': {'seat': 1}});
      expect(r.s.opponentReconnectDeadlineMs, isNull);
    });
  });

  group('the clock', () {
    test('the countdown uses the server clock corrected by the measured offset', () async {
      // this phone runs 7 s ahead of the server
      final r = _Rig(skewMs: 7000);
      await r.ctl.connect();
      await pump();
      await r.advance(const Duration(milliseconds: 100));
      r.ch.serverSend({'t': 'welcome', 'ts': r.clock.now().millisecondsSinceEpoch - 50, 'userId': 'me'});
      await pump();
      await r.server(r.room(status: 'playing'));
      // the server says: 100 s left, in SERVER time
      final deadline = r.clock.now().millisecondsSinceEpoch + 100000;
      await r.server({
        ...r.game(GameState.initial()),
        'clock': {'seat': 0, 'deadline': deadline, 'totalMs': 120000, 'graceMs': 1500},
      });
      expect(r.ctl.remainingMs(), closeTo(100000, 5));
      await r.advance(const Duration(seconds: 30));
      expect(r.ctl.remainingMs(), closeTo(70000, 5));
      await r.advance(const Duration(seconds: 100));
      expect(r.ctl.remainingMs(), 0, reason: 'never negative');
    });
  });

  group('errors and refusals', () {
    test('missing, expired, closed and full rooms each get their own state', () async {
      final r = _Rig(stored: 'K7TQ3M');
      await r.online(resume: {'code': 'K7TQ3M', 'status': 'lobby'});
      for (final c in {
        'room_not_found': RoomEnd.notFound,
        'room_expired': RoomEnd.expired,
        'room_closed': RoomEnd.closed,
        'room_full': RoomEnd.full,
      }.entries) {
        await r.server({'t': 'error', 'code': c.key, 'message': 'x'});
        expect(r.s.roomEnd, c.value, reason: c.key);
      }
      expect(r.s.rejoinCode, isNull, reason: 'a dead room is forgotten');
    });

    test('an outdated app is surfaced and not retried', () async {
      final r = _Rig();
      await r.ctl.connect();
      await pump();
      await r.server({'t': 'error', 'code': 'unsupported_version', 'message': 'Please update the app to play online.', 'fatal': true});
      expect(r.s.outdated, isTrue);
      expect(r.s.error!.message, 'Please update the app to play online.');
      await r.advance(const Duration(minutes: 1));
      expect(r.transport.attempts, 1);
    });

    test('rate limits carry the wait time', () async {
      final r = _Rig();
      await r.online();
      await r.server({'t': 'error', 'code': 'rate_limited', 'message': 'Slow down a little.', 'retryAfterMs': 4000});
      expect(r.s.error!.retryAfterMs, 4000);
    });

    test('a malformed server message cannot break the screen', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      await r.server({'t': 'game_state', 'snapshot': {'mask0': 'nonsense'}});
      await r.server({'t': 'room_state'});
      expect(r.s.room!.code, 'K7TQ3M', reason: 'the last good state is kept');
    });
  });

  group('leaving is only ever the confirmed button', () {
    test('every lifecycle change, drop and disconnect leaves the room alone', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      await r.server(r.game(GameState.initial()));
      for (final s in AppLifecycleState.values) {
        r.ctl.onLifecycle(s);
      }
      r.ch.networkDrop();
      await pump();
      await r.advance(const Duration(seconds: 2));
      await r.ctl.disconnect();
      final sent = [for (final c in r.transport.channels) ...c.of('leave')];
      expect(sent, isEmpty);
      expect(r.s.room, isNotNull, reason: 'the room view is kept for the reconnect');
    });

    test('leaveGame sends exactly one leave and forgets the room', () async {
      final r = _Rig();
      await r.online();
      await r.server(r.room(status: 'playing'));
      r.ctl.leaveGame();
      expect(r.ch.of('leave').length, 1);
      expect(r.s.rejoinCode, isNull);
      expect(r.store.read('online.room'), '');
    });

    test('resuming the app reconnects straight away', () async {
      final r = _Rig();
      r.transport.failWith = StateError('offline');
      await r.ctl.connect();
      await pump();
      r.transport.failWith = null;
      final before = r.transport.attempts;
      r.ctl.onLifecycle(AppLifecycleState.resumed);
      await pump();
      expect(r.transport.attempts, before + 1);
    });
  });
}
