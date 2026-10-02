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

  /// Up to 6 moves ahead in 0.4 s. Completes lines, blocks threats and sees
  /// replies several moves deep, but cannot see begi/treghi.
  static const easy = AiConfig(
    name: 'Easy',
    maxDepth: 6,
    timeMs: 400,
    seesSwings: false,
    avoidRepeat: false,
    quiesce: false,
  );

  /// Up to 10 moves ahead in 1 s. Also blocks a forming begi and plans
  /// two-line setups.
  static const medium = AiConfig(
    name: 'Medium',
    maxDepth: 10,
    timeMs: 1000,
    seesSwings: true,
    avoidRepeat: false,
    quiesce: true,
  );

  /// Up to 16 moves ahead in 2 s (a slower phone stops a few moves earlier).
  /// Builds begi/treghi deliberately, even during placement.
  static const hard = AiConfig(
    name: 'Hard',
    maxDepth: 16,
    timeMs: 2000,
    seesSwings: true,
    avoidRepeat: true,
    quiesce: true,
  );

  /// The same config with a different clock (tests, self-play, hints).
  AiConfig withTime(int ms) => AiConfig(
        name: name,
        maxDepth: maxDepth,
        timeMs: ms,
        seesSwings: seesSwings,
        avoidRepeat: avoidRepeat,
        quiesce: quiesce,
      );

  AiConfig withDepth(int depth) => AiConfig(
        name: name,
        maxDepth: depth,
        timeMs: timeMs,
        seesSwings: seesSwings,
        avoidRepeat: avoidRepeat,
        quiesce: quiesce,
      );
}
