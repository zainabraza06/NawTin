import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:naw_tin_core/naw_tin_core.dart';

import 'auth_provider.dart';
import 'online_config.dart';
import 'transport.dart';

enum ConnPhase { idle, connecting, online, reconnecting, stopped }

/// Why we gave up instead of retrying. Each has its own designed screen.
enum StopReason { outdated, unauthorized, replaced, authUnavailable, notConfigured }

/// What last went wrong while (re)connecting.
enum Problem { unreachable, handshakeTimeout, dropped, rateLimited }

class ConnectionState {
  const ConnectionState(this.phase, {this.stopReason, this.problem, this.attempt = 0, this.retryAt});
  const ConnectionState.idle() : this(ConnPhase.idle);

  final ConnPhase phase;
  final StopReason? stopReason;
  final Problem? problem;

  /// Consecutive failed attempts so far (0 when connected).
  final int attempt;

  /// When the next automatic retry happens (while reconnecting).
  final DateTime? retryAt;

  bool get isOnline => phase == ConnPhase.online;
  bool get isStopped => phase == ConnPhase.stopped;

  @override
  String toString() => 'ConnectionState($phase, stop: $stopReason, problem: $problem, attempt: $attempt)';
}

class OnlineProfile {
  const OnlineProfile(this.name, this.avatar);
  final String name;
  final int avatar;
}

class _Out {
  _Out(this.seq, this.type, this.payload);
  final int seq;
  final String type;
  final Map<String, Object?> payload;
}

/// The connection to the online server.
///
/// * Handshake: `hello` (ID token, name, optional room to resume) -> `welcome`.
/// * Heartbeat every 15 s; a connection silent for 40 s is treated as dead.
/// * Reconnects forever with exponential backoff (0.5 s ... 8 s, +-25% jitter)
///   unless the server says never to: outdated app (4000 / unsupported_version),
///   replaced by another device (4002), or sign-in refused twice (4001).
/// * After every reconnect the server sends a **full** `room_state` +
///   `game_state`; nothing is replayed from local state.
/// * Sequenced messages are numbered per room and stay in an outbox until the
///   server acknowledges them, so they survive drops and rate limits (resent
///   with the same number).
/// * It **never** sends `leave` by itself. Closing, backgrounding or losing the
///   connection are all just drops; only an explicit `send(Msg.leave)` forfeits.
class OnlineService {
  OnlineService({
    required this.config,
    required this.auth,
    required this.transport,
    required this.scheduler,
    required this.profile,
    required this.resumeCode,
    Random? random,
    this.appVersion = '',
  }) : _random = random ?? Random();

  final OnlineConfig config;
  final AuthTokenProvider auth;
  final Transport transport;
  final Scheduler scheduler;

  /// Current display name / avatar (read at every handshake).
  final OnlineProfile Function() profile;

  /// The room to resume after a reconnect (the stored room id), if any.
  final String? Function() resumeCode;
  final Random _random;
  final String appVersion;

  static const heartbeat = Duration(seconds: 15);
  static const deadAfter = Duration(seconds: 40);
  static const handshakeTimeout = Duration(seconds: 8);
  static const maxBackoff = Duration(seconds: 8);

  final StreamController<Map<String, Object?>> _messages = StreamController.broadcast();
  final StreamController<ConnectionState> _states = StreamController.broadcast();
  ConnectionState _state = const ConnectionState.idle();

  /// Every server message after the handshake (`welcome`, `room_state`,
  /// `game_state`, `event`, `error`).
  Stream<Map<String, Object?>> get messages => _messages.stream;
  Stream<ConnectionState> get states => _states.stream;
  ConnectionState get state => _state;

  String? userId;
  int pingMs = 0;

  // ---- connection bookkeeping ----
  TransportChannel? _ch;
  StreamSubscription<String>? _sub;
  bool _wantOnline = false;
  int _gen = 0;
  int _attempt = 0;
  bool _refreshToken = false;
  bool _triedRefresh = false;
  DateTime _helloAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastIncoming = DateTime.fromMillisecondsSinceEpoch(0);
  void Function()? _retryCancel, _heartbeatCancel, _handshakeCancel, _flushCancel;
  int _pingCounter = 0;
  final Map<int, DateTime> _pingSent = {};

