import 'package:flutter_test/flutter_test.dart';
import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:naw_tin_server/naw_tin_server.dart' as srv;
import 'package:nawtin/services/online/auth_provider.dart';
import 'package:nawtin/services/online/online_config.dart';
import 'package:nawtin/services/online/online_service.dart';

import 'support.dart';

class _Auth implements AuthTokenProvider {
  int calls = 0;
  bool lastRefresh = false;
  @override
  String? get debugUid => 'tester';
  @override
  Future<String> idToken({bool forceRefresh = false}) async {
    calls++;
    lastRefresh = forceRefresh;
    return 'test:tester';
  }
}

class _Rig {
  _Rig({String? stored, OnlineConfig? config, int skewMs = 0, int seed = 4})
      : clock = srv.FakeClock(),
        transport = ScriptedTransport(),
        auth = _Auth(),
        storedRoom = stored {
    sched = ClockScheduler(clock, skewMs: skewMs);
    service = OnlineService(
      config: config ?? OnlineConfig.parse('ws://localhost:8080/ws', release: false),
      auth: auth,
      transport: transport,
      scheduler: sched,
      profile: () => const OnlineProfile('Tester', 3),
      resumeCode: () => storedRoom,
      random: seeded(seed),
      appVersion: '1.2.3',
    );
  }

  final srv.FakeClock clock;
  final ScriptedTransport transport;
  final _Auth auth;
  late final ClockScheduler sched;
  late final OnlineService service;
  String? storedRoom;
  final List<Map<String, Object?>> received = [];

  Future<void> advance(Duration d) async {
    var left = d;
    while (left > Duration.zero) {
      final step = left > const Duration(seconds: 1) ? const Duration(seconds: 1) : left;
      clock.advance(step);
      await pump(3);
      left -= step;
    }
  }

  /// Connects and completes the handshake.
  Future<ScriptedChannel> online({Map<String, Object?>? resume}) async {
    service.messages.listen(received.add);
    await service.connect();
    await pump();
    final ch = transport.last;
    ch.serverSend({'t': 'welcome', 'ts': clock.now().millisecondsSinceEpoch, 'userId': 'tester', if (resume != null) 'resume': resume});
    await pump();
    return ch;
  }

  Future<ScriptedChannel> reconnectAfterDrop({Map<String, Object?>? resume}) async {
    final before = transport.channels.length;
    for (var i = 0; i < 60 && transport.channels.length == before; i++) {
      await advance(const Duration(milliseconds: 250));
    }
    expect(transport.channels.length, before + 1, reason: 'the client opened a new connection');
    final ch = transport.last;
    ch.serverSend({'t': 'welcome', 'ts': clock.now().millisecondsSinceEpoch, 'userId': 'tester', if (resume != null) 'resume': resume});
    await pump();
    return ch;
  }

  List<Map<String, Object?>> allSent(String t) => [for (final c in transport.channels) ...c.of(t)];
}

Map<String, Object?> roomState({int lastSeq = 0, String status = 'lobby'}) => {
      't': 'room_state',
      'code': 'K7TQ3M',
      'status': status,
      'host': 'tester',
      'players': [
        {'userId': 'tester', 'name': 'Tester', 'avatar': 3, 'connected': true, 'ready': true, 'seat': null, 'pingMs': 0, 'lastSeq': lastSeq},
      ],
      'rules': {'turnSeconds': 120, 'reconnectSeconds': 45},
      'rev': 1,
      'ack': lastSeq,
    };

