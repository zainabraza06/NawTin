import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai.dart';
import '../../core/engine/engine.dart';
import '../../core/ai/hint_analyzer.dart';
import '../../services/ads/ads_provider.dart';
import '../../services/ads/ads_service.dart';
import '../../services/ai_provider.dart';
import '../../services/turn_clock.dart';
import '../setup/game_setup.dart';

/// Where the game screen is in its turn cycle.
enum GameStatus { awaitingInput, capturePick, animating, aiThinking, autoPlaying, gameOver }

const Object _keep = Object();

/// A position before a played move plus the running stats at that moment, so
/// rewind can restore captured tokens, protection and the stats exactly.
@immutable
class HistoryEntry {
  const HistoryEntry(this.game, this.eaten, this.linesFormed, this.swings);
  final GameState game;
  final List<int> eaten;
  final List<int> linesFormed;
  final List<int> swings;
}

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
    this.timeouts = const [0, 0],
    this.timeoutSeat = 0,
    this.timeoutSerial = 0,
    this.timeoutDisqualified = false,
    this.paused = false,
    this.pausesUsed = 0,
    this.hintText,
    this.hintMove,
    this.hintBusy = false,
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

  /// Positions before every played move (rewind steps back through these).
  final List<HistoryEntry> history;

  /// Timeouts per seat. The first auto-plays a move, the second disqualifies.
  final List<int> timeouts;

  /// Who timed out last, and a counter so the UI can announce it once.
  final int timeoutSeat;
  final int timeoutSerial;
  final bool timeoutDisqualified;

  /// Manual pause (max [GameController.maxPauses] per game).
  final bool paused;
  final int pausesUsed;

  /// Hint on screen: the warning text, and (Hint 2) the best move to show.
  final String? hintText;
  final Move? hintMove;

  /// A hint is being worked out (ads playing or the Hard search running).
  final bool hintBusy;

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
    List<HistoryEntry>? history,
    List<int>? timeouts,
    int? timeoutSeat,
    int? timeoutSerial,
    bool? timeoutDisqualified,
    bool? paused,
    int? pausesUsed,
    Object? hintText = _keep,
    Object? hintMove = _keep,
    bool? hintBusy,
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
        timeouts: timeouts ?? this.timeouts,
        timeoutSeat: timeoutSeat ?? this.timeoutSeat,
        timeoutSerial: timeoutSerial ?? this.timeoutSerial,
        timeoutDisqualified: timeoutDisqualified ?? this.timeoutDisqualified,
        paused: paused ?? this.paused,
        pausesUsed: pausesUsed ?? this.pausesUsed,
        hintText: identical(hintText, _keep) ? this.hintText : hintText as String?,
        hintMove: identical(hintMove, _keep) ? this.hintMove : hintMove as Move?,
        hintBusy: hintBusy ?? this.hintBusy,
      );
}

/// Two-player (pass-and-play) controller. Owns the state machine and the
/// history stack; all rules come from the pure-Dart engine.
class GameController extends Notifier<GameUiState> {
  /// Bumped on every new game so a search that finishes late is discarded.
  int _generation = 0;

  /// Shortest time the AI "thinks", so its replies do not feel instant.
  static const Duration _minThink = Duration(milliseconds: 550);

  /// Pauses allowed per game.
  static const int maxPauses = 2;

  bool _backgrounded = false;
  bool _adHold = false;

  @override
  GameUiState build() {
    final clock = ref.read(clockProvider.notifier);
    clock.onExpired = _onTimeout;
    ref.onDispose(() => clock.onExpired = null);
    // any state change may start or stop the countdown
    listenSelf((prev, _) {
      if (prev != null) _syncClock(); // never touch other providers mid-build
    });
    return GameUiState.initial(ref.read(setupProvider).names);
  }

  /// Starts a fresh game with the names chosen on the setup screen.
  void newGame({List<String>? names}) {
    _generation++;
    _backgrounded = false;
    _adHold = false;
    state = GameUiState.initial(names ?? ref.read(setupProvider).names);
    if (ref.read(setupProvider).mode == GameMode.vsAi) {
      // line up the first rewarded ad so a hint never waits on a cold start
      ref.read(adsServiceProvider).initialize().catchError((_) {});
    }
    _newTurnClock();
    _maybePlayAi();
  }

