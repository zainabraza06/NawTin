import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  group('room codes', () {
    test('are 6 characters from the unambiguous alphabet, and unique', () {
      final env = TestEnv();
      final seen = <String>{};
      for (var i = 0; i < 2000; i++) {
        final c = env.server.manager.generateCode();
        expect(c.length, 6);
        expect(isValidRoomCode(c), isTrue, reason: c);
        for (final bad in ['0', 'O', '1', 'I']) {
          expect(c.contains(bad), isFalse, reason: '$c has $bad');
        }
        seen.add(c);
      }
      // random, so repeats are possible but should be rare in 2000 draws
      expect(seen.length, greaterThan(1990));
    });

    test('a live room never gets the code of another live room', () async {
      final env = TestEnv(seed: 3);
      final codes = <String>{};
      for (var i = 0; i < 12; i++) {
        final c = await env.client('user$i', ip: 'ip$i');
        await c.send(Msg.createRoom);
        expect(codes.add(c.code!), isTrue);
      }
    });
  });

  group('create and join', () {
    test('the host gets a waiting room with an expiry; a friend joins by code', () async {
      final env = TestEnv();
      final host = await env.client('hostA', name: 'Zainab');
      await host.send(Msg.createRoom);
      expect(host.status, 'waiting');
      expect(host.players.length, 1);
      expect(host.room['host'], 'hostA');
      final expiry = host.room['expiresAt'] as int;
      expect(expiry, env.clock.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch);

      final guest = await env.client('guestB', name: 'Sam');
      // typed sloppily: lower case, a space and a dash
      final c = host.code!;
      await guest.send(Msg.joinRoom, {'code': '${c.substring(0, 3).toLowerCase()} - ${c.substring(3)}'});
      expect(guest.status, 'lobby');
      expect(guest.players.map((p) => p['name']), ['Zainab', 'Sam']);
      expect(host.status, 'lobby', reason: 'the host sees the guest arrive');
      expect(host.players.length, 2);
    });

    test('a third player is refused: room_full', () async {
      final env = TestEnv();
      final (host, _) = await env.lobby();
      final third = await env.client('third');
      await third.send(Msg.joinRoom, {'code': host.code});
      expect(third.lastErrorCode, ErrorCodes.roomFull);
    });

    test('unknown, malformed and expired codes give distinct errors', () async {
      final env = TestEnv();
      final c = await env.client('user1');
      await c.send(Msg.joinRoom, {'code': 'ZZZZZZ'});
      expect(c.lastErrorCode, ErrorCodes.roomNotFound);
      await c.send(Msg.joinRoom, {'code': 'abc'});
      expect(c.lastErrorCode, ErrorCodes.roomNotFound);

      final host = await env.client('hostA');
      await host.send(Msg.createRoom);
      final code = host.code!;
      await env.advance(const Duration(minutes: 10, seconds: 1));
      await c.send(Msg.joinRoom, {'code': code});
      expect(c.lastErrorCode, ErrorCodes.roomExpired);
    });

    test('a waiting room expires after 10 minutes and the host is told', () async {
      final env = TestEnv();
      final host = await env.client('hostA');
      await host.send(Msg.createRoom);
      await env.advance(const Duration(minutes: 9, seconds: 59));
      expect(host.status, 'waiting');
      await env.advance(const Duration(seconds: 2));
      expect(host.status, 'closed');
      expect(env.server.manager.rooms, isEmpty);
    });

    test('when a friend joins the expiry window starts again', () async {
      final env = TestEnv();
      final host = await env.client('hostA');
      await host.send(Msg.createRoom);
      await env.advance(const Duration(minutes: 8));
      final guest = await env.client('guestB');
      await guest.send(Msg.joinRoom, {'code': host.code});
      await env.advance(const Duration(minutes: 8)); // 16 minutes after creation
      expect(host.status, 'lobby');
      await env.advance(const Duration(minutes: 3));
      expect(host.status, 'closed');
    });

    test('one room per user: creating a second is already_in_room', () async {
      final env = TestEnv();
      final host = await env.client('hostA');
      await host.send(Msg.createRoom);
      await host.send(Msg.createRoom);
      expect(host.lastErrorCode, ErrorCodes.alreadyInRoom);
    });
  });

  group('lobby', () {
    test('only the host can start, and only when the guest is ready', () async {
      final env = TestEnv();
      final host = await env.client('hostA');
      await host.send(Msg.createRoom);
      final guest = await env.client('guestB');
      await guest.send(Msg.joinRoom, {'code': host.code});

      await guest.send(Msg.start);
      expect(guest.lastErrorCode, ErrorCodes.notHost);
      await host.send(Msg.start);
      expect(host.lastErrorCode, ErrorCodes.notReady);

      await guest.send(Msg.ready, {'ready': true});
      expect(host.players.firstWhere((p) => p['userId'] == 'guestB')['ready'], isTrue);
      await host.send(Msg.start);
      expect(host.status, 'playing');
      expect(guest.status, 'playing');
    });

    test('start flips a coin: one player per seat, both told who goes first', () async {
      final env = TestEnv(seed: 9);
      final (first, second) = await env.startedGame();
      expect(first.seat, 0);
      expect(second.seat, 1);
      final flip = first.room['coinFlip'] as Map;
      expect(flip['seat0'], first.uid);
      expect(second.room['coinFlip'], flip);
    });

    test('over many rooms both players get seat 0 about equally', () async {
      final env = TestEnv(seed: 21);
      var hostFirst = 0;
      for (var i = 0; i < 60; i++) {
        final host = await env.client('host$i', ip: 'a$i');
        await host.send(Msg.createRoom);
        final guest = await env.client('guest$i', ip: 'b$i');
        await guest.send(Msg.joinRoom, {'code': host.code});
        await guest.send(Msg.ready, {'ready': true});
        await host.send(Msg.start);
        if (host.seat == 0) hostFirst++;
      }
      expect(hostFirst, inInclusiveRange(15, 45));
    });

    test('the first game_state is a fresh game with the server clock', () async {
      final env = TestEnv();
      final (first, _) = await env.startedGame();
      final s = first.state;
      expect(s, GameState.initial());
      expect(s.placesLeft, 2);
      final clock = first.clockInfo!;
      expect(clock['seat'], 0);
      expect(clock['totalMs'], 120000);
      expect(clock['deadline'], env.clock.now().add(const Duration(milliseconds: 121500)).millisecondsSinceEpoch);
      expect(first.room['rules'], containsPair('placementRule', 'symmetricOpening'));
    });

    test('the host leaving the lobby closes the room; the guest leaving frees it', () async {
      final env = TestEnv();
      final (host, guest) = await env.lobby();
      await guest.send(Msg.leave);
      expect(host.status, 'waiting');
      expect(host.players.length, 1);
      // the guest is free to join again
      await guest.send(Msg.joinRoom, {'code': host.code});
      expect(guest.status, 'lobby');
      await host.send(Msg.leave);
      expect(guest.status, 'closed');
      expect(env.server.manager.rooms, isEmpty);
    });
  });
}