void main() {
  group('handshake', () {
    test('hello carries the token, profile, protocol and the room to resume', () async {
      final r = _Rig(stored: 'K7TQ3M');
      await r.online(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      final hello = r.transport.last.hello!;
      expect(hello['protocol'], protocolVersion);
      expect(hello['token'], 'test:tester');
      expect(hello['name'], 'Tester');
      expect(hello['avatar'], 3);
      expect(hello['appVersion'], '1.2.3');
      expect(hello['resume'], 'K7TQ3M');
      expect(r.service.state.isOnline, isTrue);
      expect(r.service.userId, 'tester');
    });

    test('no stored room: no resume field', () async {
      final r = _Rig();
      await r.online();
      expect(r.transport.last.hello!.containsKey('resume'), isFalse);
    });

    test('a server that never answers is retried (handshake timeout)', () async {
      final r = _Rig();
      await r.service.connect();
      await pump();
      await r.advance(const Duration(milliseconds: 8100));
      expect(r.service.state.phase, ConnPhase.reconnecting);
      expect(r.service.state.problem, Problem.handshakeTimeout);
      await r.advance(const Duration(seconds: 2));
      expect(r.transport.attempts, 2, reason: 'and it tries again');
    });

    test('no server address: stops with a clear reason instead of trying', () async {
      final r = _Rig(config: OnlineConfig.parse('http://nope', release: true));
      await r.service.connect();
      expect(r.service.state.stopReason, StopReason.notConfigured);
      expect(r.transport.attempts, 0);
    });
  });

  group('clock offset', () {
    test("a phone 5 s ahead of the server learns the offset from the server's timestamps", () async {
      final r = _Rig(skewMs: 5000); // phone clock = server clock + 5 s
      r.service.messages.listen(r.received.add);
      await r.service.connect();
      await pump();
      final ch = r.transport.last;
      // hello leaves at T0; the server answers 100 ms later; 100 ms back
      await r.advance(const Duration(milliseconds: 100));
      final serverTs = r.clock.now().millisecondsSinceEpoch;
      await r.advance(const Duration(milliseconds: 100));
      ch.serverSend({'t': 'welcome', 'ts': serverTs, 'userId': 'tester'});
      await pump();
      expect(r.service.offsetMs, closeTo(-5000, 5));
      // the corrected clock agrees with the server's
      expect(r.service.serverNowMs, closeTo(r.clock.now().millisecondsSinceEpoch, 5));
    });

    test('the sample with the smallest round trip wins', () async {
      final r = _Rig();
      r.service.messages.listen(r.received.add);
      await r.service.connect();
      await pump();
      final ch = r.transport.last;
      await r.advance(const Duration(milliseconds: 100)); // a 100 ms handshake
      ch.serverSend({'t': 'welcome', 'ts': r.clock.now().millisecondsSinceEpoch - 50, 'userId': 'tester'});
      await pump();
      expect(r.service.offsetMs.abs(), lessThan(5));

      // a slow, lopsided ping (800 ms) with a wild timestamp must not move it
      await r.advance(const Duration(seconds: 15));
      final slow = ch.of('ping').last['n'];
      await r.advance(const Duration(milliseconds: 800));
      ch.serverSend({'t': 'pong', 'n': slow, 'ts': r.clock.now().millisecondsSinceEpoch + 4000});
      await pump();
      expect(r.service.offsetMs.abs(), lessThan(5), reason: 'a worse round trip is ignored');

      // a fast ping (20 ms) from a server whose clock is 3 s ahead takes over
      await r.advance(const Duration(milliseconds: 14200)); // exactly to the next heartbeat
      final fast = ch.of('ping').last['n'];
      expect(fast, 2);
      await r.advance(const Duration(milliseconds: 20));
      ch.serverSend({'t': 'pong', 'n': fast, 'ts': r.clock.now().millisecondsSinceEpoch - 10 + 3000});
      await pump();
      expect(r.service.offsetMs, closeTo(3000, 5));
      expect(r.service.pingMs, 20);
    });
  });

  group('heartbeat', () {
    test('pings every 15 s, carrying the last measured round trip', () async {
      final r = _Rig();
      final ch = await r.online();
      for (var i = 1; i <= 3; i++) {
        // the replies take 20 ms, so later heartbeats come 20 ms sooner
        await r.advance(i == 1 ? const Duration(seconds: 15) : const Duration(milliseconds: 14980));
        final ping = ch.of('ping').last;
        expect(ping['n'], i);
        expect(ping['rtt'], i == 1 ? 0 : 20, reason: 'ping $i carries the previous round trip');
        await r.advance(const Duration(milliseconds: 20));
        ch.serverSend({'t': 'pong', 'n': i, 'ts': r.clock.now().millisecondsSinceEpoch});
        await pump();
        await r.advance(const Duration(milliseconds: 0));
      }
      expect(ch.of('ping').length, 3);
      expect(r.service.pingMs, 20);
    });

    test('a connection silent for 40 s is treated as dead and reconnected', () async {
      final r = _Rig();
      final ch = await r.online();
      expect(r.transport.attempts, 1);
      await r.advance(const Duration(seconds: 46)); // pings go out, nothing comes back
      expect(r.service.state.phase, anyOf(ConnPhase.reconnecting, ConnPhase.connecting));
      await r.advance(const Duration(seconds: 12));
      expect(r.transport.attempts, greaterThanOrEqualTo(2));
      expect(ch.isClosed, isTrue);
    });

    test('any traffic keeps it alive', () async {
      final r = _Rig();
      final ch = await r.online();
      for (var i = 0; i < 10; i++) {
        await r.advance(const Duration(seconds: 15));
        ch.serverSend({'t': 'pong', 'n': i + 1, 'ts': r.clock.now().millisecondsSinceEpoch});
        await pump();
      }
      expect(r.service.state.isOnline, isTrue);
      expect(r.transport.attempts, 1);
    });
  });

  group('reconnecting', () {
    test('exponential backoff 0.5 s -> 8 s with +-25% jitter, then steady', () async {
      final r = _Rig();
      r.transport.failWith = StateError('no route');
      await r.service.connect();
      await pump();
      final base = [500, 1000, 2000, 4000, 8000, 8000, 8000];
      for (var i = 0; i < base.length; i++) {
        final st = r.service.state;
        expect(st.phase, ConnPhase.reconnecting, reason: 'attempt ${i + 1}');
        expect(st.attempt, i + 1);
        final wait = st.retryAt!.difference(r.clock.now()).inMilliseconds;
        expect(wait, inInclusiveRange((base[i] * 0.75).floor(), (base[i] * 1.25).ceil()), reason: 'attempt ${i + 1}');
        await r.advance(Duration(milliseconds: wait + 5));
      }
      expect(r.transport.attempts, base.length + 1);
    });

    test('jitter really varies the delays', () async {
      final waits = <int>{};
      for (var seed = 1; seed <= 6; seed++) {
        final r = _Rig(seed: seed);
        r.transport.failWith = StateError('x');
        await r.service.connect();
        await pump();
        waits.add(r.service.state.retryAt!.difference(r.clock.now()).inMilliseconds);
      }
      expect(waits.length, greaterThan(3));
    });

    test('a successful connection resets the backoff', () async {
      final r = _Rig();
      r.transport.failWith = StateError('x');
      await r.service.connect();
      await pump();
      await r.advance(const Duration(seconds: 3));
      expect(r.service.state.attempt, greaterThan(1));
      r.transport.failWith = null;
      for (var i = 0; i < 60 && r.transport.channels.isEmpty; i++) {
        await r.advance(const Duration(milliseconds: 250));
      }
      r.transport.last.serverSend({'t': 'welcome', 'ts': r.clock.now().millisecondsSinceEpoch, 'userId': 'tester'});
      await pump();
      expect(r.service.state.isOnline, isTrue);
      // drop again: the first retry delay is short again
      r.transport.last.networkDrop();
      await pump();
      final wait = r.service.state.retryAt!.difference(r.clock.now()).inMilliseconds;
      expect(wait, lessThanOrEqualTo(625));
    });

    test('a dropped connection reconnects and asks to resume the room', () async {
      final r = _Rig(stored: 'K7TQ3M');
      final first = await r.online(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      first.networkDrop();
      await pump();
      expect(r.service.state.phase, ConnPhase.reconnecting);
      await r.reconnectAfterDrop(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      expect(r.transport.channels.length, 2);
      expect(r.transport.last.hello!['resume'], 'K7TQ3M');
      expect(r.service.state.isOnline, isTrue);
    });

    test('coming back to the foreground reconnects immediately', () async {
      final r = _Rig();
      r.transport.failWith = StateError('offline');
      await r.service.connect();
      await pump();
      r.transport.failWith = null;
      expect(r.service.state.phase, ConnPhase.reconnecting);
      final before = r.transport.attempts;
      r.service.appResumed();
      await pump();
      expect(r.transport.attempts, before + 1, reason: 'no waiting out the backoff');
    });
  });

  group('refusals stop the retrying', () {
    test('an outdated app (close code 4000) shows "update" and never retries', () async {
      final r = _Rig();
      final ch = await r.online();
      ch.serverClose(CloseCodes.outdated);
      await pump();
      expect(r.service.state.stopReason, StopReason.outdated);
      final attempts = r.transport.attempts;
      await r.advance(const Duration(minutes: 2));
      expect(r.transport.attempts, attempts);
    });

    test('unsupported_version error does the same, even before the socket closes', () async {
      final r = _Rig();
      r.service.messages.listen(r.received.add);
      await r.service.connect();
      await pump();
      r.transport.last.serverSend({'t': 'error', 'code': 'unsupported_version', 'message': 'Please update the app to play online.', 'fatal': true});
      await pump();
      expect(r.service.state.stopReason, StopReason.outdated);
      expect(r.received.single['message'], 'Please update the app to play online.');
      await r.advance(const Duration(minutes: 1));
      expect(r.transport.attempts, 1);
    });

    test('opened on another device (4002): stops, does not fight for the seat', () async {
      final r = _Rig();
      final ch = await r.online();
      ch.serverClose(CloseCodes.replaced);
      await pump();
      expect(r.service.state.stopReason, StopReason.replaced);
      await r.advance(const Duration(minutes: 1));
      expect(r.transport.attempts, 1);
    });

    test('sign-in refused (4001): one retry with a fresh token, then stop', () async {
      final r = _Rig();
      r.service.messages.listen(r.received.add);
      await r.service.connect();
      await pump();
      r.transport.last.serverClose(CloseCodes.unauthorized);
      await pump();
      await r.advance(const Duration(seconds: 2));
      expect(r.auth.lastRefresh, isTrue, reason: 'asked for a refreshed token');
      expect(r.transport.attempts, 2);
      r.transport.last.serverClose(CloseCodes.unauthorized);
      await pump();
      expect(r.service.state.stopReason, StopReason.unauthorized);
      await r.advance(const Duration(minutes: 1));
      expect(r.transport.attempts, 2);
    });

    test('rate-limited close (4003) backs off for at least 30 s', () async {
      final r = _Rig();
      final ch = await r.online();
      ch.serverClose(CloseCodes.rateLimited);
      await pump();
      final wait = r.service.state.retryAt!.difference(r.clock.now());
      expect(wait, greaterThanOrEqualTo(const Duration(seconds: 30)));
    });

    test('release builds with no sign-in say so instead of inventing a token', () async {
      final r = _Rig();
      final service = OnlineService(
        config: OnlineConfig.parse('wss://x.example/ws', release: true),
        auth: const UnavailableAuth(),
        transport: r.transport,
        scheduler: r.sched,
        profile: () => const OnlineProfile('T', 0),
        resumeCode: () => null,
      );
      await service.connect();
      await pump();
      expect(service.state.stopReason, StopReason.authUnavailable);
      expect(r.transport.attempts, 0);
    });
  });

  group('leaving is explicit only', () {
    test('disconnect, backgrounding, resume, drops and dispose never send leave', () async {
      final r = _Rig(stored: 'K7TQ3M');
      final first = await r.online(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      first.serverSend(roomState());
      await pump();
      r.service.appPaused();
      r.service.appResumed();
      first.networkDrop();
      await pump();
      await r.reconnectAfterDrop(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      r.service.appPaused();
      await r.service.disconnect();
      await r.service.dispose();
      expect(r.allSent('leave'), isEmpty, reason: 'no leave on any lifecycle path');
    });

    test('only an explicit send(leave) emits one', () async {
      final r = _Rig();
      final ch = await r.online();
      ch.serverSend(roomState());
      await pump();
      r.service.send(Msg.leave);
      expect(ch.of('leave').length, 1);
    });
  });

  group('sequence numbers', () {
    test('numbered 1, 2, 3 and held until acknowledged', () async {
      final r = _Rig();
      final ch = await r.online();
      ch.serverSend(roomState());
      await pump();
      expect(r.service.send(Msg.place, {'to': 0}), 1);
      expect(r.service.send(Msg.place, {'to': 1}), 2);
      expect(ch.of('place').map((m) => m['seq']), [1, 2]);
      expect(r.service.pendingCount, 2);
      ch.serverSend({...roomState(lastSeq: 1)});
      await pump();
      expect(r.service.pendingCount, 1, reason: 'seq 1 acknowledged');
      ch.serverSend({'t': 'ack', 'ack': 2});
      await pump();
      expect(r.service.pendingCount, 0);
    });

    test('after a drop only the unacknowledged ones are resent, with the SAME numbers', () async {
      final r = _Rig(stored: 'K7TQ3M');
      final first = await r.online(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      first.serverSend(roomState(status: 'playing'));
      await pump();
      r.service.send(Msg.place, {'to': 0}); // seq 1: the server got it
      r.service.send(Msg.place, {'to': 1}); // seq 2: lost on the way
      first.networkDrop();
      await pump();
      final second = await r.reconnectAfterDrop(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      expect(second.of('place'), isEmpty, reason: 'nothing is replayed before the server says where it is');
      second.serverSend(roomState(lastSeq: 1, status: 'playing'));
      await pump();
      expect(second.of('place').map((m) => m['seq']), [2]);
      expect(second.of('place').single['to'], 1);
      // and the counter carries on correctly
      expect(r.service.send(Msg.place, {'to': 2}), 3);
    });

    test('a message sent while offline waits and goes out in order after the resync', () async {
      final r = _Rig(stored: 'K7TQ3M');
      final first = await r.online(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      first.serverSend(roomState(status: 'playing'));
      await pump();
      first.networkDrop();
      await pump();
      r.service.send(Msg.place, {'to': 5}); // typed while the line is down
      expect(first.of('place'), isEmpty);
      final second = await r.reconnectAfterDrop(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      second.serverSend(roomState(lastSeq: 0, status: 'playing'));
      await pump();
      expect(second.of('place').map((m) => [m['seq'], m['to']]), [
        [1, 5]
      ]);
    });

    test('rate_limited: the same message is resent with the same number after the wait', () async {
      final r = _Rig();
      final ch = await r.online();
      ch.serverSend(roomState());
      await pump();
      r.service.send(Msg.ready, {'ready': true}); // 1
      r.service.send(Msg.place, {'to': 3}); // 2: refused as too fast
      ch.serverSend({'t': 'error', 'code': 'rate_limited', 'ref': 2, 'retryAfterMs': 1000, 'message': 'Slow down a little.'});
      await pump();
      r.service.send(Msg.place, {'to': 4}); // 3: queued behind the blocked one
      expect(ch.of('place').length, 1, reason: 'held back during the wait');
      await r.advance(const Duration(milliseconds: 1200));
      final places = ch.of('place');
      expect(places.map((m) => [m['seq'], m['to']]), [
        [2, 3],
        [2, 3],
        [3, 4],
      ]);
    });

    test('seq_gap: the server resyncs and the client continues from what it processed', () async {
      final r = _Rig();
      final ch = await r.online();
      ch.serverSend(roomState());
      await pump();
      r.service.send(Msg.ready, {'ready': true}); // 1
      r.service.send(Msg.place, {'to': 1}); // 2
      r.service.send(Msg.place, {'to': 2}); // 3
      ch.serverSend({'t': 'error', 'code': 'seq_gap', 'message': 'Messages were missed; resyncing.', 'ref': 3});
      await pump();
      ch.serverSend(roomState(lastSeq: 1));
      await pump();
      expect(ch.of('place').map((m) => m['seq']), [1 + 1, 3, 2, 3]);
    });

    test('after an app restart the counter jumps to the server\'s number, not back to 1', () async {
      final r = _Rig(stored: 'K7TQ3M');
      final ch = await r.online(resume: {'code': 'K7TQ3M', 'status': 'playing'});
      ch.serverSend(roomState(lastSeq: 7, status: 'playing'));
      await pump();
      expect(r.service.send(Msg.place, {'to': 0}), 8);
    });

    test('newRoom starts again from 1', () async {
      final r = _Rig();
      final ch = await r.online();
      ch.serverSend(roomState());
      await pump();
      r.service.send(Msg.ready, {'ready': true});
      r.service.send(Msg.ready, {'ready': false});
      r.service.newRoom();
      expect(r.service.send(Msg.ready, {'ready': true}), 1);
      expect(r.service.pendingCount, 1);
    });

    test('connection-level messages need a live connection', () async {
      final r = _Rig();
      expect(r.service.sendNow(Msg.createRoom), isFalse);
      final ch = await r.online();
      expect(r.service.sendNow(Msg.createRoom), isTrue);
      expect(ch.of('create_room').length, 1);
    });
  });
}
