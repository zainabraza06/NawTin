import 'dart:math' as math;

import 'eval_weights.dart';

/// How strong a search is. Difficulty is how far ahead the search may look and
/// for how long: the same engine and the same evaluation shape. The search
/// deepens one move at a time until the depth ceiling or the time limit, so a
/// fast phone looks further than a slow one and a quiet position is searched
/// deeper than a busy one. The flags switch off evaluation terms a level is
/// not supposed to understand.
final class AiConfig {
  const AiConfig({
    required this.name,
    required this.maxDepth,
    required this.timeMs,
    required this.seesSwings,
    required this.avoidRepeat,
    required this.quiesce,
    this.minDepth = 1,
    this.lateReductions = false,
    this.weights = EvalWeights.standard,
  });

  final String name;

  /// Deepest iteration of iterative deepening.
  final int maxDepth;

  /// Time cap per move; the last fully searched depth is used.
  final int timeMs;

  /// Evaluation knows begi/treghi potential (Medium and Hard only).
  final bool seesSwings;

  /// Steer away from repeating positions while ahead (Hard).
  final bool avoidRepeat;

  /// Extend capture sequences past the horizon.
  final bool quiesce;

  /// The search keeps going past [timeMs] (up to [overtimeFactor] times as long)
  /// until it has completed at least this depth. On a slow phone (a debug build,
  /// an old device) this stops the AI from playing on a 2-move horizon.
  final int minDepth;

  /// Search likely-unimportant late quiet moves one move shallower and only look
  /// at them properly if they turn out good. Reaches deeper in the same time.
  final bool lateReductions;

  /// The numbers the evaluation judges positions with.
  final EvalWeights weights;

  /// The same config judging positions with other [weights] (tuning, tests).
  AiConfig withWeights(EvalWeights w) => AiConfig(
        name: name,
        maxDepth: maxDepth,
        timeMs: timeMs,
        seesSwings: seesSwings,
        avoidRepeat: avoidRepeat,
        quiesce: quiesce,
        minDepth: minDepth,
        lateReductions: lateReductions,
        weights: w,
      );

  /// How far past [timeMs] the search may run while still below [minDepth].
  static const int overtimeFactor = 3;

  /// Up to 6 plies (3 turns each) ahead in 0.4 s. Completes lines, blocks threats and sees
  /// replies several moves deep, but cannot see begi/treghi.
  static const easy = AiConfig(
    name: 'Easy',
    maxDepth: 6,
    timeMs: 400,
    seesSwings: false,
    avoidRepeat: false,
    quiesce: false,
    minDepth: 3,
  );

  /// Up to 10 plies (5 turns each) ahead in 1 s. Also blocks a forming begi and plans
  /// two-line setups.
  static const medium = AiConfig(
    name: 'Medium',
    maxDepth: 10,
    timeMs: 1000,
    seesSwings: true,
    avoidRepeat: false,
    quiesce: true,
    minDepth: 5,
    lateReductions: true,
  );

  /// Up to 16 plies (8 turns each) ahead in 2 s (a slower phone stops earlier,
  /// but never before [minDepth]).
  /// Builds begi/treghi deliberately, even during placement.
  static const hard = AiConfig(
    name: 'Hard',
    maxDepth: 16,
    timeMs: 2000,
    seesSwings: true,
    avoidRepeat: true,
    quiesce: true,
    minDepth: 7,
    lateReductions: true,
  );

  /// The same config with a different clock (tests, self-play, hints).
  AiConfig withTime(int ms) => AiConfig(
        name: name,
        maxDepth: maxDepth,
        timeMs: ms,
        seesSwings: seesSwings,
        avoidRepeat: avoidRepeat,
        quiesce: quiesce,
        minDepth: minDepth,
        lateReductions: lateReductions,
        weights: weights,
      );

  AiConfig withDepth(int depth) => AiConfig(
        name: name,
        maxDepth: depth,
        timeMs: timeMs,
        seesSwings: seesSwings,
        avoidRepeat: avoidRepeat,
        quiesce: quiesce,
        minDepth: math.min(minDepth, depth),
        lateReductions: lateReductions,
        weights: weights,
      );

  /// The same config without the guaranteed minimum depth, for tests that need
  /// the time limit to be strict.
  AiConfig strictTime() => AiConfig(
        name: name,
        maxDepth: maxDepth,
        timeMs: timeMs,
        seesSwings: seesSwings,
        avoidRepeat: avoidRepeat,
        quiesce: quiesce,
        minDepth: 1,
        lateReductions: lateReductions,
        weights: weights,
      );
}