  // ---- clock offset (server - client), from the smallest-round-trip sample ----
  final List<({int rtt, int offset})> _samples = [];
  int offsetMs = 0;

  /// The server's clock now, corrected for the offset (both phones agree).
  int get serverNowMs => scheduler.now().millisecondsSinceEpoch + offsetMs;

  // ---- sequenced outbox ----
  int _seq = 0;
  int _sentUpTo = 0;
  bool _awaitingSync = false;
  DateTime? _blockedUntil;
  final List<_Out> _outbox = [];
  int get pendingCount => _outbox.length;
  int get lastSeq => _seq;

  // ===================================================================
  // public API
  // ===================================================================

  /// Starts (or resumes) the connection and keeps it alive.
  Future<void> connect() async {
    if (_wantOnline && (_state.phase == ConnPhase.online || _state.phase == ConnPhase.connecting)) return;
    _wantOnline = true;
    _attempt = 0;
    _triedRefresh = false;
    await _open();
  }

  /// Closes the connection without telling the server anything ("leave" is a
  /// separate, explicit message).
  Future<void> disconnect() async {
    _wantOnline = false;
    _teardown();
    _emit(const ConnectionState.idle());
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _states.close();
  }

  /// The app came back to the foreground: reconnect right away if needed, or
  /// check the connection is alive.
  void appResumed() {
    if (!_wantOnline) return;
    if (_state.phase == ConnPhase.reconnecting) {
      _retryCancel?.call();
      _attempt = 0;
      _open();
    } else if (_state.isOnline) {
      _sendPing();
    }
  }

  /// The app went to the background. Deliberately does nothing: the OS may drop
  /// the socket, which is then handled like any other drop. It must never leave.
  void appPaused() {}

  /// Starts numbering from 1 again: call before creating / joining a different room.
  void newRoom() {
    _seq = 0;
    _sentUpTo = 0;
    _outbox.clear();
    _awaitingSync = false;
    _blockedUntil = null;
  }

  /// Sends a room-level message with the next sequence number. It is kept
  /// until acknowledged and resent after a reconnect or a rate-limit.
  int send(String type, [Map<String, Object?> payload = const {}]) {
    assert(Msg.sequenced.contains(type), '$type is not a sequenced message');
    final seq = ++_seq;
    _outbox.add(_Out(seq, type, payload));
    _flush();
    return seq;
  }

  /// Sends a connection-level message (`create_room`, `join_room`). Returns
  /// false if there is no live connection.
  bool sendNow(String type, [Map<String, Object?> payload = const {}]) {
    final ch = _ch;
    if (ch == null || !_state.isOnline) return false;
    ch.send(jsonEncode({'v': protocolVersion, 't': type, ...payload}));
    return true;
  }

  // ===================================================================
  // connecting
  // ===================================================================

  Future<void> _open() async {
    if (!_wantOnline) return;
    final url = config.url;
    if (url == null) {
      _stopWith(StopReason.notConfigured);
      return;
    }
    final gen = ++_gen;
    _emit(ConnectionState(ConnPhase.connecting, attempt: _attempt, problem: _state.problem));

    String token;
    try {
      token = await auth.idToken(forceRefresh: _refreshToken);
      _refreshToken = false;
    } on AuthUnavailable {
      if (gen == _gen) _stopWith(StopReason.authUnavailable);
      return;
    } catch (_) {
      if (gen == _gen) _scheduleRetry(Problem.unreachable);
      return;
    }
    if (gen != _gen || !_wantOnline) return;

    TransportChannel ch;
    try {
      ch = await transport.connect(url);
    } catch (_) {
      if (gen == _gen) _scheduleRetry(Problem.unreachable);
      return;
    }
    if (gen != _gen || !_wantOnline) {
      unawaited(ch.close());
      return;
    }
    _ch = ch;
    _lastIncoming = scheduler.now();
    _sub = ch.incoming.listen(
      (raw) => _onFrame(gen, raw),
      onDone: () => _onClosed(gen),
      onError: (Object _) => _onClosed(gen),
      cancelOnError: true,
    );

    final p = profile();
    final resume = resumeCode();
    _helloAt = scheduler.now();
    ch.send(jsonEncode({
      'v': protocolVersion,
      't': Msg.hello,
      'protocol': protocolVersion,
      'token': token,
      'name': p.name,
      'avatar': p.avatar,
      'appVersion': appVersion,
      if (resume != null) 'resume': resume,
    }));
    _awaitingSync = resume != null;
    _handshakeCancel = scheduler.after(handshakeTimeout, () {
      if (gen == _gen && !_state.isOnline) _loseConnection(gen, Problem.handshakeTimeout);
    });
  }

