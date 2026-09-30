/// How many rewarded ads each assist costs.
abstract final class AdCosts {
  static const int hintWarning = 1;
  static const int hintBestMove = 2;
  static const int rewind = 3;
}

/// Outcome of showing a single rewarded ad.
enum AdShowResult {
  /// Watched to the end: the user earned this ad's reward.
  completed,

  /// Closed before the reward point.
  dismissed,

  /// Nothing to show (no fill, no network, not loaded in time).
  unavailable,
}

/// Outcome of a whole chain of ads.
final class AdChainResult {
  const AdChainResult.granted(this.total)
      : granted = true,
        completed = total,
        message = null;
  const AdChainResult.denied(this.completed, this.total, this.message) : granted = false;

  /// True only when EVERY ad in the chain was watched to the end.
  final bool granted;
  final int completed;
  final int total;

  /// User-facing reason when [granted] is false.
  final String? message;
}

/// Rewarded-ad wrapper. Implementations provide the primitives; the multi-ad
/// chain (reward only after all ads finish, never free) is shared here so the
/// mock and the real AdMob service behave identically.
abstract class AdsService {
  /// One-time setup (SDK start-up).
  Future<void> initialize();

  /// Whether an ad is loaded and can be shown right now.
  bool get isReady;

  /// Starts loading the next ad (no-op if one is ready or loading).
  Future<void> preload();

  /// Shows one ad; resolves when it is closed.
  Future<AdShowResult> showOne();

  /// How long the chain waits for a still-loading ad before giving up.
  Duration get loadTimeout => const Duration(seconds: 8);

  static const String noAdMessage =
      'No ad is available right now. Check your connection and try again in a moment.';
  static const String closedEarlyMessage =
      'The ad was closed before the end, so no reward was given. Watch it to the finish to unlock this.';

  /// Shows [count] ads back to back. The reward is granted only if all of them
  /// are watched to the end; if any is missing or skipped the whole request is
  /// denied (no partial or free rewards). [onProgress] reports the number of
  /// ads finished so far (after each) and [onStart] the 1-based index of the
  /// ad about to play.
  Future<AdChainResult> showChain(
    int count, {
    void Function(int index)? onStart,
    void Function(int done)? onProgress,
  }) async {
    for (var i = 0; i < count; i++) {
      if (!await _waitUntilReady()) {
        preload();
        return AdChainResult.denied(i, count, noAdMessage);
      }
      onStart?.call(i + 1);
      final r = await showOne();
      preload(); // line up the next one straight away
      switch (r) {
        case AdShowResult.completed:
          onProgress?.call(i + 1);
        case AdShowResult.dismissed:
          return AdChainResult.denied(i, count, closedEarlyMessage);
        case AdShowResult.unavailable:
          return AdChainResult.denied(i, count, noAdMessage);
      }
    }
    return AdChainResult.granted(count);
  }

  Future<bool> _waitUntilReady() async {
    if (isReady) return true;
    await preload();
    final deadline = DateTime.now().add(loadTimeout);
    while (!isReady && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return isReady;
  }
}
