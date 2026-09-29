import 'bits.dart';
import 'board.dart';

/// Players are seats 0 and 1. Seat 0 moves first (and places two tokens on
/// its opening turn). Which human/AI sits in which seat is a UI concern.
enum GamePhase { placement, movement }

enum GameEndReason {
  /// The loser has 2 tokens left (board + unplaced).
  tokensReduced,

  /// The loser must move but has no legal move.
  noLegalMoves,

  /// The same position occurred three times (draw).
  repetition,

  /// The loser timed out twice (set by the controller, not the rules).
  disqualified,
}

final class GameResult {
  const GameResult.win(int this.winner, this.reason);
  const GameResult.draw(this.reason) : winner = null;

  /// Winning seat, or null for a draw.
  final int? winner;
  final GameEndReason reason;

  bool get isDraw => winner == null;

  @override
  String toString() => isDraw ? 'draw($reason)' : 'win($winner, $reason)';
}

/// Positions seen since the last irreversible action (a placement or a
/// capture), kept as a persistent linked list so states stay immutable and
/// cheap to copy during search. Repetition can only happen inside such a run.
final class PositionHistory {
  const PositionHistory(this.key, [this.previous]);

  final int key;
  final PositionHistory? previous;

  PositionHistory add(int newKey) => PositionHistory(newKey, this);

  /// How many times [k] occurs in the run (including the newest entry).
  int count(int k) {
    var n = 0;
    for (PositionHistory? h = this; h != null; h = h.previous) {
      if (h.key == k) n++;
    }
    return n;
  }
}

/// Immutable game position. All board data is two 24-bit masks.
final class GameState {
  const GameState({
    required this.mask0,
    required this.mask1,
    required this.hand0,
    required this.hand1,
    required this.turn,
    required this.placesLeft,
    required this.history,
    this.result,
  });

  /// The start of a game: empty board, 9 tokens each, seat 0 to place two.
  factory GameState.initial() => GameState.fromMasks(
        mask0: 0,
        mask1: 0,
        hand0: Board.tokensPerPlayer,
        hand1: Board.tokensPerPlayer,
        turn: 0,
        placesLeft: 2,
      );

  /// Builds any position (tests, hints, search roots).
  factory GameState.fromMasks({
    required int mask0,
    required int mask1,
    int hand0 = 0,
    int hand1 = 0,
    int turn = 0,
    int placesLeft = 1,
  }) =>
      GameState(
        mask0: mask0,
        mask1: mask1,
        hand0: hand0,
        hand1: hand1,
        turn: turn,
        placesLeft: placesLeft,
        history: PositionHistory(keyOf(mask0, mask1, turn)),
      );

  /// Tokens of seat 0 / seat 1 on the board (bit per point).
  final int mask0;
  final int mask1;

  /// Tokens still to be placed.
  final int hand0;
  final int hand1;

  /// Seat to act.
  final int turn;

  /// Placements the seat to act may still make this turn (2 on the opening
  /// turn, otherwise 1). Ignored during movement.
  final int placesLeft;

  final PositionHistory history;

  /// Set once the game has ended.
  final GameResult? result;

  /// Unique id of a board position + side to move (49 bits, so it also stays
  /// exact on platforms where ints are doubles).
  static int keyOf(int mask0, int mask1, int turn) =>
      (turn * 16777216 + mask1) * 16777216 + mask0;

  int get positionKey => keyOf(mask0, mask1, turn);

  int maskOf(int seat) => seat == 0 ? mask0 : mask1;
  int handOf(int seat) => seat == 0 ? hand0 : hand1;

  int get occupied => mask0 | mask1;
  int get emptyMask => Board.fullMask & ~occupied;

  /// Tokens a seat still owns: on the board plus unplaced.
  int totalTokens(int seat) => popCount(maskOf(seat)) + handOf(seat);

  /// Captured (eaten) tokens of a seat.
  int lostTokens(int seat) => Board.tokensPerPlayer - totalTokens(seat);

  GamePhase get phase =>
      hand0 + hand1 > 0 ? GamePhase.placement : GamePhase.movement;

  bool get isOver => result != null;

  GameState withResult(GameResult r) => GameState(
        mask0: mask0,
        mask1: mask1,
        hand0: hand0,
        hand1: hand1,
        turn: turn,
        placesLeft: placesLeft,
        history: history,
        result: r,
      );

  /// Ends the game because [seat] was disqualified.
  GameState disqualify(int seat) =>
      withResult(GameResult.win(1 - seat, GameEndReason.disqualified));

  @override
  bool operator ==(Object other) =>
      other is GameState &&
      other.mask0 == mask0 &&
      other.mask1 == mask1 &&
      other.hand0 == hand0 &&
      other.hand1 == hand1 &&
      other.turn == turn &&
      other.placesLeft == placesLeft;

  @override
  int get hashCode =>
      Object.hash(mask0, mask1, hand0, hand1, turn, placesLeft);

  @override
  String toString() => 'GameState(p0=${bitsOf(mask0).toList()}+$hand0, '
      'p1=${bitsOf(mask1).toList()}+$hand1, turn=$turn, result=$result)';
}
