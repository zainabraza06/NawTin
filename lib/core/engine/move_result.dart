import 'analysis.dart';
import 'game_state.dart';
import 'move.dart';
import 'patterns.dart';
import 'rules.dart';

/// The announcements a move can trigger.
enum Call { phutas, machyas, begi, treghi }

/// A begi/treghi that has just formed for [seat].
final class SwingEvent {
  const SwingEvent(this.seat, this.pattern);
  final int seat;
  final SwingPattern pattern;

  Call get call =>
      pattern.kind == PatternKind.treghi ? Call.treghi : Call.begi;
}

/// Everything the UI, stats and sound need to know about one played move.
final class MoveResult {
  const MoveResult({
    required this.before,
    required this.move,
    required this.after,
    required this.mover,
    required this.completedLines,
    required this.swingEvents,
    required this.phutasLines,
  });

  final GameState before;
  final Move move;
  final GameState after;
  final int mover;

  /// Lines (16-bit line mask) completed by this move.
  final int completedLines;

  /// Begi/treghi setups that armed as a result of this move (either seat).
  /// Empty once a setup already existed, so the banner shows only once.
  final List<SwingEvent> swingEvents;

  /// NEW lines (16-bit line mask) the mover could complete next turn, minus
  /// begi/treghi swing lines. Non-zero means the PHUTAS button is available.
  final int phutasLines;

  bool get isMachyas => move.hasCapture;
  bool get canPhutas => phutasLines != 0;

  /// The strongest begi/treghi announcement (treghi outranks begi), if any.
  SwingEvent? get announcedSwing {
    SwingEvent? best;
    for (final e in swingEvents) {
      if (best == null ||
          (e.pattern.kind == PatternKind.treghi &&
              best.pattern.kind != PatternKind.treghi)) {
        best = e;
      }
    }
    return best;
  }

  /// Auto announcements in the order the UI should play them
  /// (Phutas is a player-pressed button, so it is not listed).
  List<Call> get autoCalls => [
        if (isMachyas) Call.machyas,
        if (announcedSwing != null) announcedSwing!.call,
      ];

  /// Plays [move] in [before] and analyses what happened.
  static MoveResult resolve(GameState before, Move move) {
    final mover = before.turn;
    final after = Rules.apply(before, move);
    final completed = Rules.linesFormedByStep(before, move.step);

    final events = <SwingEvent>[];
    var moverArmedAfter = const <SwingPattern>[];
    for (var seat = 0; seat < 2; seat++) {
      final armedBefore =
          SwingPattern.armed(before.maskOf(seat), before.maskOf(1 - seat));
      final armedAfter =
          SwingPattern.armed(after.maskOf(seat), after.maskOf(1 - seat));
      if (seat == mover) moverArmedAfter = armedAfter;
      for (final p in armedAfter) {
        if (!armedBefore.contains(p)) events.add(SwingEvent(seat, p));
      }
    }

    final newThreats = Analysis.threatLines(after, mover) &
        ~Analysis.threatLines(before, mover) &
        ~Analysis.swingLines(moverArmedAfter);

    return MoveResult(
      before: before,
      move: move,
      after: after,
      mover: mover,
      completedLines: completed,
      swingEvents: events,
      phutasLines: after.isOver ? 0 : newThreats,
    );
  }
}
