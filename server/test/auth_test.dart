import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:naw_tin_server/naw_tin_server.dart';
import 'package:test/test.dart';

import 'support.dart';

const project = 'naw-tin-test';
final keyPem = File('test/fixtures/test_key.pem').readAsStringSync();
final certPem = File('test/fixtures/test_cert.pem').readAsStringSync();

String token({
  String sub = 'firebase-uid-1',
  String? aud,
  String? iss,
  Duration expiresIn = const Duration(hours: 1),
  String kid = 'k1',
  String provider = 'anonymous',
  bool withSub = true,
}) {
  final jwt = JWT(
    {'firebase': {'sign_in_provider': provider}},
    subject: withSub ? sub : null,
    issuer: iss ?? 'https://securetoken.google.com/$project',
    audience: Audience.one(aud ?? project),
    header: {'kid': kid},
  );
  return jwt.sign(RSAPrivateKey(keyPem), algorithm: JWTAlgorithm.RS256, expiresIn: expiresIn);
}

FirebaseTokenVerifier verifier() =>
    FirebaseTokenVerifier(project, fetchCerts: () async => {'k1': certPem});

void main() {
  setUp(() => Rules.placementRule = PlacementRule.symmetricOpening);

  group('Firebase ID token verification', () {
    test('accepts a valid anonymous token and returns the stable uid', () async {
      final u = await verifier().verify(token());
      expect(u?.uid, 'firebase-uid-1');
      expect(u?.anonymous, isTrue);
    });

    test('a later Google sign-in keeps the same uid', () async {
      final u = await verifier().verify(token(provider: 'google.com'));
      expect(u?.uid, 'firebase-uid-1');
      expect(u?.anonymous, isFalse);
    });

    test('rejects the wrong project, issuer, expired, unknown key and tampering', () async {
      final v = verifier();
      expect(await v.verify(token(aud: 'some-other-project')), isNull);
      expect(await v.verify(token(iss: 'https://evil.example/$project')), isNull);
      expect(await v.verify(token(expiresIn: const Duration(seconds: -30))), isNull);
      expect(await v.verify(token(kid: 'unknown')), isNull);
      final good = token();
      final parts = good.split('.');
      final forged = '${parts[0]}.${parts[1]}.${parts[2].substring(0, parts[2].length - 4)}AAAA';
      expect(await v.verify(forged), isNull);
      expect(await v.verify('not.a.jwt'), isNull);
      expect(await v.verify(''), isNull);
    });

    test('rejects an HMAC token that tries to pass as RS256', () async {
      final sneaky = JWT({}, subject: 'attacker', issuer: 'https://securetoken.google.com/$project', audience: Audience.one(project), header: {'kid': 'k1'})
          .sign(SecretKey('anything'), algorithm: JWTAlgorithm.HS256);
      expect(await verifier().verify(sneaky), isNull);
    });

    test('rejects a token with no subject', () async {
      expect(await verifier().verify(token(withSub: false)), isNull);
    });
  });

  group('test-mode tokens and the guardrails around them', () {
    test('fake tokens only parse in the expected shape', () async {
      final v = TestTokenVerifier();
      expect((await v.verify('test:alice'))?.uid, 'alice');
      expect(await v.verify('test:'), isNull);
      expect(await v.verify('test:a'), isNull);
      expect(await v.verify('alice'), isNull);
      expect(await v.verify('test:bad uid!'), isNull);
    });

    test('test auth is OFF by default and the server needs a real project id', () {
      expect(() => ServerConfig.fromEnv({}), throwsStateError);
      final ok = ServerConfig.fromEnv({'FIREBASE_PROJECT_ID': 'proj'});
      expect(ok.testAuth, isFalse);
      expect(ok.firebaseProjectId, 'proj');
    });

    test('test auth needs the explicit environment variable', () {
      expect(ServerConfig.fromEnv({'NAWTIN_TEST_AUTH': '1'}).testAuth, isTrue);
      expect(() => ServerConfig.fromEnv({'NAWTIN_TEST_AUTH': 'true'}), throwsStateError,
          reason: 'only the exact value "1" enables it');
      expect(() => ServerConfig.fromEnv({'NAWTIN_TEST_AUTH': '0'}), throwsStateError);
    });

    test('the server refuses to start with fake tokens on Cloud Run', () {
      for (final marker in ['K_SERVICE', 'K_REVISION']) {
        expect(
          () => ServerConfig.fromEnv({'NAWTIN_TEST_AUTH': '1', 'FIREBASE_PROJECT_ID': 'p', marker: 'naw-tin'}),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Cloud Run'))),
        );
      }
      // a real deployment (Firebase, no test mode) is fine on Cloud Run
      final real = ServerConfig.fromEnv({'FIREBASE_PROJECT_ID': 'p', 'K_SERVICE': 'naw-tin'});
      expect(real.testAuth, isFalse);
    });
  });

  group('the hello handshake', () {
    test('a good hello is answered with welcome', () async {
      final env = TestEnv();
      final c = await env.client('alice');
      final w = c.last('welcome')!;
      expect(w['userId'], 'alice');
      expect(w['protocol'], protocolVersion);
      expect(w['minProtocol'], minProtocolVersion);
      expect(w['resume'], isNull);
    });

    test('a bad token is refused and the socket closed (4001)', () async {
      final env = TestEnv();
      final c = await env.client('alice', hello: false);
      await c.hello(token: 'garbage');
      expect(c.errors().single['code'], ErrorCodes.unauthorized);
      expect(c.errors().single['fatal'], true);
      expect(c.ch.closeCode, 4001);
    });

    test('an outdated client gets a clear message and 4000', () async {
      final env = TestEnv();
      final c = await env.client('alice', hello: false);
      await c.hello(protocol: 0);
      final e = c.errors().single;
      expect(e['code'], ErrorCodes.unsupportedVersion);
      expect(e['message'], 'Please update the app to play online.');
      expect(e['fatal'], true);
      expect(c.ch.closeCode, 4000);
    });

    test('anything before hello is refused', () async {
      final env = TestEnv();
      final c = await env.client('alice', hello: false);
      await c.send(Msg.createRoom);
      expect(c.lastErrorCode, ErrorCodes.unauthorized);
      expect(c.ch.closeCode, 4001);
      expect(env.server.manager.rooms, isEmpty);
    });

    test('no hello within 5 seconds: the socket is closed', () async {
      final env = TestEnv();
      final c = await env.client('alice', hello: false);
      await env.advance(const Duration(seconds: 4), heartbeats: false);
      expect(c.ch.closeCode, isNull);
      await env.advance(const Duration(seconds: 2), heartbeats: false);
      expect(c.ch.closeCode, 4001);
    });

    test('a rejected name is a normal error: pick another and carry on', () async {
      final env = TestEnv();
      final c = await env.client('alice', hello: false);
      await c.hello(nameOverride: 'x');
      expect(c.lastErrorCode, ErrorCodes.nameInvalid);
      expect(c.ch.closeCode, isNull);
      await c.hello(nameOverride: 'Alice');
      expect(c.last('welcome'), isNotNull);
    });

    test('malformed frames are errors; repeated ones close the socket', () async {
      final env = TestEnv();
      final c = await env.client('alice');
      for (var i = 0; i < 4; i++) {
        c.ch.clientSend('{not json');
        await pump();
      }
      expect(c.errors().length, 4);
      expect(c.ch.closeCode, isNull);
      c.ch.clientSend('[1,2,3]');
      await pump();
      expect(c.ch.closeCode, 4003);
    });

    test('oversized frames are refused', () async {
      final env = TestEnv();
      final c = await env.client('alice');
      c.ch.clientSend('{"t":"ping","pad":"${'x' * 5000}"}');
      await pump();
      expect(c.ch.closeCode, 4003);
    });

    test('ping is answered with pong carrying the nonce and the server time', () async {
      final env = TestEnv();
      final c = await env.client('alice');
      await c.send(Msg.ping, {'n': 77, 'rtt': 123});
      final pong = c.last('pong')!;
      expect(pong['n'], 77);
      expect(pong['ts'], env.clock.now().millisecondsSinceEpoch);
    });
  });
}
