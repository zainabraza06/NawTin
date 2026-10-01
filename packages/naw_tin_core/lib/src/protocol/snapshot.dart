import '../engine/engine.dart';
import 'protocol.dart';

/// Wire form of a position: the engine's `GameState` without the repetition
/// history (the server keeps that; clients never need it).
Map<String, Object?> encodeSnapshot(GameState s, {String? endReasonOverride}) {
  final r = s.result;
  return {
    'mask0': s.mask0,
    'mask1': s.mask1,
    'hand0': s.hand0,
    'hand1': s.hand1,
    'turn': s.turn,
    'placesLeft': s.placesLeft,
    'phase': s.phase == GamePhase.placement ? 'placement' : 'movement',
    'result': r == null
        ? null
        : {
            'winner': r.winner,
            'reason': endReasonOverride ?? r.reason.name,
          },
  };
}

/// Rebuilds a [GameState] from [encodeSnapshot] output. Throws
/// [FormatException] on malformed input (never trusts the sender).
GameState decodeSnapshot(Object? json) {
  if (json is! Map) throw const FormatException('snapshot must be an object');
  int n(String k, int lo, int hi) {
    final v = json[k];
    if (v is! int || v < lo || v > hi) {
      throw FormatException('snapshot.$k out of range');
    }
    return v;
  }

  final mask0 = n('mask0', 0, Board.fullMask);
  final mask1 = n('mask1', 0, Board.fullMask);
  if (mask0 & mask1 != 0) throw const FormatException('overlapping tokens');
  final s = GameState.fromMasks(
    mask0: mask0,
    mask1: mask1,
    hand0: n('hand0', 0, Board.tokensPerPlayer),
    hand1: n('hand1', 0, Board.tokensPerPlayer),
    turn: n('turn', 0, 1),
    placesLeft: n('placesLeft', 1, 2),
  );
  final r = json['result'];
  if (r == null) return s;
  if (r is! Map) throw const FormatException('snapshot.result');
  final winner = r['winner'];
  final reason = _engineReason(r['reason']);
  if (winner == null) return s.withResult(GameResult.draw(reason));
  if (winner is! int || (winner != 0 && winner != 1)) {
    throw const FormatException('snapshot.result.winner');
  }
  return s.withResult(GameResult.win(winner, reason));
}

/// The raw end reason string of a snapshot (may be `abandoned` / `forfeit`).
String? snapshotEndReason(Object? json) {
  if (json is Map && json['result'] is Map) {
    final reason = (json['result'] as Map)['reason'];
    return reason is String ? reason : null;
  }
  return null;
}

/// Online-only reasons map onto the engine's closest one.
GameEndReason _engineReason(Object? name) {
  for (final r in GameEndReason.values) {
    if (r.name == name) return r;
  }
  if (name == EndReason.abandoned || name == EndReason.forfeit) {
    return GameEndReason.disqualified;
  }
  throw FormatException('unknown end reason $name');
}

Map<String, Object?> encodeMove(Move m) =>
    {'from': m.from, 'to': m.to, 'capture': m.capture};

/// Decodes a move; `from < 0` is a placement, `capture < 0` means none.
Move decodeMove(Object? json) {
  if (json is! Map) throw const FormatException('move must be an object');
  int p(String k, {bool allowNone = false}) {
    final v = json[k] ?? (allowNone ? -1 : null);
    if (v is! int || v < (allowNone ? -1 : 0) || v >= Board.pointCount) {
      throw FormatException('move.$k out of range');
    }
    return v;
  }

  final from = p('from', allowNone: true);
  final to = p('to');
  final capture = p('capture', allowNone: true);
  return from < 0
      ? Move.place(to, capture: capture)
      : Move.slide(from, to, capture: capture);
}
