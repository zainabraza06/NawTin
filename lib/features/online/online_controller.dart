import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

import '../../services/online/auth_provider.dart';
import '../../services/online/firebase_auth_provider.dart';
import '../../services/online/online_config.dart';
import '../../services/online/online_service.dart';
import '../../services/online/transport.dart';
import '../../services/prefs_store.dart';
import 'online_state.dart';

// ----------------------------------------------------------------------------
// providers
// ----------------------------------------------------------------------------

/// DEBUG BUILDS ONLY: a server address typed into the debug console (saved on
/// the device), so one debug APK works on any network without a rebuild. In
/// release builds this is always null.
class DebugServerController extends Notifier<String?> {
  static const _key = 'debug.server';

  @override
  String? build() {
    if (!kDebugMode) return null;
    final v = ref.read(prefsStoreProvider).read(_key);
    return (v == null || v.isEmpty) ? null : v;
  }

  void set(String? address) {
    if (!kDebugMode) return;
    final v = address?.trim();
    ref.read(prefsStoreProvider).write(_key, v ?? '');
    state = (v == null || v.isEmpty) ? null : v;
  }
}

final debugServerProvider = NotifierProvider<DebugServerController, String?>(DebugServerController.new);

final onlineConfigProvider = Provider<OnlineConfig>(
  (ref) => OnlineConfig.fromEnvironment(override: ref.watch(debugServerProvider)),
);
final onlineTransportProvider = Provider<Transport>((ref) => const WebSocketTransport());
final onlineSchedulerProvider = Provider<Scheduler>((ref) => const SystemScheduler());

/// The sign-in used for online play. Debug builds get the fake-token path (for
/// a server in test mode); release builds get [UnavailableAuth] until Firebase
/// sign-in is wired in.
/// Debug builds use the fake test token unless built with
/// `--dart-define=NAWTIN_REAL_AUTH=1`; release builds always use Firebase.
const _realAuthInDebug = bool.fromEnvironment('NAWTIN_REAL_AUTH');

final onlineAuthProvider = Provider<AuthTokenProvider>(
  (ref) => createAuth(
    debug: kDebugMode,
    store: ref.read(prefsStoreProvider),
    random: Random(),
    real: (!kDebugMode || _realAuthInDebug) ? FirebaseAuthProvider() : null,
  ),
);

/// Display name + avatar for online play, saved on the device.
class OnlineProfileController extends Notifier<OnlineProfile> {
  static const _key = 'online.profile';

  @override
  OnlineProfile build() {
    final raw = ref.read(prefsStoreProvider).read(_key);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map;
        final name = validateName(j['name'] as String?);
        if (name != null) return OnlineProfile(name, (j['avatar'] as int?) ?? 0);
      } catch (_) {}
    }
    final fresh = OnlineProfile(generateName(Random()), 0);
    _save(fresh);
    return fresh;
  }

  void _save(OnlineProfile p) =>
      ref.read(prefsStoreProvider).write(_key, jsonEncode({'name': p.name, 'avatar': p.avatar}));

  /// Returns false if [name] is not acceptable (same rules as the server).
  bool setName(String name) {
    final ok = validateName(name);
    if (ok == null) return false;
    state = OnlineProfile(ok, state.avatar);
    _save(state);
    return true;
  }

  void setAvatar(int avatar) {
    state = OnlineProfile(state.name, avatar.clamp(0, 15));
    _save(state);
  }
}

final onlineProfileProvider = NotifierProvider<OnlineProfileController, OnlineProfile>(OnlineProfileController.new);

const _roomKey = 'online.room';

/// The saved room id, or null (an empty string is how a cleared one is stored).
String? _storedRoom(PrefsStore store) {
  final v = store.read(_roomKey);
  return (v == null || v.isEmpty) ? null : v;
}

