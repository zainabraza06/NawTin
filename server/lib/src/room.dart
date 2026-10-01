import 'dart:async';
import 'dart:math';

import 'package:naw_tin_core/naw_tin_core.dart';

import 'clock.dart';
import 'config.dart';

typedef Send = void Function(Map<String, Object?> message);
typedef LogFn = void Function(String event, [Map<String, Object?> fields]);

enum RoomStatus { waiting, lobby, playing, finished, closed }

/// A protocol-level rejection, turned into an `error` message by the caller.
class RoomError implements Exception {
  RoomError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class RoomPlayer {
  RoomPlayer(this.userId, this.name, this.avatar, this.send);

  final String userId;
  String name;
  int avatar;

  /// Null while the player is offline.
  Send? send;
  bool get connected => send != null;

  bool ready = false;
  int? seat;
  int lastSeq = 0;
  int pingMs = 0;

  DateTime? awayDeadline;
  Cancel? _awayTimer;
}

class _Pending {
  _Pending(this.step, this.targets);
  final Move step;
  final int targets; // bitmask of legal victims
}

/// One private room: the lobby and the game it hosts.
///
/// The room is the single source of truth. Clients only send intentions
/// ([receive]); everything is checked here with the shared rules engine, and
/// confirmed state is pushed back as `event`s followed by a `game_state`.
class Room {
  Room({
    required this.code,
    required RoomPlayer host,
    required this.config,
    required this.clock,
    required this.ai,
    required this.random,
    required this.log,
    required this.onPlayerGone,
    required this.onClosed,
  })  : hostId = host.userId,
        createdAt = clock.now() {
    players.add(host);
    _armExpiry();
  }

  final String code;
  final String hostId;
  final ServerConfig config;
  final ServerClock clock;
  final AiService ai;
  final Random random;
  final LogFn log;

  /// Called when a player leaves the room for good (so the user is free to join another).
  final void Function(String userId) onPlayerGone;
  final void Function(Room room, {required bool expired}) onClosed;

  final DateTime createdAt;
  final List<RoomPlayer> players = [];
  RoomStatus status = RoomStatus.waiting;
  int rev = 0;
  DateTime? expiresAt;

  // ---- game ----
  GameState? game;
  _Pending? _pending;
  int? coinFlipSeat0Index; // index into players at game start (info only)
  String? _coinFlipSeat0;
  List<int> timeouts = [0, 0];
  List<int> eaten = [0, 0], lines = [0, 0], swings = [0, 0];
  ({int seat, int lines})? _phutas;
  ({int seat, Move move})? _lastMove;
  String? _lastEvent;
  String? endReason;
  String? _rematchBy;

  // ---- clock ----
  int? _clockSeat;
  DateTime? _clockDeadline;
  int _clockToken = 0;
  bool _resolving = false; // an auto-move is being computed
  Cancel? _clockTimer, _expiryTimer, _rematchTimer;

  bool get isOpen => status != RoomStatus.closed;
  RoomPlayer? playerById(String id) {
    for (final p in players) {
      if (p.userId == id) return p;
    }
    return null;
  }

  RoomPlayer? _other(RoomPlayer p) {
    for (final q in players) {
      if (q != p) return q;
    }
    return null;
  }

  // ======================================================================
  // joining / connections
  // ======================================================================

  /// Adds the guest. Throws [RoomError] if the room cannot take them.
  void join(RoomPlayer guest) {
    if (status == RoomStatus.closed) throw RoomError(ErrorCodes.roomClosed, 'That room has closed.');
    if (players.length >= 2 || status != RoomStatus.waiting) {
      throw RoomError(ErrorCodes.roomFull, 'That room is already full.');
    }
    players.add(guest);
    status = RoomStatus.lobby;
    _armExpiry(); // the window starts again once a friend arrives
    log('room.joined', {'room': code, 'user': guest.userId});
    rev++;
    _broadcastRoom();
  }

  /// (Re)connects a player's socket: used right after create/join and when
  /// a dropped player returns. Always ends with a full resync for them.
  void attach(RoomPlayer p, Send send) {
    final wasAway = !p.connected && p.awayDeadline != null;
    p.send = send;
    p._awayTimer?.call();
    p._awayTimer = null;
    p.awayDeadline = null;
    if (wasAway && status == RoomStatus.playing) {
      rev++;
      _emitToOthers(p, _event(EventKind.reconnected, seat: p.seat));
    }
    rev++;
    _broadcastRoom();
    if (game != null) sendGameState(p);
  }

