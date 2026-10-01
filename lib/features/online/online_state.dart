import 'package:flutter/foundation.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

import '../../services/online/online_service.dart';

const Object _keep = Object();

@immutable
class PlayerView {
  const PlayerView({
    required this.userId,
    required this.name,
    required this.avatar,
    required this.connected,
    required this.ready,
    required this.seat,
    required this.pingMs,
  });

  final String userId;
  final String name;
  final int avatar;
  final bool connected;
  final bool ready;
  final int? seat;
  final int pingMs;

  static PlayerView fromJson(Map p) => PlayerView(
        userId: p['userId'] as String,
        name: (p['name'] as String?) ?? '?',
        avatar: (p['avatar'] as int?) ?? 0,
        connected: p['connected'] == true,
        ready: p['ready'] == true,
        seat: p['seat'] as int?,
        pingMs: (p['pingMs'] as int?) ?? 0,
      );
}

/// The lobby as the server last described it.
@immutable
class RoomView {
  const RoomView({
    required this.code,
    required this.status,
    required this.hostId,
    required this.players,
    required this.expiresAtMs,
    required this.turnSeconds,
    required this.reconnectSeconds,
    required this.coinFlipSeat0,
    required this.rematchOfferedBy,
    required this.placementRule,
  });

  final String code;

  /// waiting | lobby | playing | finished | closed
  final String status;
  final String hostId;
  final List<PlayerView> players;
  final int? expiresAtMs;
  final int turnSeconds;
  final int reconnectSeconds;

  /// userId of whoever got seat 0 in the coin flip.
  final String? coinFlipSeat0;
  final String? rematchOfferedBy;
  final String placementRule;

  PlayerView? player(String? uid) {
    for (final p in players) {
      if (p.userId == uid) return p;
    }
    return null;
  }

  PlayerView? opponentOf(String? uid) {
    for (final p in players) {
      if (p.userId != uid) return p;
    }
    return null;
  }

  static RoomView fromJson(Map m) {
    final rules = (m['rules'] as Map?) ?? const {};
    return RoomView(
      code: m['code'] as String,
      status: m['status'] as String,
      hostId: m['host'] as String,
      players: [for (final p in (m['players'] as List? ?? const [])) PlayerView.fromJson(p as Map)],
      expiresAtMs: m['expiresAt'] as int?,
      turnSeconds: (rules['turnSeconds'] as int?) ?? 120,
      reconnectSeconds: (rules['reconnectSeconds'] as int?) ?? 45,
      coinFlipSeat0: (m['coinFlip'] as Map?)?['seat0'] as String?,
      rematchOfferedBy: (m['rematch'] as Map?)?['offeredBy'] as String?,
      placementRule: (rules['placementRule'] as String?) ?? 'symmetricOpening',
    );
  }
}

/// The server's turn clock: whose turn it is and the absolute deadline in
/// SERVER time (the controller converts it with the measured offset).
@immutable
class ClockView {
  const ClockView({required this.seat, required this.deadlineServerMs, required this.totalMs});
  final int seat;
  final int deadlineServerMs;
  final int totalMs;
}

@immutable
class GameView {
  const GameView({
    required this.state,
    required this.rev,
    required this.pendingStep,
    required this.pendingTargets,
    required this.clock,
    required this.timeouts,
    required this.eaten,
    required this.lines,
    required this.swings,
    required this.phutas,
    required this.lastMove,
    required this.endReason,
  });

  final GameState state;
  final int rev;

  /// A step that completed a line and is waiting for the player to choose a
  /// token to eat, with the legal victims as a bitmask.
  final Move? pendingStep;
  final int pendingTargets;
  final ClockView? clock;
  final List<int> timeouts;
  final List<int> eaten, lines, swings;
  final ({int seat, int lines})? phutas;
  final ({int seat, Move move})? lastMove;

  /// Wire end reason (also `abandoned` / `forfeit`) once the game is over.
  final String? endReason;

