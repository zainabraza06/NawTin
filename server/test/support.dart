import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:naw_tin_server/naw_tin_server.dart';
import 'package:test/test.dart';

/// Lets queued microtasks and zero-delay futures run (the server is async).
Future<void> pump([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// In-memory socket: the "client side" is driven by the test.
class FakeChannel implements ClientChannel {
  FakeChannel(this.ip);
  @override
  final String ip;

  final StreamController<String> _in = StreamController<String>();
  final List<Map<String, Object?>> received = [];
  int? closeCode;
  String? closeReason;

  @override
  Stream<String> get incoming => _in.stream;

  @override
  void send(String data) => received.add((jsonDecode(data) as Map).cast<String, Object?>());

  @override
  Future<void> close(int code, String reason) async {
    closeCode ??= code;
    closeReason ??= reason;
    if (!_in.isClosed) await _in.close();
  }

  bool get isClosed => _in.isClosed;

  void clientSend(Object? frame) => _in.add(frame is String ? frame : jsonEncode(frame));

  /// The network dropped (no `leave` was sent).
  Future<void> drop() async {
    if (!_in.isClosed) await _in.close();
  }
}

/// A scripted client that numbers its sequenced messages like the real app.
class TestClient {
  TestClient(this.server, this.uid, {this.name = 'Player', String? ip})
      : ch = FakeChannel(ip ?? 'ip-$uid') {
    server.attach(ch);
  }

  final NawTinServer server;
  final String uid;
  final String name;
  FakeChannel ch;
  int seq = 0;
  void Function(TestClient)? onReconnect;

  Future<void> hello({String? resume, String? token, int protocol = protocolVersion, String? nameOverride}) async {
    ch.clientSend({
      'v': 1,
      't': 'hello',
      'protocol': protocol,
      'token': token ?? 'test:$uid',
      'name': nameOverride ?? name,
      if (resume != null) 'resume': resume,
    });
    await pump();
  }

  Future<void> send(String t, [Map<String, Object?> payload = const {}, int? seqOverride]) async {
    // sequence numbers are per user per room: a new room starts again at 1
    if (t == Msg.createRoom) seq = 0;
    if (t == Msg.joinRoom && normalizeRoomCode('${payload['code']}') != code) seq = 0;
    final sequenced = Msg.sequenced.contains(t);
    final s = sequenced ? (seqOverride ?? ++seq) : null;
    ch.clientSend({'v': 1, 't': t, if (s != null) 'seq': s, ...payload});
    await pump();
  }

  /// Reconnects with a brand-new socket (the old one is dropped first).
  Future<void> reconnect({String? resume, String? ip}) async {
    await ch.drop();
    await pump();
    ch = FakeChannel(ip ?? 'ip-$uid');
    server.attach(ch);
    await hello(resume: resume);
    onReconnect?.call(this);
  }

  // ---- what the server sent ----
  List<Map<String, Object?>> ofType(String t) => ch.received.where((m) => m['t'] == t).toList();
  Map<String, Object?>? last(String t) => ofType(t).isEmpty ? null : ofType(t).last;
  Map<String, Object?> get room => last('room_state')!;
  Map<String, Object?> get game => last('game_state')!;
  List<Map<String, Object?>> events([String? kind]) =>
      ofType('event').where((e) => kind == null || e['kind'] == kind).toList();
  List<Map<String, Object?>> errors() => ofType('error');
  String? get lastErrorCode => errors().isEmpty ? null : errors().last['code'] as String;

  String? get code => last('room_state')?['code'] as String?;

  List<Map<String, Object?>> get players => (room['players'] as List).cast<Map<String, Object?>>();
  Map<String, Object?> get me => players.firstWhere((p) => p['userId'] == uid);
  int? get seat => me['seat'] as int?;
  String get status => room['status'] as String;

  GameState get state => decodeSnapshot(game['snapshot']);
  Map<String, Object?>? get clockInfo => game['clock'] as Map<String, Object?>?;

  void clearInbox() => ch.received.clear();
}

class TestEnv {
  TestEnv({ServerConfig? config, int seed = 1})
      : clock = FakeClock(),
        config = config ?? const ServerConfig(testAuth: true) {
    server = NawTinServer(
      config: this.config,
      verifier: TestTokenVerifier(),
      clock: clock,
      ai: DirectAiService(),
      random: Random(seed),
      log: (e, [f = const {}]) {},
    );
  }

  final FakeClock clock;
  final ServerConfig config;
  late final NawTinServer server;

  final List<TestClient> _clients = [];

  /// Moves fake time forward in 10 s steps. Connected clients send their
  /// 15 s heartbeat like the real app, so only dropped ones go quiet.
  Future<void> advance(Duration d, {bool heartbeats = true}) async {
    var left = d;
    while (left > Duration.zero) {
      final step = left > const Duration(seconds: 10) ? const Duration(seconds: 10) : left;
      if (heartbeats) {
        for (final c in _clients) {
          if (!c.ch.isClosed) c.ch.clientSend({'v': 1, 't': 'ping', 'n': 0});
        }
        await pump(2);
      }
      clock.advance(step);
      await pump(3);
      left -= step;
    }
  }

  Future<TestClient> client(String uid, {String? name, String? ip, bool hello = true}) async {
    final c = TestClient(server, uid, name: name ?? 'P$uid', ip: ip);
    _clients.add(c);
    if (hello) await c.hello();
    return c;
  }

  Room roomOf(String code) => server.manager.rooms[code]!;

  /// host + guest in a lobby, guest ready (the host has not started yet).
  Future<(TestClient host, TestClient guest)> lobby({String hostId = 'hostA', String guestId = 'guestB'}) async {
    final host = await client(hostId, name: 'Hosty');
    await host.send(Msg.createRoom);
    final guest = await client(guestId, name: 'Guesty');
    await guest.send(Msg.joinRoom, {'code': host.code});
    await guest.send(Msg.ready, {'ready': true});
    return (host, guest);
  }

  /// A game in progress. Returns clients ordered by seat: first moves first.
  Future<(TestClient first, TestClient second)> startedGame() async {
    final (host, guest) = await lobby();
    await host.send(Msg.start);
    expect(host.status, 'playing');
    return host.seat == 0 ? (host, guest) : (guest, host);
  }
}

/// A step for whoever is to move: usually the Easy AI's choice (so games end),
/// otherwise a random legal step (so they are varied).
Move pickMove(GameState s, Random rnd) {
  if (rnd.nextDouble() < 0.7) {
    return Searcher(AiConfig.easy.withTime(25)).search(s).move;
  }
  final steps = Rules.stepMoves(s);
  return steps[rnd.nextInt(steps.length)];
}

/// Sends the step for [c] and, if the server asks for a capture, answers it
/// (with the AI's choice when it had one).
Future<void> playOne(TestClient c, Random rnd) async {
  final s = c.state;
  final move = pickMove(s, rnd);
  final asked = c.events(EventKind.captureRequired).length;
  await c.send(move.isPlacement ? Msg.place : Msg.move, {
    'to': move.to,
    if (!move.isPlacement) 'from': move.from,
  });
  final need = c.events(EventKind.captureRequired);
  if (need.length > asked) {
    final targets = ((need.last['data'] as Map)['targets'] as List).cast<int>();
    final pick = move.hasCapture && targets.contains(move.capture)
        ? move.capture
        : targets[rnd.nextInt(targets.length)];
    await c.send(Msg.capture, {'point': pick});
  }
}