  void _onFrame(int gen, String raw) {
    if (gen != _gen) return;
    _lastIncoming = scheduler.now();
    Map<String, Object?> m;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['t'] is! String) return;
      m = j.cast<String, Object?>();
    } catch (_) {
      return; // ignore what we cannot read (forward compatible)
    }
    final ack = m['ack'];
    if (ack is int) _outbox.removeWhere((o) => o.seq <= ack);

    switch (m['t']) {
      case Msg.welcome:
        _handshakeCancel?.call();
        userId = m['userId'] as String?;
        _attempt = 0;
        _triedRefresh = false;
        final rtt = _lastIncoming.difference(_helloAt).inMilliseconds;
        _addSample(rtt, m['ts']);
        _emit(const ConnectionState(ConnPhase.online));
        _startHeartbeat(gen);
        if (m['resume'] == null) _awaitingSync = false; // nothing to resync
        _messages.add(m);
        _flush();
      case Msg.pong:
        final n = m['n'];
        final sent = n is int ? _pingSent.remove(n) : null;
        if (sent != null) {
          final rtt = _lastIncoming.difference(sent).inMilliseconds;
          pingMs = rtt;
          _addSample(rtt, m['ts']);
        }
      case Msg.ack:
        _flush();
      case Msg.error:
        _onError(gen, m);
      case Msg.roomState:
        _noteProcessed(m);
        if (_awaitingSync) _syncFrom(m);
        _messages.add(m);
      default:
        _messages.add(m);
    }
  }

  void _onError(int gen, Map<String, Object?> m) {
    final code = m['code'];
    if (code == ErrorCodes.unsupportedVersion) {
      _messages.add(m);
      _stopWith(StopReason.outdated);
      return;
    }
    if (code == ErrorCodes.seqGap) {
      _awaitingSync = true; // the server resyncs us with a full room_state next
    } else if (code == ErrorCodes.rateLimited && m['ref'] is int) {
      // not processed and its number was not used up: resend it as it was
      final wait = Duration(milliseconds: (m['retryAfterMs'] is int ? m['retryAfterMs'] as int : 1000) + 50);
      _sentUpTo = min(_sentUpTo, (m['ref'] as int) - 1);
      _blockedUntil = scheduler.now().add(wait);
      _flushCancel?.call();
      _flushCancel = scheduler.after(wait, _flush);
    }
    _messages.add(m);
  }

  /// The highest of my messages the server has processed, from `room_state`.
  int? _processedIn(Map<String, Object?> room) {
    for (final p in (room['players'] as List? ?? const [])) {
      if (p is Map && p['userId'] == userId && p['lastSeq'] is int) return p['lastSeq'] as int;
    }
    return null;
  }

  /// My counter must never be behind the server's: after an app kill it starts
  /// again at 0 while the server remembers the room's last number, and a lower
  /// number would be dropped as a duplicate.
  void _noteProcessed(Map<String, Object?> room) {
    final processed = _processedIn(room);
    if (processed != null && processed > _seq) {
      _seq = processed;
      _sentUpTo = max(_sentUpTo, processed);
    }
  }

  /// Aligns the outbox with what the server has processed (after a reconnect
  /// or a `seq_gap`): drop what it has, resend the rest in order.
  void _syncFrom(Map<String, Object?> room) {
    final processed = _processedIn(room);
    if (processed == null) return;
    _awaitingSync = false;
    _outbox.removeWhere((o) => o.seq <= processed);
    _sentUpTo = processed;
    if (_seq < processed) _seq = processed;
    _flush();
  }

  void _flush() {
    final ch = _ch;
    if (ch == null || !_state.isOnline || _awaitingSync) return;
    final blocked = _blockedUntil;
    if (blocked != null) {
      if (scheduler.now().isBefore(blocked)) return;
      _blockedUntil = null;
    }
    for (final o in _outbox) {
      if (o.seq <= _sentUpTo) continue;
      ch.send(jsonEncode({'v': protocolVersion, 't': o.type, 'seq': o.seq, ...o.payload}));
      _sentUpTo = o.seq;
    }
  }

  // ===================================================================
  // heartbeat and clock offset
  // ===================================================================

  void _startHeartbeat(int gen) {
    _heartbeatCancel?.call();
    _heartbeatCancel = scheduler.every(heartbeat, () {
      if (gen != _gen) return;
      if (scheduler.now().difference(_lastIncoming) > deadAfter) {
        _loseConnection(gen, Problem.dropped);
        return;
      }
      _sendPing();
    });
  }

  void _sendPing() {
    final ch = _ch;
    if (ch == null) return;
    final n = ++_pingCounter;
    _pingSent[n] = scheduler.now();
    if (_pingSent.length > 8) _pingSent.remove(_pingSent.keys.first);
    ch.send(jsonEncode({'v': protocolVersion, 't': Msg.ping, 'n': n, 'rtt': pingMs}));
  }

  /// offset = serverTs - (clientSendTime + rtt / 2); the sample with the
  /// smallest round trip is the most trustworthy.
  void _addSample(int rtt, Object? serverTs) {
    if (serverTs is! int) return;
    final receivedAt = scheduler.now().millisecondsSinceEpoch;
    final offset = serverTs - (receivedAt - rtt ~/ 2);
    _samples.add((rtt: rtt, offset: offset));
    if (_samples.length > 8) _samples.removeAt(0);
    var best = _samples.first;
    for (final s in _samples) {
      if (s.rtt < best.rtt) best = s;
    }
    offsetMs = best.offset;
  }

  // ===================================================================
  // losing and regaining the connection
  // ===================================================================

  void _onClosed(int gen) {
    if (gen != _gen) return;
    final code = _ch?.closeCode;
    _releaseChannel();
    if (!_wantOnline) return;
    switch (code) {
      case CloseCodes.outdated:
        _stopWith(StopReason.outdated);
      case CloseCodes.replaced:
        _stopWith(StopReason.replaced);
      case CloseCodes.unauthorized:
        if (_triedRefresh) {
          _stopWith(StopReason.unauthorized);
        } else {
          _triedRefresh = true; // ask for a fresh token once, then try again
          _refreshToken = true;
          _scheduleRetry(Problem.dropped, minimum: Duration.zero);
        }
      case CloseCodes.rateLimited:
        _scheduleRetry(Problem.rateLimited, minimum: const Duration(seconds: 30));
      default:
        _scheduleRetry(Problem.dropped);
    }
  }

  void _loseConnection(int gen, Problem why) {
    if (gen != _gen) return;
    final ch = _ch;
    _releaseChannel();
    if (ch != null) unawaited(ch.close(4000 + 99, 'lost'));
    if (_wantOnline) _scheduleRetry(why);
  }

  void _scheduleRetry(Problem why, {Duration? minimum}) {
    _attempt++;
    final baseMs = min(maxBackoff.inMilliseconds, 500 * (1 << min(_attempt - 1, 6)));
    final jittered = (baseMs * (0.75 + 0.5 * _random.nextDouble())).round();
    var delay = Duration(milliseconds: jittered);
    if (minimum != null && delay < minimum) delay = minimum;
    _retryCancel?.call();
    final gen = ++_gen; // invalidates any stale callbacks
    _emit(ConnectionState(ConnPhase.reconnecting,
        problem: why, attempt: _attempt, retryAt: scheduler.now().add(delay)));
    _retryCancel = scheduler.after(delay, () {
      if (gen == _gen) _open();
    });
  }

  void _stopWith(StopReason reason) {
    _wantOnline = false;
    _teardown();
    _emit(ConnectionState(ConnPhase.stopped, stopReason: reason));
  }

  void _releaseChannel() {
    _heartbeatCancel?.call();
    _handshakeCancel?.call();
    _heartbeatCancel = _handshakeCancel = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _ch = null;
    _pingSent.clear();
  }

  void _teardown() {
    _gen++;
    _retryCancel?.call();
    _flushCancel?.call();
    final ch = _ch;
    _releaseChannel();
    if (ch != null) unawaited(ch.close(1000, 'bye'));
  }

  void _emit(ConnectionState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}
