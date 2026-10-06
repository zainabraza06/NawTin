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
    this.varietyMargin = 0,
    this.endgameDepthBonus = 0,
    this.capturePreference = 0,
    this.safetyPreference = 0,
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

  /// Variety: among the root moves whose value is within this many points of the
  /// best (100 points = one token), one is picked at random, so the AI does not
  /// play the same game every time. 0 = always the single best move.
  final int varietyMargin;

  /// Extra search depth allowed when few tokens remain (small branching makes
  /// deep calculation cheap, and endgames are decided by long forced lines).
  final int endgameDepthBonus;

  /// "A bird in the hand": if a move that eats a token is worth within this many
  /// points of the best move, play it instead. A search that stops on an odd or
  /// an even depth judges quiet set-ups differently, and without this it will
  /// sometimes decline a capture it could simply make.
  final int capturePreference;

  /// If the best move leaves the opponent a line to complete next turn, a move
  /// worth within this many points that does not is played instead. Search
  /// values that close are decided by noise (they flip with the search depth),
  /// and ignoring a one-move threat looks naive.
  final int safetyPreference;

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
        varietyMargin: varietyMargin,
        endgameDepthBonus: endgameDepthBonus,
        capturePreference: capturePreference,
        safetyPreference: safetyPreference,
      );

  /// The same config with another variety margin (0 = deterministic, for tests).
  AiConfig withVariety(int margin) => AiConfig(
        name: name,
        maxDepth: maxDepth,
        timeMs: timeMs,
        seesSwings: seesSwings,
        avoidRepeat: avoidRepeat,
        quiesce: quiesce,
        minDepth: minDepth,
        lateReductions: lateReductions,
        weights: weights,
        varietyMargin: margin,
        endgameDepthBonus: endgameDepthBonus,
        capturePreference: capturePreference,
        safetyPreference: safetyPreference,
      );

  /// The same config with another capture preference (0 = off).
  AiConfig withCapturePreference(int margin) => AiConfig(
        name: name,
        maxDepth: maxDepth,
        timeMs: timeMs,
        seesSwings: seesSwings,
        avoidRepeat: avoidRepeat,
        quiesce: quiesce,
        minDepth: minDepth,
        lateReductions: lateReductions,
        weights: weights,
        varietyMargin: varietyMargin,
        endgameDepthBonus: endgameDepthBonus,
        capturePreference: margin,
        safetyPreference: safetyPreference,
      );

  /// The same config with another safety preference (0 = off).
  AiConfig withSafetyPreference(int margin) => AiConfig(
        name: name,
        maxDepth: maxDepth,
        timeMs: timeMs,
        seesSwings: seesSwings,
        avoidRepeat: avoidRepeat,
        quiesce: quiesce,
        minDepth: minDepth,
        lateReductions: lateReductions,
        weights: weights,
        varietyMargin: varietyMargin,
        endgameDepthBonus: endgameDepthBonus,
        capturePreference: capturePreference,
        safetyPreference: margin,
      );

  /// How far past [timeMs] the search may run while still below [minDepth].
  static const int overtimeFactor = 3;

  /// Up to 8 plies (4 turns each) ahead in 0.4 s. Completes lines, blocks
  /// threats, sees capture sequences and begi/treghi set-ups, and varies its
  /// play a little between games.
  static const easy = AiConfig(
    name: 'Easy',
    maxDepth: 8,
    timeMs: 400,
    seesSwings: true,
    avoidRepeat: false,
    quiesce: true,
    minDepth: 4,
    varietyMargin: 30,
    capturePreference: 40,
    safetyPreference: 40,
  );

  /// Up to 12 plies (6 turns each) ahead in 1 s. Plans two-line and swinging
  /// set-ups, calculates endgames further, varies its play.
  static const medium = AiConfig(
    name: 'Medium',
    maxDepth: 12,
    timeMs: 1000,
    seesSwings: true,
    avoidRepeat: false,
    quiesce: true,
    minDepth: 6,
    lateReductions: true,
    varietyMargin: 15,
    endgameDepthBonus: 4,
    capturePreference: 40,
    safetyPreference: 40,
  );

  /// Up to 18 plies (9 turns each) ahead in 2 s (a slower phone stops earlier,
  /// but never before [minDepth]). Builds begi/treghi deliberately, calculates
  /// endgames far ahead, avoids repeating itself, varies its play.
  static const hard = AiConfig(
    name: 'Hard',
    maxDepth: 18,
    timeMs: 2000,
    seesSwings: true,
    avoidRepeat: true,
    quiesce: true,
    minDepth: 8,
    lateReductions: true,
    varietyMargin: 8,
    endgameDepthBonus: 8,
    capturePreference: 40,
    safetyPreference: 40,
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
        varietyMargin: varietyMargin,
        endgameDepthBonus: endgameDepthBonus,
        capturePreference: capturePreference,
        safetyPreference: safetyPreference,
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
        varietyMargin: varietyMargin,
        endgameDepthBonus: endgameDepthBonus,
        capturePreference: capturePreference,
        safetyPreference: safetyPreference,
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
        varietyMargin: varietyMargin,
        endgameDepthBonus: endgameDepthBonus,
        capturePreference: capturePreference,
        safetyPreference: safetyPreference,
      );
}
