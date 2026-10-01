import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth.dart';
import 'clock.dart';
import 'config.dart';
import 'rate_limiter.dart';
import 'room.dart';

/// A client connection as the server sees it (a real WebSocket in production,
/// an in-memory fake in tests).
abstract class ClientChannel {
  Stream<String> get incoming;
  void send(String data);
  Future<void> close(int code, String reason);

  /// For rate limiting only. Never logged or stored.
  String get ip;
}

/// [ClientChannel] over a shelf WebSocket.
class SocketChannel implements ClientChannel {
  SocketChannel(this._ch, this.ip);
  final WebSocketChannel _ch;
  @override
  final String ip;

  @override
  Stream<String> get incoming => _ch.stream.where((e) => e is String).cast<String>();

  @override
  void send(String data) => _ch.sink.add(data);

  @override
  Future<void> close(int code, String reason) async {
    try {
      await _ch.sink.close(code, reason);
    } catch (_) {
      // already closed, or the platform refused the code: never let a close
      // failure break shutdown or another player's game
    }
  }
}

/// Tracks live rooms, who is in which, and recently expired codes.
class RoomManager {
  RoomManager(this.clock, this.random);

  final ServerClock clock;
  final Random random;
  final Map<String, Room> rooms = {};
  final Map<String, String> _userRoom = {};
  final Map<String, DateTime> _expired = {};

  Room? roomOfUser(String uid) {
    final code = _userRoom[uid];
    final r = code == null ? null : rooms[code];
    return (r != null && r.isOpen) ? r : null;
  }

  void bind(String uid, String code) => _userRoom[uid] = code;
  void unbind(String uid, String code) {
    if (_userRoom[uid] == code) _userRoom.remove(uid);
  }

  /// A fresh code from [roomCodeAlphabet], unique among live rooms.
  String generateCode() {
    for (var i = 0; i < 100; i++) {
      final code = List.generate(roomCodeLength, (_) => roomCodeAlphabet[random.nextInt(roomCodeAlphabet.length)]).join();
      if (!rooms.containsKey(code)) return code;
    }
    throw StateError('could not allocate a room code');
  }

  void remember(Room room, {required bool expired}) {
    rooms.remove(room.code);
    if (expired) _expired[room.code] = clock.now().add(const Duration(minutes: 10));
  }

  bool wasExpired(String code) {
    final until = _expired[code];
    if (until == null) return false;
    if (clock.now().isAfter(until)) {
      _expired.remove(code);
      return false;
    }
    return true;
  }
}

class _Session {
  _Session(this.ch, this.lastFrame);
  final ClientChannel ch;
  DateTime lastFrame;
  AuthUser? user;
  String name = '';
  int avatar = 0;
  RoomPlayer? player;
  Room? room;
  bool closed = false;
  bool helloBusy = false;
  int badFrames = 0;
  Cancel? helloTimer;
}

/// The online server. Feed it connections with [attach]; [serve] wires that
/// to a real HTTP port.
class NawTinServer {
  NawTinServer({
    required this.config,
    required this.verifier,
    ServerClock? clock,
    AiService? ai,
    Random? random,
    LogFn? log,
  })  : clock = clock ?? const SystemClock(),
        ai = ai ?? IsolateAiService(),
        random = random ?? Random.secure(),
        log = log ?? _stdoutLog {
    manager = RoomManager(this.clock, this.random);
    limiter = RateLimiter(this.clock);
    _sweep = this.clock.every(const Duration(seconds: 10), _heartbeatSweep);
  }

  final ServerConfig config;
  final TokenVerifier verifier;
  final ServerClock clock;
  final AiService ai;
  final Random random;
  final LogFn log;
  late final RoomManager manager;
  late final RateLimiter limiter;
  final Map<String, _Session> _sessions = {};
  final Set<_Session> _all = {};
  Cancel? _sweep;
  HttpServer? _http;

  static void _stdoutLog(String event, [Map<String, Object?> fields = const {}]) {
    // structured, anonymous: user ids and room codes only
    stdout.writeln(jsonEncode({'ts': DateTime.now().toUtc().toIso8601String(), 'event': event, ...fields}));
  }

  int get sessionCount => _all.length;

  // ----------------------------------------------------------------- http

