/// One action by the player to move: a placement or a one-step slide, plus
/// the opponent token eaten when the action completes a line.
///
/// Captures are part of the move, so a search treats every capture choice as
/// its own branch. A UI builds the move in two steps (choose the step, then
/// pick the capture with `Rules.captureTargets`).
final class Move {
  /// Placement of a token from hand onto [to].
  const Move.place(this.to, {this.capture = -1}) : from = -1;

  /// One-step slide of the token on [from] to the adjacent empty point [to].
  const Move.slide(this.from, this.to, {this.capture = -1});

  /// Origin point, or -1 for a placement.
  final int from;
  final int to;

  /// Opponent point eaten by this move, or -1 when no line is completed.
  final int capture;

  bool get isPlacement => from < 0;
  bool get hasCapture => capture >= 0;

  Move withCapture(int point) =>
      isPlacement ? Move.place(to, capture: point) : Move.slide(from, to, capture: point);

  /// The same move without its capture (the "step" part).
  Move get step => hasCapture ? withCapture(-1) : this;

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.from == from &&
      other.to == to &&
      other.capture == capture;

  @override
  int get hashCode => Object.hash(from, to, capture);

  @override
  String toString() {
    final base = isPlacement ? 'place($to)' : 'slide($from->$to)';
    return hasCapture ? '$base x$capture' : base;
  }
}
