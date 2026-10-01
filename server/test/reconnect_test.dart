import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

import 'support.dart';

const window = Duration(seconds: 45);

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  group('disconnects', () {
    test('the opponent is told, with the reconnect deadline', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await b.ch.drop();
      await pump();
      final e = a.events(EventKind.disconnected).single;
      expect((e['data'] as Map)['seat'], 1);
      expect((e['data'] as Map)['reconnectDeadline'], env.clock.now().add(window).millisecondsSinceEpoch);
      expect((e['data'] as Map)['reason'], 'dropped');
      expect(a.players.firstWhere((p) => p['userId'] == b.uid)['connected'], isFalse);
    });

    test('returning inside the window resumes with a full state sync', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await a.send(Msg.place, {'to': 0});
      await a.send(Msg.place, {'to': 1});
      await b.ch.drop();
      await env.advance(const Duration(seconds: 30));
      // the app was killed and restarted: a new socket, hello with the saved room
      await b.reconnect(resume: a.code);

      expect(b.last('welcome')!['resume'], {'code': a.code, 'status': 'playing'});
      expect(b.state, a.state, reason: 'a full snapshot, not a replay');
      expect(b.status, 'playing');
      expect(b.me['connected'], isTrue);
      expect(a.events(EventKind.reconnected).length, 1);
      expect(a.players.firstWhere((p) => p['userId'] == b.uid)['connected'], isTrue);

      // play carries on, and sequence numbers continue from the saved counter
      await b.send(Msg.place, {'to': 9});
      expect(b.errors(), isEmpty);
      expect(a.state.mask1, bit(9));
    });

    test('not returning within 45 seconds forfeits the game', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await b.ch.drop();
      await env.advance(const Duration(seconds: 44));
      expect(a.status, 'playing');
      await env.advance(const Duration(seconds: 2));
      expect(a.status, 'finished');
      expect(a.events(EventKind.gameOver).single['data'], {'winner': 0, 'reason': 'abandoned'});
      expect(a.state.result!.winner, 0);
    });

    test('rejoining after the window shows the finished result', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await b.ch.drop();
      await env.advance(const Duration(seconds: 50));
      await b.reconnect(resume: a.code);
      expect(b.status, 'finished');
      expect(b.state.result!.winner, 0);
    });

    test('silence for 45 seconds counts as a drop; heartbeats keep a connection alive', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await env.advance(const Duration(minutes: 3)); // heartbeats on: nobody is dropped
      expect(a.ch.closeCode, isNull);
      expect(b.ch.closeCode, isNull);

      // b stops sending anything (frozen phone)
      final quiet = await env.client('quietC');
      await quiet.send(Msg.createRoom);
      await env.advance(const Duration(seconds: 60), heartbeats: false);
      expect(quiet.ch.closeCode, 1000);
      expect(quiet.ch.closeReason, 'idle');
    });

    test('a new connection by the same user replaces the old one and keeps the seat', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      final oldChannel = b.ch;
      final b2 = TestClient(env.server, b.uid, name: b.name);
      await b2.hello(resume: a.code);

      expect(oldChannel.closeCode, 4002);
      expect(b2.status, 'playing');
      expect(b2.seat, 1);
      expect(b2.state, a.state);
      expect(a.events(EventKind.disconnected), isEmpty, reason: 'a swap is not a disconnect');
      await a.send(Msg.place, {'to': 0});
      expect(b2.state.mask0, bit(0));
    });
  });

  group('leaving', () {
    test('the Leave button is an instant forfeit', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await b.send(Msg.leave);
      expect(a.status, 'finished');
      expect(a.events(EventKind.gameOver).single['data'], {'winner': 0, 'reason': 'forfeit'});
      expect(env.clock.pendingTimers, lessThan(8));
    });

    test('a connection drop (backgrounding, app kill) is NOT a leave', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await b.ch.drop();
      await env.advance(const Duration(seconds: 10));
      expect(a.status, 'playing');
      expect(a.events(EventKind.gameOver), isEmpty);
    });

    test('a guest who drops from the lobby is removed after the window', () async {
      final env = TestEnv();
      final (host, guest) = await env.lobby();
      await guest.ch.drop();
      await env.advance(const Duration(seconds: 46));
      expect(host.status, 'waiting');
      expect(host.players.length, 1);
      // and they can join again
      final back = await env.client(guest.uid, name: 'Guesty');
      await back.send(Msg.joinRoom, {'code': host.code});
      expect(back.status, 'lobby');
    });

    test('a host who drops from the lobby takes the room with them after the window', () async {
      final env = TestEnv();
      final (host, guest) = await env.lobby();
      await host.ch.drop();
      await env.advance(const Duration(seconds: 46));
      expect(guest.status, 'closed');
      expect(env.server.manager.rooms, isEmpty);
    });

    test('a client that lost its socket can rejoin its room by code', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await b.ch.drop();
      await pump();
      final b2 = await env.client(b.uid, name: b.name, ip: 'other');
      expect(b2.last('welcome')!['resume'], isNotNull, reason: 'the server offers "Rejoin game"');
      await b2.send(Msg.joinRoom, {'code': a.code});
      expect(b2.status, 'playing');
      expect(b2.state, a.state);
    });
  });
}