  /// The player's socket went away without a `leave`.
  void detach(RoomPlayer p) {
    if (!p.connected && p.awayDeadline != null) return;
    p.send = null;
    p.awayDeadline = clock.now().add(config.reconnect);
    p._awayTimer?.call();
    p._awayTimer = clock.after(config.reconnect, () => _awayExpired(p));
    log('room.disconnected', {'room': code, 'user': p.userId});
    rev++;
    if (status == RoomStatus.playing) {
      _emitToOthers(
        p,
        _event(EventKind.disconnected, seat: p.seat, data: {
          'seat': p.seat,
          'reconnectDeadline': p.awayDeadline!.millisecondsSinceEpoch,
          'reason': 'dropped',
        }),
      );
    }
    _broadcastRoom();
  }

  void _awayExpired(RoomPlayer p) {
    p._awayTimer = null;
    if (!isOpen || p.connected) return;
    switch (status) {
      case RoomStatus.playing:
        // did not come back inside the window: forfeit
        _finish(game!.disqualify(p.seat!), EndReason.abandoned);
      case RoomStatus.waiting:
      case RoomStatus.lobby:
        if (p.userId == hostId) {
          close();
        } else {
          _removePlayer(p);
        }
      case RoomStatus.finished:
        _removePlayer(p);
        if (!players.any((q) => q.connected)) close();
      case RoomStatus.closed:
        break;
    }
  }

  void _removePlayer(RoomPlayer p) {
    p._awayTimer?.call();
    players.remove(p);
    onPlayerGone(p.userId);
    if (status == RoomStatus.lobby) {
      status = RoomStatus.waiting;
      for (final q in players) {
        q.ready = false;
      }
    }
    rev++;
    _broadcastRoom();
  }

  /// Closes the room and tells whoever is still connected.
  void close({bool expired = false}) {
    if (status == RoomStatus.closed) return;
    status = RoomStatus.closed;
    for (final c in [_clockTimer, _expiryTimer, _rematchTimer]) {
      c?.call();
    }
    _clockTimer = _expiryTimer = _rematchTimer = null;
    _clockToken++;
    rev++;
    _broadcastRoom();
    for (final p in players) {
      p._awayTimer?.call();
      onPlayerGone(p.userId);
    }
    log('room.closed', {'room': code, 'expired': expired});
    onClosed(this, expired: expired);
  }

  void _armExpiry() {
    _expiryTimer?.call();
    expiresAt = clock.now().add(config.roomLife);
    _expiryTimer = clock.after(config.roomLife, () {
      if (status == RoomStatus.waiting || status == RoomStatus.lobby) close(expired: true);
    });
  }

  // ======================================================================
  // incoming messages
  // ======================================================================

  /// Handles one room-level client message from [p].
  void receive(RoomPlayer p, String type, Map<String, Object?> m) {
    final seq = m['seq'];
    if (Msg.sequenced.contains(type)) {
      if (seq is! int || seq < 1) {
        _error(p, RoomError(ErrorCodes.badRequest, 'Missing sequence number.'), m);
        return;
      }
      if (seq <= p.lastSeq) {
        // duplicate: already processed, just repeat the acknowledgement
        _to(p, {'t': Msg.ack});
        return;
      }
      if (seq > p.lastSeq + 1) {
        _error(p, RoomError(ErrorCodes.seqGap, 'Messages were missed; resyncing.'), m);
        _to(p, _roomStateMsg());
        sendGameState(p);
        return;
      }
      p.lastSeq = seq;
    }
    try {
      _dispatch(p, type, m);
    } on RoomError catch (e) {
      _error(p, e, m);
    } catch (e, st) {
      log('room.internal_error', {'room': code, 'error': '$e', 'stack': '$st'});
      _error(p, RoomError(ErrorCodes.internal, 'Something went wrong on the server.'), m);
    }
  }

  /// Throws away a sequenced message that was rate limited but must not be
  /// retried (an emote). In the normal case (the next number) the number is
  /// consumed and acknowledged; a duplicate or a gap is handled as usual.
  void discard(RoomPlayer p, Map<String, Object?> m) {
    final seq = m['seq'];
    if (seq is int && seq == p.lastSeq + 1) {
      p.lastSeq = seq;
      _to(p, {'t': Msg.ack});
      return;
    }
    receive(p, Msg.emote, m); // duplicate / gap / missing number: the usual handling
  }

