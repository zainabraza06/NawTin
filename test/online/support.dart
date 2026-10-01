import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:naw_tin_server/naw_tin_server.dart' as srv;
import 'package:nawtin/services/online/transport.dart';

/// Lets queued microtasks and zero-delay futures run.
Future<void> pump([int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The client's [Scheduler] on top of the server package's fake clock, with an
/// optional skew so a phone's clock can disagree with the server's.
class ClockScheduler implements Scheduler {
  ClockScheduler(this.clock, {this.skewMs = 0});
  final srv.FakeClock clock;
  final int skewMs;

  @override
  DateTime now() => clock.now().add(Duration(milliseconds: skewMs));

  @override
  void Function() after(Duration d, void Function() f) => clock.after(d, f);

  @override
  void Function() every(Duration d, void Function() f) => clock.every(d, f);
}

// ----------------------------------------------------------------------------
// a scripted server, for unit-testing the connection layer on its own
// ----------------------------------------------------------------------------

class ScriptedChannel implements TransportChannel {
  final StreamController<String> _in = StreamController<String>();
  final List<Map<String, Object?>> sent = [];
  int? _closeCode;
  bool get isClosed => _in.isClosed;

  @override
  Stream<String> get incoming => _in.stream;

  @override
  void send(String data) => sent.add((jsonDecode(data) as Map).cast<String, Object?>());

  @override
  Future<void> close([int? code, String? reason]) async {
    _closeCode ??= code;
    if (!_in.isClosed) await _in.close();
  }

  @override
  int? get closeCode => _closeCode;

  // ---- the "server" side ----
  void serverSend(Map<String, Object?> m) {
    if (!_in.isClosed) _in.add(jsonEncode({'v': 1, ...m}));
  }

  void serverClose(int code) {
    _closeCode = code;
    if (!_in.isClosed) _in.close();
  }

  /// The network died: closed with no close code.
  void networkDrop() {
    if (!_in.isClosed) _in.close();
  }

  List<Map<String, Object?>> of(String t) => sent.where((m) => m['t'] == t).toList();
  Map<String, Object?>? get hello => of('hello').isEmpty ? null : of('hello').first;
}

class ScriptedTransport implements Transport {
  final List<ScriptedChannel> channels = [];
  Object? failWith;
  int attempts = 0;

  ScriptedChannel get last => channels.last;

  @override
  Future<TransportChannel> connect(Uri url) async {
    attempts++;
    if (failWith != null) throw failWith!;
    final ch = ScriptedChannel();
    channels.add(ch);
    return ch;
  }
}

// ----------------------------------------------------------------------------
// the real server, in-process
// ----------------------------------------------------------------------------

/// Two in-memory pipes joined into one connection: [serverSide] is handed to
/// the real server, [clientSide] to the app's connection layer.
class PairChannel {
  PairChannel(this.ip);

  final String ip;
  final StreamController<String> _toServer = StreamController<String>();
  final StreamController<String> _toClient = StreamController<String>();
  int? _code;

  late final srv.ClientChannel serverSide = _Side(this, true);
  late final TransportChannel clientSide = _Side(this, false);

  /// The network died: both directions close, no close code.
  void networkDrop() {
    if (!_toClient.isClosed) _toClient.close();
    if (!_toServer.isClosed) _toServer.close();
  }
}

class _Side implements srv.ClientChannel, TransportChannel {
  _Side(this.p, this.isServer);
  final PairChannel p;
  final bool isServer;

  @override
  String get ip => p.ip;

  @override
  Stream<String> get incoming => isServer ? p._toServer.stream : p._toClient.stream;

  @override
  void send(String data) {
    final target = isServer ? p._toClient : p._toServer;
    if (!target.isClosed) target.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (isServer) p._code ??= code;
    p.networkDrop();
  }

  @override
  int? get closeCode => p._code;
}

/// A [Transport] whose far end is a real [srv.NawTinServer].
class InProcessTransport implements Transport {
  InProcessTransport(this.server, this.ip);
  final srv.NawTinServer server;
  final String ip;
  final List<PairChannel> open = [];
  bool refuse = false;

  @override
  Future<TransportChannel> connect(Uri url) async {
    if (refuse) throw StateError('server unreachable');
    final pair = PairChannel(ip);
    open.add(pair);
    server.attach(pair.serverSide);
    return pair.clientSide;
  }

  /// Cuts every live connection (a dead network, not a clean close).
  void dropAll() {
    for (final c in open) {
      c.networkDrop();
    }
    open.clear();
  }
}

Random seeded(int s) => Random(s);