  Handler get handler => (Request req) {
        switch (req.url.path) {
          case 'healthz':
            return Response.ok('ok');
          case 'ws':
            return webSocketHandler((WebSocketChannel ch) {
              final fwd = req.headers['x-forwarded-for']?.split(',').first.trim();
              final conn = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
              attach(SocketChannel(ch, fwd ?? conn?.remoteAddress.address ?? 'unknown'));
            })(req);
          case '':
            return Response.ok('Naw Tin online server (protocol $protocolVersion)');
          default:
            return Response.notFound('not found');
        }
      };

  Future<HttpServer> serve({int? port}) async {
    final s = await shelf_io.serve(handler, InternetAddress.anyIPv4, port ?? config.port);
    _http = s;
    return s;
  }

  Future<void> stop() async {
    _sweep?.call();
    for (final s in [..._all]) {
      await s.ch.close(CloseCodes.goingAway, 'server stopping');
    }
    await _http?.close(force: true);
  }

  // ------------------------------------------------------------ connections

  void attach(ClientChannel ch) {
    final s = _Session(ch, clock.now());
    _all.add(s);
    if (!limiter.allow('conn:${ch.ip}', limit: 20, window: const Duration(minutes: 1))) {
      _send(s, _errorMsg(ErrorCodes.rateLimited, 'Too many connections. Try again in a minute.', fatal: true));
      _close(s, CloseCodes.rateLimited, 'rate limited');
      return;
    }
    s.helloTimer = clock.after(Duration(seconds: config.helloTimeoutSeconds), () {
      if (s.user == null) _close(s, CloseCodes.unauthorized, 'hello timeout');
    });
    ch.incoming.listen(
      (raw) => unawaited(_onFrame(s, raw)),
      onDone: () => _onClosed(s),
      onError: (_) => _onClosed(s),
      cancelOnError: true,
    );
  }

  void _close(_Session s, int code, String reason) {
    if (s.closed) return;
    unawaited(s.ch.close(code, reason));
    _onClosed(s);
  }

  void _onClosed(_Session s) {
    if (s.closed) return;
    s.closed = true;
    s.helloTimer?.call();
    _all.remove(s);
    final uid = s.user?.uid;
    if (uid != null && _sessions[uid] == s) {
      _sessions.remove(uid);
      // an unplanned drop: the room keeps the seat for the reconnect window
      final p = s.player;
      s.room?.detach(p!);
    }
  }

  void _heartbeatSweep() {
    final now = clock.now();
    for (final s in [..._all]) {
      if (now.difference(s.lastFrame) > Duration(seconds: config.idleTimeoutSeconds)) {
        _close(s, 1000, 'idle');
      }
    }
    limiter.sweep(const Duration(minutes: 15));
  }

  // --------------------------------------------------------------- frames

  void _send(_Session s, Map<String, Object?> msg) {
    if (s.closed) return;
    s.ch.send(jsonEncode({'v': protocolVersion, 'ts': clock.now().millisecondsSinceEpoch, ...msg}));
  }

  Map<String, Object?> _errorMsg(String code, String message, {bool fatal = false, Object? ref, Object? id, int? retryAfterMs}) => {
        't': Msg.error,
        'code': code,
        'message': message,
        'fatal': fatal,
        if (ref != null) 'ref': ref,
        if (id != null) 'id': id,
        if (retryAfterMs != null) 'retryAfterMs': retryAfterMs,
      };