  /// Handles a tap on board point [p] according to the current status.
  void tapPoint(int p) {
    final s = state;
    if (s.paused ||
        s.status == GameStatus.animating ||
        s.status == GameStatus.aiThinking ||
        s.status == GameStatus.autoPlaying ||
        s.status == GameStatus.gameOver) {
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
      // the AI never presses PHUTAS; it is a button for the human seat
      phutasReady: result.canPhutas && mover != ref.read(setupProvider).aiSeat,
      eaten: move.hasCapture ? bump(s.eaten, mover, 1) : s.eaten,
      linesFormed: bump(s.linesFormed, mover, popCount(result.completedLines)),
      swings: swings,
      history: [...s.history, HistoryEntry(s.game, s.eaten, s.linesFormed, s.swings)],
      hintText: null,
      hintMove: null,
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
    _newTurnClock();
    _maybePlayAi();
  }

  // --------------------------------------------------------------- clock

  /// Full time for the next action (each placement / slide gets its own).
  void _newTurnClock() {
    ref.read(clockProvider.notifier).reset(ref.read(setupProvider).turnSeconds * 1000);
    _syncClock(); // an expired clock could not restart before it was refilled
  }

  /// The countdown runs only while a human can act: never during animations,
  /// AI thinking, auto-play, ads, a manual pause, or (vs AI only) while the
  /// app is in the background.
  void _syncClock() {
    final s = state;
    final aiSeat = ref.read(setupProvider).aiSeat;
    final humansTurn = aiSeat != s.game.turn;
    final acting = s.status == GameStatus.awaitingInput || s.status == GameStatus.capturePick;
    final backgroundHold = _backgrounded && aiSeat != null;
    ref
        .read(clockProvider.notifier)
        .setRunning(!s.game.isOver && humansTurn && acting && !s.paused && !backgroundHold && !_adHold);
  }

  /// Phone left the foreground / came back. Only pauses the clock vs the AI.
  void setBackgrounded(bool value) {
    _backgrounded = value;
    _syncClock();
  }

  /// Rewarded ads hold the clock while they play (Stage 6).
  void setAdHold(bool value) {
    _adHold = value;
    _syncClock();
  }

  /// Restores the full countdown for the current turn (rewind, Stage 6).
  void refillClock() => ref.read(clockProvider.notifier).refill();

  /// Manual pause. Returns false when the game has no pauses left or the
  /// moment is wrong (mid-animation, AI thinking, game over).
  bool pause() {
    final s = state;
    final ok = !s.paused &&
        s.pausesUsed < maxPauses &&
        (s.status == GameStatus.awaitingInput || s.status == GameStatus.capturePick);
    if (!ok) return false;
    state = s.copyWith(paused: true, pausesUsed: s.pausesUsed + 1);
    return true;
  }

  void resume() {
    if (state.paused) state = state.copyWith(paused: false);
  }

  /// Time ran out. First timeout: a basic (Easy-quality) legal move is played
  /// for the seat, including which token to eat. Second: disqualified.
  Future<void> _onTimeout() async {
    final s = state;
    if (s.game.isOver ||
        (s.status != GameStatus.awaitingInput && s.status != GameStatus.capturePick)) {
      return;
    }
    final seat = s.game.turn;
    final counts = [...s.timeouts];
    counts[seat]++;

    if (counts[seat] >= 2) {
      _generation++;
      state = s.copyWith(
        game: s.game.disqualify(seat),
        status: GameStatus.gameOver,
        selected: null,
        targets: 0,
        pendingStep: null,
        captureMask: 0,
        timeouts: counts,
        timeoutSeat: seat,
        timeoutSerial: s.timeoutSerial + 1,
        timeoutDisqualified: true,
      );
      return;
    }

    final gen = _generation;
    final pending = s.pendingStep;
    state = s.copyWith(
      status: GameStatus.autoPlaying,
      selected: null,
      targets: 0,
      captureMask: 0,
      timeouts: counts,
      timeoutSeat: seat,
      timeoutSerial: s.timeoutSerial + 1,
    );

    Move move;
    try {
      // deliberately Easy: a timeout must never hand out a Hard-quality move
      move = await ref
          .read(aiServiceProvider)
          .chooseMove(s.game, AiConfig.easy.withTime(250), onlyStep: pending);
    } catch (_) {
      final legal = Rules.legalMoves(s.game);
      move = legal.firstWhere((m) => pending == null || m.step == pending, orElse: () => legal.first);
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!ref.mounted || gen != _generation || state.status != GameStatus.autoPlaying) return;
    _commit(move);
  }

  // ---------------------------------------------------------- hints & rewind

  int? get _humanSeat {
    final ai = ref.read(setupProvider).aiSeat;
    return ai == null ? null : 1 - ai;
  }

  /// Hint and Rewind exist only against the AI, on the human's own turn.
  bool get canAssist {
    final s = state;
    final human = _humanSeat;
    return human != null &&
        !s.game.isOver &&
        !s.paused &&
        !s.hintBusy &&
        s.game.turn == human &&
        (s.status == GameStatus.awaitingInput || s.status == GameStatus.capturePick);
  }

  /// Index in history to rewind to, or null when there is nothing to undo.
  /// Steps back two turns: the AI's last turn and the human's turn before it.
  int? _rewindTarget(GameUiState s) {
    final ai = ref.read(setupProvider).aiSeat;
    if (ai == null) return null;
    final human = 1 - ai;
    var i = s.history.length;
    while (i > 0 && s.history[i - 1].game.turn == ai) {
      i--;
    }
    final afterAi = i;
    while (i > 0 && s.history[i - 1].game.turn == human) {
      i--;
    }
    return i == afterAi ? null : i;
  }

  bool get canRewind =>
      canAssist && state.status == GameStatus.awaitingInput && _rewindTarget(state) != null;

  /// Plays [count] rewarded ads with the clock held; the caller grants the
  /// assist only if the result says every ad was watched.
  Future<AdChainResult> watchAds(
    int count, {
    void Function(int index)? onStart,
    void Function(int done)? onProgress,
  }) async {
    _adHold = true;
    _syncClock();
    try {
      return await ref
          .read(adsServiceProvider)
          .showChain(count, onStart: onStart, onProgress: onProgress);
    } finally {
      _adHold = false;
      _syncClock();
    }
  }

  void clearHint() => state = state.copyWith(hintText: null, hintMove: null);

  /// Hint 1 (after 1 ad): a warning only.
  void applyWarningHint() {
    final human = _humanSeat;
    if (human == null || !canAssist) return;
    state = state.copyWith(
      hintText: HintAnalyzer.warning(state.game, human).message,
      hintMove: null,
    );
  }

  /// Hint 2 (after 2 ads): the warning plus the best move, from the Hard
  /// search, highlighted on the board.
  Future<void> applyBestMoveHint() async {
    final human = _humanSeat;
    if (human == null || !canAssist) return;
    final s = state;
    final gen = _generation;
    state = s.copyWith(hintBusy: true);
    _adHold = true;
    _syncClock();
    Move? best;
    try {
      best = await ref
          .read(aiServiceProvider)
          .chooseMove(s.game, AiConfig.hard.withTime(1500), onlyStep: s.pendingStep);
    } catch (_) {
      best = null;
    } finally {
      _adHold = false;
    }
    if (!ref.mounted || gen != _generation) return;
    final warning = HintAnalyzer.warning(s.game, human).message;
    final how = best == null
        ? ''
        : best.isPlacement
            ? ' Best move: place on the glowing point.'
            : ' Best move: slide the marked token to the glowing point.';
    final eat = best != null && best.hasCapture ? ' Then eat the marked token.' : '';
    state = state.copyWith(hintBusy: false, hintText: '$warning$how$eat', hintMove: best);
    _syncClock();
  }

  /// Rewind (after 3 ads): back two turns, with captured tokens, protection,
  /// stats and the full countdown restored.
  bool rewind() {
    final s = state;
    if (!canRewind) return false;
    final i = _rewindTarget(s)!;
    final e = s.history[i];
    _generation++; // cancel anything in flight
    final placing = e.game.handOf(e.game.turn) > 0;
    state = s.copyWith(
      game: e.game,
      status: GameStatus.awaitingInput,
      selected: null,
      targets: placing ? e.game.emptyMask : 0,
      pendingStep: null,
      captureMask: 0,
      lastResult: null,
      phutasReady: false,
      phutasLines: 0,
      eaten: e.eaten,
      linesFormed: e.linesFormed,
      swings: e.swings,
      history: s.history.sublist(0, i),
      hintText: null,
      hintMove: null,
    );
    _newTurnClock(); // the countdown starts again from full
    return true;
  }

  // ------------------------------------------------------------------ AI

  static AiConfig configFor(Difficulty d) => switch (d) {
        Difficulty.easy => AiConfig.easy,
        Difficulty.medium => AiConfig.medium,
        Difficulty.hard => AiConfig.hard,
      };

  /// If it is the AI's turn, search on a background isolate and play the move.
  Future<void> _maybePlayAi() async {
    final setup = ref.read(setupProvider);
    final aiSeat = setup.aiSeat;
    final s = state;
    if (aiSeat == null ||
        s.game.isOver ||
        s.game.turn != aiSeat ||
        s.status != GameStatus.awaitingInput) {
      return;
    }
    final gen = _generation;
    state = s.copyWith(status: GameStatus.aiThinking, targets: 0);
    _newTurnClock();

    final started = DateTime.now();
    Move move;
    try {
      move = await ref
          .read(aiServiceProvider)
          .chooseMove(s.game, configFor(setup.difficulty));
    } catch (_) {
      // never leave the game stuck: fall back to the first legal move
      move = Rules.legalMoves(s.game).first;
    }
    final spent = DateTime.now().difference(started);
    if (spent < _minThink) await Future<void>.delayed(_minThink - spent);

    if (!ref.mounted || gen != _generation || state.status != GameStatus.aiThinking) {
      return;
    }
    _commit(move);
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