  void _dispatch(RoomPlayer p, String type, Map<String, Object?> m) {
    if (status == RoomStatus.closed) throw RoomError(ErrorCodes.roomClosed, 'That room has closed.');
    switch (type) {
      case Msg.ready:
        if (status != RoomStatus.lobby && status != RoomStatus.waiting) return;
        p.ready = m['ready'] == true;
        rev++;
        _broadcastRoom();
      case Msg.start:
        _start(p);
      case Msg.place:
        _place(p, m);
      case Msg.move:
        _slide(p, m);
      case Msg.capture:
        _capture(p, m);
      case Msg.pressPhutas:
        _pressPhutas(p);
      case Msg.emote:
        final id = m['id'];
        if (id is! String || !emoteIds.contains(id)) {
          throw RoomError(ErrorCodes.emoteUnknown, 'Unknown emote.');
        }
        rev++;
        _emitAll(_event(EventKind.emote, seat: p.seat, data: {'seat': p.seat, 'id': id}));
      case Msg.offerRematch:
        _offerRematch(p);
      case Msg.acceptRematch:
        _acceptRematch(p);
      case Msg.leave:
        _leave(p);
      case Msg.report:
        _report(p, m);
      default:
        throw RoomError(ErrorCodes.badRequest, 'Unknown message.');
    }
  }

  // ======================================================================
  // lobby
  // ======================================================================

  void _start(RoomPlayer p) {
    if (p.userId != hostId) throw RoomError(ErrorCodes.notHost, 'Only the host can start the game.');
    if (status != RoomStatus.lobby) {
      throw RoomError(ErrorCodes.notReady, 'Wait for your friend to join first.');
    }
    final guest = _other(p)!;
    if (!guest.ready || !guest.connected) {
      throw RoomError(ErrorCodes.notReady, 'Your friend is not ready yet.');
    }
    _beginGame(rematch: false);
  }

  void _beginGame({required bool rematch}) {
    if (!rematch) {
      // fair coin flip for who moves first
      final firstIndex = random.nextBool() ? 0 : 1;
      coinFlipSeat0Index = firstIndex;
      players[firstIndex].seat = 0;
      players[1 - firstIndex].seat = 1;
    } else {
      // seats swap: whoever moved second last time now starts
      for (final p in players) {
        p.seat = 1 - p.seat!;
      }
    }
    _coinFlipSeat0 = players.firstWhere((p) => p.seat == 0).userId;
    game = GameState.initial();
    _reportedThisGame.clear();
    _pending = null;
    timeouts = [0, 0];
    eaten = [0, 0];
    lines = [0, 0];
    swings = [0, 0];
    _phutas = null;
    _lastMove = null;
    _lastEvent = null;
    endReason = null;
    _rematchBy = null;
    _rematchTimer?.call();
    _rematchTimer = null;
    _expiryTimer?.call();
    _expiryTimer = null;
    expiresAt = null;
    status = RoomStatus.playing;
    for (final p in players) {
      p.ready = false;
    }
    log('game.started', {'room': code, 'rematch': rematch});
    _startClock();
    rev++;
    _broadcastRoom();
    _broadcastGame();
  }

  // ======================================================================
  // moves
  // ======================================================================

  GameState _activeGame(RoomPlayer p) {
    final g = game;
    if (status != RoomStatus.playing || g == null || g.isOver) {
      throw RoomError(ErrorCodes.gameNotActive, 'The game is not in progress.');
    }
    if (_resolving || p.seat != g.turn) {
      throw RoomError(ErrorCodes.notYourTurn, "It's not your turn.");
    }
    return g;
  }

  int _point(Object? v, String name) {
    if (v is! int || v < 0 || v >= Board.pointCount) {
      throw RoomError(ErrorCodes.badRequest, 'Bad $name.');
    }
    return v;
  }

  void _place(RoomPlayer p, Map<String, Object?> m) {
    final g = _activeGame(p);
    if (_pending != null) throw RoomError(ErrorCodes.capturePending, 'Choose a token to eat first.');
    if (g.handOf(g.turn) == 0) throw RoomError(ErrorCodes.wrongPhase, 'All your tokens are placed; slide one instead.');
    _step(p, g, Move.place(_point(m['to'], 'point')));
  }

  void _slide(RoomPlayer p, Map<String, Object?> m) {
    final g = _activeGame(p);
    if (_pending != null) throw RoomError(ErrorCodes.capturePending, 'Choose a token to eat first.');
    if (g.handOf(g.turn) > 0) throw RoomError(ErrorCodes.wrongPhase, 'Place your tokens before sliding.');
    _step(p, g, Move.slide(_point(m['from'], 'point'), _point(m['to'], 'point')));
  }

