import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/engine.dart';

/// Where the game screen is in its turn cycle. (`idle` and `aiThinking` join
/// in later stages together with the AI.)
enum GameStatus { awaitingInput, capturePick, animating, gameOver }

const Object _keep = Object();

/// Everything the game screen renders. The rules engine state lives in
/// [game]; the rest is UI-facing bookkeeping owned by the controller.
@immutable
class GameUiState {
  const GameUiState({
    required this.game,
    required this.status,
    required this.names,
    this.selected,
    this.targets = 0,
    this.pendingStep,
    this.captureMask = 0,
    this.lastResult,
    this.fxSerial = 0,
    this.phutasSeat = 0,
    this.phutasLines = 0,
    this.phutasReady = false,
    this.phutasSerial = 0,
    this.eaten = const [0, 0],
    this.linesFormed = const [0, 0],
    this.swings = const [0, 0],
    this.history = const [],
  });

  factory GameUiState.initial(List<String> names) {
    final game = GameState.initial();
    return GameUiState(
      game: game,
      status: GameStatus.awaitingInput,
      names: names,
      targets: game.emptyMask,
    );
  }

  final GameState game;
  final GameStatus status;
  final List<String> names;

  /// Token picked up in the movement phase.
  final int? selected;

  /// Points the player may tap next (placement targets or slide targets).
  final int targets;

  /// The step waiting for a capture choice (status == capturePick).
  final Move? pendingStep;

  /// Opponent tokens that can be eaten right now.
  final int captureMask;

  /// The most recent move, and a counter that changes for every move so the
  /// board can start its animation exactly once.
  final MoveResult? lastResult;
  final int fxSerial;

  /// PHUTAS button: which seat set up a threat, which lines, and whether the
  /// button can still be pressed. [phutasSerial] bumps when it is pressed.
  final int phutasSeat;
  final int phutasLines;
  final bool phutasReady;
  final int phutasSerial;

  // Per-seat stats for the game-over screen.
  final List<int> eaten;
  final List<int> linesFormed;
  final List<int> swings;

  /// Positions before every played move (used by rewind in a later stage).
  final List<GameState> history;

  bool get isOver => game.isOver;

  GameUiState copyWith({
    GameState? game,
    GameStatus? status,
    Object? selected = _keep,
    int? targets,
    Object? pendingStep = _keep,
    int? captureMask,
    Object? lastResult = _keep,
    int? fxSerial,
    int? phutasSeat,
    int? phutasLines,
    bool? phutasReady,
    int? phutasSerial,
    List<int>? eaten,
    List<int>? linesFormed,
    List<int>? swings,
    List<GameState>? history,
  }) =>
      GameUiState(
        game: game ?? this.game,
        status: status ?? this.status,
        names: names,
        selected: identical(selected, _keep) ? this.selected : selected as int?,
        targets: targets ?? this.targets,
        pendingStep:
            identical(pendingStep, _keep) ? this.pendingStep : pendingStep as Move?,
        captureMask: captureMask ?? this.captureMask,
        lastResult: identical(lastResult, _keep)
            ? this.lastResult
            : lastResult as MoveResult?,
        fxSerial: fxSerial ?? this.fxSerial,
        phutasSeat: phutasSeat ?? this.phutasSeat,
        phutasLines: phutasLines ?? this.phutasLines,
        phutasReady: phutasReady ?? this.phutasReady,
        phutasSerial: phutasSerial ?? this.phutasSerial,
        eaten: eaten ?? this.eaten,
        linesFormed: linesFormed ?? this.linesFormed,
        swings: swings ?? this.swings,
        history: history ?? this.history,
      );
}

/// Two-player (pass-and-play) controller. Owns the state machine and the
/// history stack; all rules come from the pure-Dart engine.
class GameController extends Notifier<GameUiState> {
  @override
  GameUiState build() => GameUiState.initial(const ['Player 1', 'Player 2']);

  /// Starts a fresh game.
  void newGame({List<String>? names}) {
    state = GameUiState.initial(names ?? state.names);
  }

  /// Handles a tap on board point [p] according to the current status.
  void tapPoint(int p) {
    final s = state;
    if (s.status == GameStatus.animating || s.status == GameStatus.gameOver) {
      return;
    }
    if (s.status == GameStatus.capturePick) {
      if (s.captureMask & bit(p) != 0) {
        _commit(s.pendingStep!.withCapture(p));
      }
      return;
    }

    final g = s.game;
    final me = g.turn;
    if (g.handOf(me) > 0) {
      // placement phase
      if (g.emptyMask & bit(p) != 0) _chooseStep(Move.place(p));
      return;
    }

    // movement phase
    final own = g.maskOf(me);
    if (own & bit(p) != 0) {
      if (s.selected == p) {
        state = s.copyWith(selected: null, targets: 0);
      } else {
        state = s.copyWith(
          selected: p,
          targets: Board.neighborMasks[p] & g.emptyMask,
        );
      }
      return;
    }
    if (s.selected != null && s.targets & bit(p) != 0) {
      _chooseStep(Move.slide(s.selected!, p));
    } else if (s.selected != null) {
      state = s.copyWith(selected: null, targets: 0);
    }
  }

  void _chooseStep(Move step) {
    final targets = Rules.captureTargets(state.game, step);
    if (targets == 0) {
      _commit(step);
    } else {
      state = state.copyWith(
        status: GameStatus.capturePick,
        pendingStep: step,
        captureMask: targets,
        selected: step.isPlacement ? null : step.from,
        targets: 0,
      );
    }
  }

  void _commit(Move move) {
    final s = state;
    final result = MoveResult.resolve(s.game, move);
    final mover = result.mover;

    List<int> bump(List<int> l, int seat, int by) {
      final c = [...l];
      c[seat] += by;
      return c;
    }

    var swings = s.swings;
    for (final e in result.swingEvents) {
      swings = bump(swings, e.seat, 1);
    }

    state = s.copyWith(
      game: result.after,
      status: GameStatus.animating,
      selected: null,
      targets: 0,
      pendingStep: null,
      captureMask: 0,
      lastResult: result,
      fxSerial: s.fxSerial + 1,
      phutasSeat: mover,
      phutasLines: result.phutasLines,
      phutasReady: result.canPhutas,
      eaten: move.hasCapture ? bump(s.eaten, mover, 1) : s.eaten,
      linesFormed: bump(s.linesFormed, mover, popCount(result.completedLines)),
      swings: swings,
      history: [...s.history, s.game],
    );
  }

  /// The board calls this when the animation for [serial] has finished.
  void finishAnimation(int serial) {
    final s = state;
    if (s.status != GameStatus.animating || serial != s.fxSerial) return;
    if (s.game.isOver) {
      state = s.copyWith(status: GameStatus.gameOver, targets: 0);
      return;
    }
    final placing = s.game.handOf(s.game.turn) > 0;
    state = s.copyWith(
      status: GameStatus.awaitingInput,
      targets: placing ? s.game.emptyMask : 0,
    );
  }

  /// PHUTAS button: a warning only, no effect on the game.
  void callPhutas() {
    final s = state;
    if (!s.phutasReady) return;
    state = s.copyWith(phutasReady: false, phutasSerial: s.phutasSerial + 1);
  }
}

final gameControllerProvider =
    NotifierProvider<GameController, GameUiState>(GameController.new);
