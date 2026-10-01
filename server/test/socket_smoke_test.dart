import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:naw_tin_server/naw_tin_server.dart';
import 'package:test/test.dart';

/// A real HTTP server and real WebSockets on a random local port.
class Wire {
  Wire(this.ws) {
    ws.listen((raw) => inbox.add((jsonDecode(raw as String) as Map).cast<String, Object?>()));
  }
  final WebSocket ws;
  final List<Map<String, Object?>> inbox = [];
  int seq = 0;

  void send(String t, [Map<String, Object?> body = const {}]) {
    final s = Msg.sequenced.contains(t) ? ++seq : null;
    ws.add(jsonEncode({'v': 1, 't': t, if (s != null) 'seq': s, ...body}));
  }

  Future<Map<String, Object?>> waitFor(String t, {bool Function(Map<String, Object?>)? where}) async {
    for (var i = 0; i < 500; i++) {
      for (final m in inbox) {
        if (m['t'] == t && (where == null || where(m))) return m;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('never received $t; got ${inbox.map((m) => m['t']).toList()}');
  }
}

void main() {
  late NawTinServer server;
  late HttpServer http;

  setUp(() async {
    Rules.placementRule = PlacementRule.symmetricOpening;
    server = NawTinServer(
      config: const ServerConfig(testAuth: true),
      verifier: TestTokenVerifier(),
      ai: DirectAiService(),
      log: (e, [f = const {}]) {},
    );
    http = await server.serve(port: 0);
  });
  tearDown(() => server.stop());

  Future<Wire> connect(String uid, String name) async {
    final ws = await WebSocket.connect('ws://127.0.0.1:${http.port}/ws');
    final w = Wire(ws);
    w.send('hello', {'protocol': 1, 'token': 'test:$uid', 'name': name});
    await w.waitFor('welcome');
    return w;
  }

  test('health check and landing text over real HTTP', () async {
    final c = HttpClient();
    final r = await (await c.getUrl(Uri.parse('http://127.0.0.1:${http.port}/healthz'))).close();
    expect(r.statusCode, 200);
    expect(await utf8.decoder.bind(r).join(), 'ok');
    final root = await (await c.getUrl(Uri.parse('http://127.0.0.1:${http.port}/'))).close();
    expect(root.statusCode, 200);
    c.close();
  });

  test('two real sockets: create, join, start, play a move', () async {
    final a = await connect('alice1', 'Alice');
    final b = await connect('bobby2', 'Bobby');
    a.send('create_room');
    final created = await a.waitFor('room_state');
    final code = created['code'] as String;
    expect(isValidRoomCode(code), isTrue);

    b.send('join_room', {'code': code});
    await b.waitFor('room_state', where: (m) => m['status'] == 'lobby');
    b.send('ready', {'ready': true});
    await a.waitFor('room_state', where: (m) => (m['players'] as List).any((p) => p['userId'] == 'bobby2' && p['ready'] == true));
    a.send('start');
    final started = await a.waitFor('game_state');
    expect((started['snapshot'] as Map)['hand0'], 9);

    final room = await a.waitFor('room_state', where: (m) => m['status'] == 'playing');
    final seat0 = (room['players'] as List).firstWhere((p) => p['seat'] == 0)['userId'];
    final firstWire = seat0 == 'alice1' ? a : b;
    final otherWire = seat0 == 'alice1' ? b : a;
    firstWire.send('place', {'to': 9});
    final after = await otherWire.waitFor('game_state', where: (m) => (m['snapshot'] as Map)['mask0'] == 1 << 9);
    expect((after['lastMove'] as Map)['to'], 9);

    await a.ws.close();
    await b.ws.close();
  });

  test('the same checks apply over the wire: a stranger gets a typed error', () async {
    final a = await connect('alice1', 'Alice');
    a.send('join_room', {'code': 'ZZZZZZ'});
    final err = await a.waitFor('error');
    expect(err['code'], ErrorCodes.roomNotFound);
    await a.ws.close();
  });

  test('stopping the server closes open sockets cleanly (a deploy sends SIGTERM)', () async {
    final ws = await WebSocket.connect('ws://127.0.0.1:${http.port}/ws');
    ws.add(jsonEncode({'v': 1, 't': 'hello', 'protocol': 1, 'token': 'test:alice1', 'name': 'Alice'}));
    final welcomed = Completer<void>();
    final closed = Completer<int?>();
    ws.listen((m) {
      if ((jsonDecode(m as String) as Map)['t'] == 'welcome' && !welcomed.isCompleted) welcomed.complete();
    }, onDone: () => closed.complete(ws.closeCode));
    await welcomed.future.timeout(const Duration(seconds: 5));
    await server.stop(); // must not throw
    expect(await closed.future.timeout(const Duration(seconds: 5)), CloseCodes.goingAway);
  });
}