  /// Validates a step with the shared engine. A step that completes a line is
  /// held (with its legal victims) until the player chooses what to eat.
  void _step(RoomPlayer p, GameState g, Move step) {
    if (!Rules.stepMoves(g).contains(step)) {
      throw RoomError(ErrorCodes.illegalMove, 'That move is not allowed.');
    }
    final targets = Rules.captureTargets(g, step);
    if (targets == 0) {
      _commit(p.seat!, step, auto: false);
      return;
    }
    _pending = _Pending(step, targets);
    rev++;
    _to(
      p,
      _event(EventKind.captureRequired, seat: p.seat, data: {
        'from': step.from,
        'to': step.to,
        'targets': bitsOf(targets).toList(),
      }),
    );
    _broadcastGame();
  }

  void _capture(RoomPlayer p, Map<String, Object?> m) {
    final g = _activeGame(p);
    final pend = _pending;
    if (pend == null) throw RoomError(ErrorCodes.noCapturePending, 'There is nothing to eat right now.');
    final point = _point(m['point'], 'point');
    // protected tokens are rejected unless every opponent token is protected
    // (that rule is already baked into pend.targets by the engine)
    if (pend.targets & bit(point) == 0) {
      throw RoomError(ErrorCodes.illegalCapture, 'You cannot eat that token.');
    }
    assert(Rules.isLegal(g, pend.step.withCapture(point)));
    _commit(p.seat!, pend.step.withCapture(point), auto: false);
  }

  void _pressPhutas(RoomPlayer p) {
    final ph = _phutas;
    if (status != RoomStatus.playing || ph == null || ph.seat != p.seat) return;
    _phutas = null;
    rev++;
    _emitAll(_event(EventKind.phutasPressed, seat: p.seat));
  }

  /// Applies a fully specified move (capture included) and announces it.
  void _commit(int seat, Move move, {required bool auto, List<Map<String, Object?>> pre = const []}) {
    final before = game!;
    final result = MoveResult.resolve(before, move);
    game = result.after;
    _pending = null;
    final events = <Map<String, Object?>>[...pre];
    events.add(move.isPlacement
        ? _event(EventKind.placed, seat: seat, data: {'to': move.to})
        : _event(EventKind.moved, seat: seat, data: {'from': move.from, 'to': move.to}));
    if (result.isMachyas) {
      eaten[seat]++;
      events.add(_event(EventKind.machyas, seat: seat, data: {'lines': result.completedLines}));
      events.add(_event(EventKind.eaten, seat: seat, data: {'point': move.capture, 'seat': 1 - seat}));
    }
    lines[seat] += popCount(result.completedLines);
    for (final e in result.swingEvents) {
      swings[e.seat]++;
    }
    final swing = result.announcedSwing;
    if (swing != null) {
      events.add(_event(
        swing.call == Call.treghi ? EventKind.treghi : EventKind.begi,
        seat: swing.seat,
        data: {'stops': swing.pattern.stops, 'ready': swing.readyOnly},
      ));
    }
    if (!auto) timeouts[seat] = 0; // only timeouts in a row count
    if (result.canPhutas && !result.after.isOver) {
      _phutas = (seat: seat, lines: result.phutasLines);
      events.add(_event(EventKind.phutasAvailable, seat: seat, data: {'lines': result.phutasLines}));
    } else {
      _phutas = null;
    }
    _lastMove = (seat: seat, move: move);
    if (result.after.isOver) {
      _finish(result.after, null, events: events);
      return;
    }
    _lastEvent = events.last['kind'] as String;
    _startClock();
    rev++;
    _flush(events);
  }

  // ======================================================================
  // clock and timeouts
  // ======================================================================

  void _startClock() {
    _clockTimer?.call();
    final g = game!;
    _clockSeat = g.turn;
    final delay = config.turn + Duration(milliseconds: config.graceMs);
    _clockDeadline = clock.now().add(delay);
    final token = ++_clockToken;
    _clockTimer = clock.after(delay, () => _onTimeout(token));
  }

