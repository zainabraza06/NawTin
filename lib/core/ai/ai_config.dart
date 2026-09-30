/// How strong a search is. Difficulty is search depth only: the same engine
/// and the same evaluation shape, just looking further ahead. The two flags
/// switch off evaluation terms a level is not supposed to understand.
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

  /// Depth 2. Completes lines and blocks one-move threats, cannot see
  /// begi/treghi.
  static const easy = AiConfig(
    name: 'Easy',
    maxDepth: 2,
    timeMs: 500,
    seesSwings: false,
    avoidRepeat: false,
    quiesce: false,
  );

  /// Depth 4. Also blocks a forming begi and plans simple two-line setups.
  static const medium = AiConfig(
    name: 'Medium',
    maxDepth: 4,
    timeMs: 1500,
    seesSwings: true,
    avoidRepeat: false,
    quiesce: true,
  );

  /// Depth 6. Builds begi/treghi deliberately, even during placement.
  static const hard = AiConfig(
    name: 'Hard',
    maxDepth: 6,
    timeMs: 3000,
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
