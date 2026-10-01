import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  group('display names', () {
    test('ordinary names pass and are tidied', () {
      expect(validateName('Zainab'), 'Zainab');
      expect(validateName('  Sam   Lee  '), 'Sam Lee');
      expect(validateName('Bob'), 'Bob');
      expect(validateName('Nigel'), 'Nigel');
      expect(validateName('Alex_99'), 'Alex_99');
      expect(validateName('Cool-Cat'), 'Cool-Cat');
    });

    test('too short, too long, odd characters, markup', () {
      for (final bad in ['', 'a', 'x' * 17, 'Sam<script>', 'a\u{1F600}b', 'Sam!', 'ab\ncd', null]) {
        expect(validateName(bad), isNull, reason: '$bad');
      }
    });

    test('obvious profanity is blocked, including look-alikes and spacing', () {
      for (final bad in ['shit', 'Sh1t', 'F U C K', 'f_u_c_k', 'b1tch', 'FUCKER', '\$hit', 'Admin', 'Naw Tin']) {
        expect(validateName(bad), isNull, reason: bad);
      }
    });
  });

  group('rate limits', () {
    test('creating rooms: 5 per 10 minutes', () async {
      final env = TestEnv();
      final c = await env.client('creator');
      for (var i = 0; i < 5; i++) {
        await c.send(Msg.createRoom);
        expect(c.lastErrorCode, isNull, reason: 'room $i');
        await c.send(Msg.leave); // closes the lobby so the next create is allowed
      }
      await c.send(Msg.createRoom);
      expect(c.lastErrorCode, ErrorCodes.rateLimited);
      expect(c.errors().last['retryAfterMs'], greaterThan(0));
      await env.advance(const Duration(minutes: 10, seconds: 1));
      await c.send(Msg.createRoom);
      expect(c.status, 'waiting');
      expect(c.last('room_state')!['host'], 'creator');
    });

    test('guessing codes: five misses lock joining for a minute', () async {
      final env = TestEnv();
      final host = await env.client('hostA');
      await host.send(Msg.createRoom);
      final guesser = await env.client('guesser');
      for (var i = 0; i < 5; i++) {
        await guesser.send(Msg.joinRoom, {'code': 'ZZZZZ$i'.substring(0, 6).replaceAll('0', '2').replaceAll('1', '3')});
        expect(guesser.lastErrorCode, ErrorCodes.roomNotFound);
      }
      // even the right code is refused now
      await guesser.send(Msg.joinRoom, {'code': host.code});
      expect(guesser.lastErrorCode, ErrorCodes.rateLimited);
      expect(host.status, 'waiting', reason: 'nobody got in');
      await env.advance(const Duration(seconds: 61));
      await guesser.send(Msg.joinRoom, {'code': host.code});
      expect(guesser.status, 'lobby');
    });

    test('joining is also limited per IP across different users', () async {
      final env = TestEnv();
      final host = await env.client('hostA');
      await host.send(Msg.createRoom);
      var refused = 0;
      for (var i = 0; i < 40; i++) {
        final c = await env.client('bot$i', ip: 'same-ip-for-all');
        // one connection per IP per minute is capped separately, so spread over minutes
        if (c.ch.closeCode != null) {
          refused++;
          continue;
        }
        await c.send(Msg.joinRoom, {'code': 'ABCDEF'});
        if (c.lastErrorCode == ErrorCodes.rateLimited) refused++;
        if (i % 15 == 14) await env.advance(const Duration(minutes: 1, seconds: 1));
      }
      expect(refused, greaterThan(0));
    });

    test('message floods: 20 per 10 seconds', () async {
      final env = TestEnv();
      final (host, _) = await env.lobby();
      for (var i = 0; i < 40; i++) {
        await host.send(Msg.ready, {'ready': true});
      }
      expect(host.errors().where((e) => e['code'] == ErrorCodes.rateLimited), isNotEmpty);
      await env.advance(const Duration(seconds: 11));
      final before = host.errors().length;
      // dropped (rate-limited) messages did not use up their numbers: carry on
      // from the last acknowledged one, as the real client does
      host.seq = host.last('room_state')!['ack'] as int;
      await host.send(Msg.ready, {'ready': true});
      expect(host.errors().length, before, reason: 'the limit lifted after the window');
    });

    test('pings are never rate limited (they are the heartbeat)', () async {
      final env = TestEnv();
      final c = await env.client('alice');
      for (var i = 0; i < 60; i++) {
        c.ch.clientSend({'v': 1, 't': 'ping', 'n': i});
      }
      await pump();
      expect(c.ofType('pong').length, 60);
      expect(c.errors(), isEmpty);
    });

    test('emotes: one per 3 seconds, six per minute', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await a.send(Msg.emote, {'id': 'nice_one'});
      await a.send(Msg.emote, {'id': 'oops'});
      expect(a.lastErrorCode, ErrorCodes.rateLimited);
      expect(b.events(EventKind.emote).length, 1);
      for (var i = 0; i < 8; i++) {
        await env.advance(const Duration(seconds: 3, milliseconds: 100));
        await a.send(Msg.emote, {'id': 'thanks'});
      }
      expect(b.events(EventKind.emote).length, lessThanOrEqualTo(6));
    });

    test('a rate-limited emote is dropped for good: it uses up its number and is never resent', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      await a.send(Msg.emote, {'id': 'nice_one'});
      await a.send(Msg.emote, {'id': 'oops'}); // too soon: dropped
      final limited = a.errors().last;
      expect(limited['code'], ErrorCodes.rateLimited);
      expect(limited.containsKey('ref'), isFalse, reason: 'no ref: the client must not resend it');
      expect(a.ofType('ack'), isNotEmpty, reason: 'its number counts as processed');
      // the very next message is accepted in order (no seq_gap, no stall)
      await a.send(Msg.offerRematch);
      expect(a.lastErrorCode, ErrorCodes.rematchUnavailable, reason: 'a normal error, not seq_gap');
      expect(b.events(EventKind.emote).length, 1);
    });

    test('reports: only the other player, only known reasons, once per game', () async {
      final env = TestEnv();
      final (a, b) = await env.startedGame();
      final code = a.code!;
      await a.send(Msg.report, {'userId': 'nobody', 'reason': 'afk'});
      expect(a.lastErrorCode, ErrorCodes.badRequest, reason: 'not in this room');
      await a.send(Msg.report, {'userId': a.uid, 'reason': 'afk'});
      expect(a.lastErrorCode, ErrorCodes.badRequest, reason: 'cannot report yourself');
      await a.send(Msg.report, {'userId': b.uid, 'reason': 'because i said so'});
      expect(a.lastErrorCode, ErrorCodes.badRequest, reason: 'unknown reason (no free text)');
      expect(env.roomOf(code).reports, isEmpty);

      await a.send(Msg.report, {'userId': b.uid, 'reason': 'abusive_name'});
      await a.send(Msg.report, {'userId': b.uid, 'reason': 'cheating'}); // second one this game: ignored
      final reports = env.roomOf(code).reports;
      expect(reports, hasLength(1));
      expect(reports.single.reporter, a.uid);
      expect(reports.single.reported, b.uid);
      expect(reports.single.reason, 'abusive_name');
      // the other player can report too
      await b.send(Msg.report, {'userId': a.uid, 'reason': 'afk'});
      expect(env.roomOf(code).reports, hasLength(2));
    });

    test('connections per IP: 20 per minute, then refused with 4003', () async {
      final env = TestEnv();
      final chans = <FakeChannel>[];
      for (var i = 0; i < 22; i++) {
        final ch = FakeChannel('1.2.3.4');
        env.server.attach(ch);
        chans.add(ch);
      }
      await pump();
      expect(chans.where((c) => c.closeCode == 4003).length, 2);
      expect(chans.first.closeCode, isNull);
    });

    test('rate-limit state does not leak between users', () async {
      final env = TestEnv();
      final a = await env.client('userone', ip: 'ip1');
      final b = await env.client('usertwo', ip: 'ip2');
      for (var i = 0; i < 6; i++) {
        await a.send(Msg.createRoom);
        await a.send(Msg.leave);
      }
      await b.send(Msg.createRoom);
      expect(b.lastErrorCode, isNull);
      expect(b.status, 'waiting');
    });
  });

  group('the server never trusts the client', () {
    test('client-sent state, seat or rules fields are ignored', () async {
      final env = TestEnv();
      final (a, _) = await env.startedGame();
      a.ch.clientSend({
        'v': 1, 't': 'place', 'seq': ++a.seq, 'to': 0,
        'seat': 1, 'turn': 1, 'mask0': 0xFFFFFF, 'snapshot': {'mask0': 7}, 'hand0': 0,
      });
      await pump();
      expect(a.state.mask0, bit(0));
      expect(a.state.hand0, 8);
      expect(a.state.turn, 0);
      expect(a.errors(), isEmpty);
    });

    test('room-level messages from outside a room are refused', () async {
      final env = TestEnv();
      final c = await env.client('lonely');
      await c.send(Msg.place, {'to': 0});
      expect(c.lastErrorCode, ErrorCodes.notInRoom);
    });
  });
}