  Future<void> _onTimeout(int token) async {
    if (token != _clockToken || status != RoomStatus.playing) return;
    final g = game!;
    final seat = g.turn;
    timeouts[seat]++;
    log('game.timeout', {'room': code, 'seat': seat, 'count': timeouts[seat]});

    if (timeouts[seat] >= 2) {
      // second timeout in a row: disqualified
      final ev = _event(EventKind.timeout, seat: seat, data: {
        'seat': seat,
        'count': timeouts[seat],
        'auto': false,
        'disqualified': true,
      });
      _pending = null;
      _finish(g.disqualify(seat), EndReason.disqualified, events: [ev]);
      return;
    }

    // first timeout: play a basic legal move for them (Easy-strength search,
    // never the Hard hint search), including the token to eat if a capture
    // was pending
    _resolving = true;
    Move move;
    try {
      move = await ai.chooseMove(g, AiConfig.easy.withTime(config.autoMoveMs), onlyStep: _pending?.step);
    } catch (_) {
      final legal = Rules.legalMoves(g);
      final step = _pending?.step;
      move = legal.firstWhere((m) => step == null || m.step == step, orElse: () => legal.first);
    }
    _resolving = false;
    if (token != _clockToken || status != RoomStatus.playing) return;
    _commit(
      seat,
      move,
      auto: true,
      pre: [
        _event(EventKind.timeout, seat: seat, data: {
          'seat': seat,
          'count': timeouts[seat],
          'auto': true,
          'disqualified': false,
        })
      ],
    );
  }

  // ======================================================================
  // game over, leaving, rematch
  // ======================================================================

  void _finish(GameState finalState, String? reasonOverride, {List<Map<String, Object?>> events = const []}) {
    game = finalState;
    status = RoomStatus.finished;
    _pending = null;
    _phutas = null;
    _clockTimer?.call();
    _clockTimer = null;
    _clockToken++;
    _clockSeat = null;
    _clockDeadline = null;
    endReason = reasonOverride ?? finalState.result!.reason.name;
    for (final p in players) {
      p._awayTimer?.call();
      p._awayTimer = null;
    }
    _rematchBy = null;
    _rematchTimer?.call();
    _rematchTimer = clock.after(config.rematchLife, () {
      if (status == RoomStatus.finished) close();
    });
    final r = finalState.result!;
    final out = [
      ...events,
      _event(EventKind.gameOver, data: {'winner': r.winner, 'reason': endReason}),
    ];
    _lastEvent = EventKind.gameOver;
    log('game.over', {'room': code, 'winner': r.winner, 'reason': endReason});
    rev++;
    _flush(out);
    _broadcastRoom();
  }

  void _leave(RoomPlayer p) {
    switch (status) {
      case RoomStatus.playing:
        // the explicit "Leave game" button is a deliberate, instant forfeit
        _finish(game!.disqualify(p.seat!), EndReason.forfeit);
      case RoomStatus.waiting:
      case RoomStatus.lobby:
        if (p.userId == hostId) {
          close();
        } else {
          _removePlayer(p);
        }
      case RoomStatus.finished:
        _removePlayer(p);
        if (players.isEmpty || !players.any((q) => q.connected)) close();
      case RoomStatus.closed:
        break;
    }
  }

  /// Reasons a player can give when reporting the other player.
  static const reportReasons = {'afk', 'abusive_name', 'cheating', 'other'};

  /// Reports recorded in this room (also written to the log). One per reporter
  /// per game; there is no automated action.
  final List<({String reporter, String reported, String reason, DateTime time})> reports = [];
  final Set<String> _reportedThisGame = {};

  void _report(RoomPlayer p, Map<String, Object?> m) {
    final reason = m['reason'];
    final target = m['userId'];
    if (reason is! String || !reportReasons.contains(reason)) {
      throw RoomError(ErrorCodes.badRequest, 'Pick a reason for the report.');
    }
    // you can only report someone who shared this room with you
    final other = target is String ? players.where((q) => q.userId == target && q.userId != p.userId) : const <RoomPlayer>[];
    if (other.isEmpty) throw RoomError(ErrorCodes.badRequest, 'You can only report the other player in this room.');
    if (!_reportedThisGame.add(p.userId)) return; // already reported this game: quietly accepted
    reports.add((reporter: p.userId, reported: other.first.userId, reason: reason, time: clock.now()));
    log('report.received', {'room': code, 'reporter': p.userId, 'reported': other.first.userId, 'reason': reason});
  }

  void _offerRematch(RoomPlayer p) {
    if (status != RoomStatus.finished || players.length < 2 || players.any((q) => !q.connected && q != p)) {
      throw RoomError(ErrorCodes.rematchUnavailable, 'A rematch is not available.');
    }
    if (_rematchBy == p.userId) return;
    if (_rematchBy != null) {
      _beginGame(rematch: true); // both asked: start
      return;
    }
    _rematchBy = p.userId;
    rev++;
    _broadcastRoom();
  }