  bool get isOver => state.isOver;
}

@immutable
class OnlineEvent {
  const OnlineEvent(this.serial, this.rev, this.kind, this.seat, this.data);
  final int serial;
  final int rev;
  final String kind;
  final int? seat;
  final Map<String, Object?> data;
}

@immutable
class OnlineError {
  const OnlineError(this.code, this.message, {this.retryAfterMs});
  final String code;
  final String message;
  final int? retryAfterMs;
}

/// Why a room is no longer usable (shown as its own designed state).
enum RoomEnd { closed, expired, notFound, full }

@immutable
class OnlineState {
  const OnlineState({
    this.conn = const ConnectionState.idle(),
    this.userId,
    this.room,
    this.game,
    this.error,
    this.events = const [],
    this.fxSerial = 0,
    this.lastResult,
    this.optimistic,
    this.roomEnd,
    this.rejoinCode,
    this.opponentReconnectDeadlineMs,
    this.pingMs = 0,
    this.offsetMs = 0,
  });

  final ConnectionState conn;
  final String? userId;
  final RoomView? room;
  final GameView? game;
  final OnlineError? error;
  final List<OnlineEvent> events;

  /// Bumps when a new confirmed move arrives that can be animated with the
  /// existing board (see [lastResult]).
  final int fxSerial;
  final MoveResult? lastResult;

  /// The step the player just asked for, shown lightly until the server
  /// confirms or rejects it. Never treated as final.
  final Move? optimistic;
  final RoomEnd? roomEnd;

  /// The room saved on this device ("Rejoin game").
  final String? rejoinCode;

  /// While the opponent is away: server time at which they forfeit.
  final int? opponentReconnectDeadlineMs;
  final int pingMs;
  final int offsetMs;

  // ---- derived ----
  bool get outdated => conn.stopReason == StopReason.outdated;
  String? get roomCode => room?.code;
  int? get mySeat => room?.player(userId)?.seat;
  PlayerView? get me => room?.player(userId);
  PlayerView? get opponent => room?.opponentOf(userId);
  bool get isHost => room != null && room!.hostId == userId;
  bool get inGame => room?.status == 'playing' && game != null;
  bool get myTurn => inGame && !game!.isOver && game!.state.turn == mySeat;

  OnlineState copyWith({
    ConnectionState? conn,
    Object? userId = _keep,
    Object? room = _keep,
    Object? game = _keep,
    Object? error = _keep,
    List<OnlineEvent>? events,
    int? fxSerial,
    Object? lastResult = _keep,
    Object? optimistic = _keep,
    Object? roomEnd = _keep,
    Object? rejoinCode = _keep,
    Object? opponentReconnectDeadlineMs = _keep,
    int? pingMs,
    int? offsetMs,
  }) =>
      OnlineState(
        conn: conn ?? this.conn,
        userId: identical(userId, _keep) ? this.userId : userId as String?,
        room: identical(room, _keep) ? this.room : room as RoomView?,
        game: identical(game, _keep) ? this.game : game as GameView?,
        error: identical(error, _keep) ? this.error : error as OnlineError?,
        events: events ?? this.events,
        fxSerial: fxSerial ?? this.fxSerial,
        lastResult: identical(lastResult, _keep) ? this.lastResult : lastResult as MoveResult?,
        optimistic: identical(optimistic, _keep) ? this.optimistic : optimistic as Move?,
        roomEnd: identical(roomEnd, _keep) ? this.roomEnd : roomEnd as RoomEnd?,
        rejoinCode: identical(rejoinCode, _keep) ? this.rejoinCode : rejoinCode as String?,
        opponentReconnectDeadlineMs: identical(opponentReconnectDeadlineMs, _keep)
            ? this.opponentReconnectDeadlineMs
            : opponentReconnectDeadlineMs as int?,
        pingMs: pingMs ?? this.pingMs,
        offsetMs: offsetMs ?? this.offsetMs,
      );
}