  Future<void> _onFrame(_Session s, String raw) async {
    if (s.closed) return;
    s.lastFrame = clock.now();
    if (utf8.encode(raw).length > config.maxFrameBytes) {
      _send(s, _errorMsg(ErrorCodes.badRequest, 'Message too large.', fatal: true));
      _close(s, CloseCodes.rateLimited, 'frame too large');
      return;
    }
    Map<String, Object?> m;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['t'] is! String) throw const FormatException();
      m = j.cast<String, Object?>();
    } catch (_) {
      if (++s.badFrames >= 5) {
        _send(s, _errorMsg(ErrorCodes.badRequest, 'Too many malformed messages.', fatal: true));
        _close(s, CloseCodes.rateLimited, 'bad frames');
      } else {
        _send(s, _errorMsg(ErrorCodes.badRequest, 'That message could not be read.'));
      }
      return;
    }
    final t = m['t'] as String;
    try {
      if (t == Msg.hello) {
        await _hello(s, m);
        return;
      }
      final user = s.user;
      if (user == null) {
        _send(s, _errorMsg(ErrorCodes.unauthorized, 'Say hello first.', fatal: true));
        _close(s, CloseCodes.unauthorized, 'no hello');
        return;
      }
      if (t == Msg.ping) {
        final rtt = m['rtt'];
        if (rtt is int && s.player != null) s.player!.pingMs = rtt.clamp(0, 9999);
        _send(s, {'t': Msg.pong, 'n': m['n']});
        return;
      }
      if (!limiter.allow('msg:${user.uid}', limit: 20, window: const Duration(seconds: 10))) {
        _send(s, _errorMsg(ErrorCodes.rateLimited, 'Slow down a little.', ref: m['seq'], retryAfterMs: limiter.retryAfterMs('msg:${user.uid}', window: const Duration(seconds: 10))));
        return;
      }
      switch (t) {
        case Msg.createRoom:
          _createRoom(s, m);
        case Msg.joinRoom:
          _joinRoom(s, m);
        default:
          final room = s.room;
          final player = s.player;
          if (room == null || player == null || !room.isOpen) {
            _send(s, _errorMsg(ErrorCodes.notInRoom, "You're not in a room.", ref: m['seq']));
            return;
          }
          if (t == Msg.emote && !_emoteAllowed(user.uid)) {
            _send(s, _errorMsg(ErrorCodes.rateLimited, 'Easy on the emotes.', ref: m['seq'], retryAfterMs: 3000));
            return;
          }
          room.receive(player, t, m);
          if (t == Msg.leave) {
            // an explicit leave detaches this connection from the room
            if (!room.isOpen || room.playerById(user.uid) == null) {
              s.room = null;
              s.player = null;
            }
          }
      }
    } catch (e, st) {
      log('server.internal_error', {'error': '$e', 'stack': '$st'});
      _send(s, _errorMsg(ErrorCodes.internal, 'Something went wrong on the server.', ref: m['seq']));
    }
  }

  bool _emoteAllowed(String uid) =>
      limiter.allow('emote3:$uid', limit: 1, window: const Duration(seconds: 3)) &&
      limiter.allow('emote60:$uid', limit: 6, window: const Duration(minutes: 1));

  // ---------------------------------------------------------------- hello

  Future<void> _hello(_Session s, Map<String, Object?> m) async {
    if (s.user != null || s.helloBusy) {
      _send(s, _errorMsg(ErrorCodes.badRequest, 'Already connected.'));
      return;
    }
    s.helloBusy = true;
    final proto = m['protocol'];
    if (proto is! int || proto < minProtocolVersion) {
      _send(s, _errorMsg(ErrorCodes.unsupportedVersion, 'Please update the app to play online.', fatal: true)..['minProtocol'] = minProtocolVersion);
      _close(s, CloseCodes.outdated, 'outdated client');
      return;
    }
    final token = m['token'];
    final user = token is String ? await verifier.verify(token) : null;
    s.helloBusy = false;
    if (s.closed) return;
    if (user == null) {
      _send(s, _errorMsg(ErrorCodes.unauthorized, 'Sign-in failed. Please try again.', fatal: true));
      _close(s, CloseCodes.unauthorized, 'bad token');
      return;
    }
    final name = validateName(m['name'] as String?);
    if (name == null) {
      _send(s, _errorMsg(ErrorCodes.nameInvalid, 'Please pick another name (2-16 letters, numbers or spaces).'));
      return;
    }
    final avatarRaw = m['avatar'];
    s.avatar = avatarRaw is int ? avatarRaw.clamp(0, 15) : 0;
    s.name = name;
    s.user = user;
    s.helloTimer?.call();

    // one connection per user: the newest wins
    final old = _sessions[user.uid];
    _sessions[user.uid] = s;
    if (old != null && old != s) {
      _send(old, _errorMsg(ErrorCodes.unauthorized, 'You opened Naw Tin on another device.', fatal: true));
      old.closed = true; // keep the room seat: the new session takes over
      _all.remove(old);
      unawaited(old.ch.close(CloseCodes.replaced, 'replaced'));
    }

    final room = manager.roomOfUser(user.uid);
    _send(s, {
      't': Msg.welcome,
      'userId': user.uid,
      'protocol': protocolVersion,
      'minProtocol': minProtocolVersion,
      if (room != null) 'resume': {'code': room.code, 'status': room.status.name},
    });
    log('session.start', {'user': user.uid});

    final resume = m['resume'];
    if (room != null && resume is String && normalizeRoomCode(resume) == room.code) {
      _reattach(s, room);
    } else if (room != null && old != null) {
      // same device lost its socket and reconnected without asking: resume anyway
      _reattach(s, room);
    }
  }

  void _reattach(_Session s, Room room) {
    final p = room.playerById(s.user!.uid);
    if (p == null) return;
    s.room = room;
    s.player = p;
    room.attach(p, (msg) => _send(s, msg));
  }

  // ---------------------------------------------------------------- rooms

  void _createRoom(_Session s, Map<String, Object?> m) {
    final uid = s.user!.uid;
    if (manager.roomOfUser(uid) != null) {
      _send(s, _errorMsg(ErrorCodes.alreadyInRoom, 'You are already in a room. Rejoin it or leave it first.'));
      return;
    }
    if (!limiter.allow('create:$uid', limit: 5, window: const Duration(minutes: 10))) {
      _send(s, _errorMsg(ErrorCodes.rateLimited, 'You created too many rooms. Try again later.', retryAfterMs: limiter.retryAfterMs('create:$uid', window: const Duration(minutes: 10))));
      return;
    }
    final code = manager.generateCode();
    final host = RoomPlayer(uid, s.name, s.avatar, null);
    final room = Room(
      code: code,
      host: host,
      config: config,
      clock: clock,
      ai: ai,
      random: random,
      log: log,
      onPlayerGone: (u) => manager.unbind(u, code),
      onClosed: (r, {required bool expired}) => manager.remember(r, expired: expired),
    );
    manager.rooms[code] = room;
    manager.bind(uid, code);
    log('room.created', {'room': code, 'user': uid});
    _reattach(s, room);
  }

  void _joinRoom(_Session s, Map<String, Object?> m) {
    final uid = s.user!.uid;
    final ip = s.ch.ip;
    final raw = m['code'];
    final code = raw is String ? normalizeRoomCode(raw) : '';

    // guard against code guessing
    const oneMinute = Duration(minutes: 1);
    const tenMinutes = Duration(minutes: 10);
    // five failed attempts in a row lock joining for a minute
    final locked = limiter.count('fail:$uid', window: oneMinute) >= 5;
    if (locked ||
        !limiter.allow('joinu:$uid', limit: 10, window: tenMinutes) ||
        !limiter.allow('joinip:$ip', limit: 30, window: tenMinutes)) {
      _send(s, _errorMsg(ErrorCodes.rateLimited, 'Too many tries. Wait a minute and try again.',
          retryAfterMs: locked ? limiter.retryAfterMs('fail:$uid', window: oneMinute) : 60000));
      return;
    }

    final mine = manager.roomOfUser(uid);
    if (mine != null) {
      if (mine.code == code) {
        _reattach(s, mine); // rejoining my own room
        return;
      }
      _send(s, _errorMsg(ErrorCodes.alreadyInRoom, 'You are already in another room.'));
      return;
    }

    void miss(String errCode, String message) {
      limiter.allow('fail:$uid', limit: 1 << 30, window: oneMinute); // record the failure
      _send(s, _errorMsg(errCode, message));
    }

    if (!isValidRoomCode(code)) return miss(ErrorCodes.roomNotFound, "That code doesn't look right.");
    final room = manager.rooms[code];
    if (room == null || !room.isOpen) {
      if (manager.wasExpired(code)) return miss(ErrorCodes.roomExpired, 'That room has expired. Ask your friend for a new code.');
      return miss(ErrorCodes.roomNotFound, "We couldn't find that room.");
    }
    final guest = RoomPlayer(uid, s.name, s.avatar, null);
    try {
      room.join(guest);
    } on RoomError catch (e) {
      return miss(e.code, e.message);
    }
    manager.bind(uid, code);
    _reattach(s, room);
  }
}