  void _acceptRematch(RoomPlayer p) {
    if (status != RoomStatus.finished || _rematchBy == null || _rematchBy == p.userId || players.length < 2) {
      throw RoomError(ErrorCodes.rematchUnavailable, 'There is no rematch to accept.');
    }
    _beginGame(rematch: true);
  }

  // ======================================================================
  // outgoing messages
  // ======================================================================

  Map<String, Object?> _event(String kind, {int? seat, Map<String, Object?> data = const {}}) =>
      {'t': Msg.event, 'kind': kind, 'seat': seat, 'data': data};

  Map<String, Object?> _roomStateMsg() => {
        't': Msg.roomState,
        'code': code,
        'status': status.name,
        'expiresAt': expiresAt?.millisecondsSinceEpoch,
        'host': hostId,
        'mode': 'private',
        'players': [
          for (final p in players)
            {
              'userId': p.userId,
              'name': p.name,
              'avatar': p.avatar,
              'connected': p.connected,
              'ready': p.userId == hostId ? true : p.ready,
              'seat': p.seat,
              'pingMs': p.pingMs,
              'lastSeq': p.lastSeq,
              'rating': null,
            }
        ],
        'rules': {
          'placementRule': Rules.placementRule.name,
          'turnSeconds': config.turnSeconds,
          'reconnectSeconds': config.reconnectSeconds,
          'seatAssignment': 'coin_flip',
        },
        'coinFlip': _coinFlipSeat0 == null ? null : {'seat0': _coinFlipSeat0},
        'rematch': {'offeredBy': _rematchBy},
      };

  Map<String, Object?> _gameStateMsg() {
    final g = game!;
    final pend = _pending;
    final lm = _lastMove;
    final ph = _phutas;
    final finished = status == RoomStatus.finished;
    return {
      't': Msg.gameState,
      'snapshot': encodeSnapshot(g, endReasonOverride: finished ? endReason : null),
      'pending': pend == null
          ? null
          : {
              'from': pend.step.from,
              'to': pend.step.to,
              'targets': bitsOf(pend.targets).toList(),
            },
      'clock': _clockDeadline == null
          ? null
          : {
              'seat': _clockSeat,
              'deadline': _clockDeadline!.millisecondsSinceEpoch,
              'totalMs': config.turnSeconds * 1000,
              'graceMs': config.graceMs,
            },
      'timeouts': timeouts,
      'stats': {'eaten': eaten, 'lines': lines, 'swings': swings},
      'phutas': ph == null ? null : {'seat': ph.seat, 'lines': ph.lines},
      'lastMove': lm == null ? null : {'seat': lm.seat, ...encodeMove(lm.move)},
      'lastEvent': _lastEvent,
    };
  }

  Map<String, Object?> _wrap(RoomPlayer p, Map<String, Object?> msg) => {
        'v': protocolVersion,
        ...msg,
        'ts': clock.now().millisecondsSinceEpoch,
        'rev': rev,
        'ack': p.lastSeq,
      };

  void _to(RoomPlayer p, Map<String, Object?> msg) => p.send?.call(_wrap(p, msg));

  void _all(Map<String, Object?> msg) {
    for (final p in players) {
      _to(p, msg);
    }
  }

  void _emitAll(Map<String, Object?> event) {
    _all(event);
    if (game != null) _broadcastGame();
  }

  void _emitToOthers(RoomPlayer p, Map<String, Object?> event) {
    for (final q in players) {
      if (q != p) _to(q, event);
    }
    if (game != null) {
      for (final q in players) {
        if (q != p) _to(q, _gameStateMsg());
      }
    }
  }

  /// Events first, then the snapshot that closes the batch.
  void _flush(List<Map<String, Object?>> events) {
    for (final e in events) {
      _all(e);
    }
    _broadcastGame();
  }

  void _broadcastRoom() => _all(_roomStateMsg());
  void _broadcastGame() {
    if (game != null) _all(_gameStateMsg());
  }

  void sendGameState(RoomPlayer p) {
    if (game != null) _to(p, _gameStateMsg());
  }

  void sendRoomState(RoomPlayer p) => _to(p, _roomStateMsg());

  void _error(RoomPlayer p, RoomError e, Map<String, Object?> m) {
    _to(p, {
      't': Msg.error,
      'code': e.code,
      'message': e.message,
      'ref': m['seq'],
      if (m['id'] != null) 'id': m['id'],
      'fatal': false,
    });
  }
}