final onlineServiceProvider = Provider<OnlineService>((ref) {
  final store = ref.read(prefsStoreProvider);
  final service = OnlineService(
    config: ref.watch(onlineConfigProvider),
    auth: ref.watch(onlineAuthProvider),
    transport: ref.watch(onlineTransportProvider),
    scheduler: ref.watch(onlineSchedulerProvider),
    profile: () => ref.read(onlineProfileProvider),
    resumeCode: () => _storedRoom(store),
    appVersion: '0.1.0',
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

// ----------------------------------------------------------------------------
// controller
// ----------------------------------------------------------------------------

/// Mirrors the server. The client never applies a move as final: it sends what
/// it wants, shows a light optimistic highlight, and renders what the server
/// confirms in `game_state`.
class OnlineGameController extends Notifier<OnlineState> {
  StreamSubscription<Map<String, Object?>>? _msgSub;
  StreamSubscription<ConnectionState>? _stateSub;
  int _eventSerial = 0;

  OnlineService get _service => ref.read(onlineServiceProvider);
  PrefsStore get _store => ref.read(prefsStoreProvider);

  @override
  OnlineState build() {
    final service = ref.watch(onlineServiceProvider);
    _msgSub = service.messages.listen(_onMessage);
    _stateSub = service.states.listen(_onConnection);
    ref.onDispose(() {
      _msgSub?.cancel();
      _stateSub?.cancel();
    });
    return OnlineState(conn: service.state, rejoinCode: _storedRoom(_store));
  }

  // ---------------------------------------------------------------- actions

  /// Opens the connection (and keeps it alive).
  Future<void> connect() => _service.connect();

  /// Closes the connection. Does NOT leave the room or forfeit.
  Future<void> disconnect() => _service.disconnect();

  void clearError() => state = state.copyWith(error: null);

  void createRoom() {
    if (!_requireOnline()) return;
    _resetRoomView();
    _service.newRoom();
    _service.sendNow(Msg.createRoom);
  }

  void joinRoom(String raw) {
    if (!_requireOnline()) return;
    final code = normalizeRoomCode(raw);
    if (!isValidRoomCode(code)) {
      state = state.copyWith(error: const OnlineError(ErrorCodes.roomNotFound, "That code doesn't look right."));
      return;
    }
    if (code != state.roomCode) {
      _resetRoomView();
      _service.newRoom();
    }
    _service.sendNow(Msg.joinRoom, {'code': code});
  }

  /// "Rejoin game" after an app restart.
  void rejoin() {
    final code = state.rejoinCode;
    if (code == null) return;
    if (!_requireOnline()) return;
    // same room: keep the sequence counter, the server tells us where it is
    _service.sendNow(Msg.joinRoom, {'code': code});
  }

  void setReady(bool ready) => _service.send(Msg.ready, {'ready': ready});
  void start() => _service.send(Msg.start);

  void place(int to) {
    if (!_canAct) return;
    state = state.copyWith(optimistic: Move.place(to), error: null);
    _service.send(Msg.place, {'to': to});
  }

  void move(int from, int to) {
    if (!_canAct) return;
    state = state.copyWith(optimistic: Move.slide(from, to), error: null);
    _service.send(Msg.move, {'from': from, 'to': to});
  }

  void capture(int point) {
    final g = state.game;
    if (!_canAct || g?.pendingStep == null) return;
    _service.send(Msg.capture, {'point': point});
  }

  void pressPhutas() => _service.send(Msg.pressPhutas);
  void emote(String id) => _service.send(Msg.emote, {'id': id});
  void offerRematch() => _service.send(Msg.offerRematch);
  void acceptRematch() => _service.send(Msg.acceptRematch);

  /// The confirmed "Leave game" button, and nothing else: it forfeits a live
  /// game on the spot. Backgrounding, closing the app or losing the connection
  /// must never come through here.
  void leaveGame() {
    if (state.room == null) return;
    _service.send(Msg.leave);
    _clearStoredRoom();
  }

  /// App lifecycle. Coming back reconnects at once; going away does nothing
  /// (and certainly never leaves the room).
  void onLifecycle(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _service.appResumed();
    } else {
      _service.appPaused();
    }
  }

  // ---------------------------------------------------------------- clock

  /// The server's clock right now (client time + measured offset).
  int get serverNow => _service.serverNowMs;

  /// Milliseconds left on the server's clock, corrected for the measured
  /// offset so both phones show the same number.
  int remainingMs() {
    final c = state.game?.clock;
    if (c == null) return 0;
    return max(0, c.deadlineServerMs - _service.serverNowMs);
  }

  // ---------------------------------------------------------------- guards

  bool get _canAct => state.inGame && state.myTurn;

  bool _requireOnline() {
    if (state.conn.isOnline) return true;
    state = state.copyWith(error: const OnlineError('not_connected', "You're not connected to the server yet."));
    return false;
  }

  void _resetRoomView() {
    state = state.copyWith(room: null, game: null, error: null, roomEnd: null, optimistic: null, lastResult: null, opponentReconnectDeadlineMs: null);
  }

  // ------------------------------------------------------------- incoming

  void _onConnection(ConnectionState c) {
    state = state.copyWith(conn: c, pingMs: _service.pingMs, offsetMs: _service.offsetMs);
  }

  void _onMessage(Map<String, Object?> m) {
    try {
      switch (m['t']) {
        case Msg.welcome:
          _onWelcome(m);
        case Msg.roomState:
          _onRoomState(m);
        case Msg.gameState:
          _onGameState(m);
        case Msg.event:
          _onEvent(m);
        case Msg.error:
          _onError(m);
      }
    } catch (e) {
      // a malformed message must never take the screen down
      if (kDebugMode) debugPrint('online: ignored bad ${m['t']}: $e');
    }
    state = state.copyWith(pingMs: _service.pingMs, offsetMs: _service.offsetMs);
  }

  void _onWelcome(Map<String, Object?> m) {
    final server = (m['resume'] as Map?)?['code'] as String?;
    state = state.copyWith(userId: m['userId'] as String?);
    if (server != null) {
      // the server still has our room: offer / perform the rejoin
      _store.write(_roomKey, server);
      state = state.copyWith(rejoinCode: server);
    } else {
      // the server does not know any room of ours (expired, closed, restarted)
      final inRoom = state.room != null && state.room!.status != 'closed';
      _clearStoredRoom();
      if (inRoom) state = state.copyWith(game: null, roomEnd: RoomEnd.closed);
    }
  }

  void _onRoomState(Map<String, Object?> m) {
    final room = RoomView.fromJson(m);
    var next = state.copyWith(room: room, roomEnd: null);
    final opp = room.opponentOf(state.userId);
    if (opp != null && opp.connected) next = next.copyWith(opponentReconnectDeadlineMs: null);
    state = next;
    switch (room.status) {
      case 'waiting':
      case 'lobby':
      case 'playing':
        _store.write(_roomKey, room.code);
        state = state.copyWith(rejoinCode: room.code);
      case 'finished':
        _clearStoredRoom(); // a finished game is not something to rejoin
      case 'closed':
        _clearStoredRoom();
        state = state.copyWith(roomEnd: RoomEnd.closed, game: null);
    }
  }

  void _onGameState(Map<String, Object?> m) {
    final snapshot = decodeSnapshot(m['snapshot']);
    final pend = m['pending'] as Map?;
    final clock = m['clock'] as Map?;
    final lm = m['lastMove'] as Map?;
    final ph = m['phutas'] as Map?;
    final stats = (m['stats'] as Map?) ?? const {};
    List<int> ints(Object? v) => [for (final e in (v as List? ?? const [0, 0])) e as int];

    ({int seat, Move move})? lastMove;
    if (lm != null) lastMove = (seat: lm['seat'] as int, move: decodeMove(lm));
    int targets = 0;
    Move? pendingStep;
    if (pend != null) {
      for (final t in (pend['targets'] as List)) {
        targets |= bit(t as int);
      }
      final from = pend['from'] as int;
      pendingStep = from < 0 ? Move.place(pend['to'] as int) : Move.slide(from, pend['to'] as int);
    }

    final prev = state.game;
    final game = GameView(
      state: snapshot,
      rev: (m['rev'] as int?) ?? 0,
      pendingStep: pendingStep,
      pendingTargets: targets,
      clock: clock == null
          ? null
          : ClockView(
              seat: clock['seat'] as int,
              deadlineServerMs: clock['deadline'] as int,
              totalMs: clock['totalMs'] as int,
            ),
      timeouts: ints(m['timeouts']),
      eaten: ints(stats['eaten']),
      lines: ints(stats['lines']),
      swings: ints(stats['swings']),
      phutas: ph == null ? null : (seat: ph['seat'] as int, lines: ph['lines'] as int),
      lastMove: lastMove,
      endReason: snapshotEndReason(m['snapshot']),
    );

    // a new confirmed move: re-derive its animation from the previous
    // confirmed position (only when it lines up exactly)
    MoveResult? result;
    var fx = state.fxSerial;
    final isNewMove = pend == null && lastMove != null && prev != null && prev.state != snapshot;
    if (isNewMove) {
      try {
        final r = MoveResult.resolve(prev.state, lastMove.move);
        if (r.after == snapshot) {
          result = r;
          fx++;
        }
      } catch (_) {}
    }
    state = state.copyWith(
      game: game,
      optimistic: null,
      lastResult: result ?? (isNewMove ? null : state.lastResult),
      fxSerial: fx,
      error: null,
    );
  }

  void _onEvent(Map<String, Object?> m) {
    final kind = m['kind'] as String;
    final data = ((m['data'] as Map?) ?? const {}).cast<String, Object?>();
    final ev = OnlineEvent(++_eventSerial, (m['rev'] as int?) ?? 0, kind, m['seat'] as int?, data);
    final events = [...state.events, ev];
    if (events.length > 60) events.removeRange(0, events.length - 60);
    var next = state.copyWith(events: events);
    switch (kind) {
      case EventKind.disconnected:
        next = next.copyWith(opponentReconnectDeadlineMs: data['reconnectDeadline'] as int?);
      case EventKind.reconnected:
        next = next.copyWith(opponentReconnectDeadlineMs: null);
      case EventKind.gameOver:
        _clearStoredRoom();
        next = next.copyWith(rejoinCode: null);
    }
    state = next;
  }

  void _onError(Map<String, Object?> m) {
    final code = (m['code'] as String?) ?? 'internal';
    final err = OnlineError(code, (m['message'] as String?) ?? 'Something went wrong.', retryAfterMs: m['retryAfterMs'] as int?);
    RoomEnd? end;
    switch (code) {
      case ErrorCodes.roomNotFound:
        end = RoomEnd.notFound;
      case ErrorCodes.roomExpired:
        end = RoomEnd.expired;
      case ErrorCodes.roomClosed:
        end = RoomEnd.closed;
      case ErrorCodes.roomFull:
        end = RoomEnd.full;
    }
    if (end == RoomEnd.notFound || end == RoomEnd.expired || end == RoomEnd.closed) {
      _clearStoredRoom();
    }
    // a rejected move: drop the optimistic highlight, the server state stands
    state = state.copyWith(error: err, optimistic: null, roomEnd: end ?? state.roomEnd);
  }

  void _clearStoredRoom() {
    _store.write(_roomKey, '');
    state = state.copyWith(rejoinCode: null);
  }
}

final onlineControllerProvider = NotifierProvider<OnlineGameController, OnlineState>(OnlineGameController.new);
