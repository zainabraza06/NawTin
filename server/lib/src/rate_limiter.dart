import 'clock.dart';

/// Sliding-window rate limiter keyed by an arbitrary string (user id, IP...).
class RateLimiter {
  RateLimiter(this.clock);

  final ServerClock clock;
  final Map<String, List<DateTime>> _hits = {};

  /// Records an attempt and returns true if it is within [limit] per [window].
  /// When it returns false the attempt is NOT counted.
  bool allow(String key, {required int limit, required Duration window}) {
    final now = clock.now();
    final list = _hits.putIfAbsent(key, () => []);
    list.removeWhere((t) => now.difference(t) >= window);
    if (list.length >= limit) return false;
    list.add(now);
    return true;
  }

  /// How many attempts for [key] are inside the current [window] (not recorded).
  int count(String key, {required Duration window}) {
    final list = _hits[key];
    if (list == null) return 0;
    final now = clock.now();
    return list.where((t) => now.difference(t) < window).length;
  }

  /// Milliseconds until the next attempt for [key] would be allowed.
  int retryAfterMs(String key, {required Duration window}) {
    final list = _hits[key];
    if (list == null || list.isEmpty) return 0;
    final wait = window - clock.now().difference(list.first);
    return wait.isNegative ? 0 : wait.inMilliseconds;
  }

  /// Drops keys with no recent hits (call occasionally).
  void sweep(Duration window) {
    final now = clock.now();
    _hits.removeWhere((_, l) => l.isEmpty || now.difference(l.last) >= window);
  }
}
