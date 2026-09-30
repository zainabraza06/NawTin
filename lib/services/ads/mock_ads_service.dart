import 'ads_service.dart';

/// Stand-in for AdMob while developing and in tests. Every "ad" is a short
/// delay; failures can be scripted so the denied paths are testable.
class MockAdsService extends AdsService {
  MockAdsService({
    this.adDuration = const Duration(milliseconds: 1500),
    this.loadDuration = const Duration(milliseconds: 200),
    this.fillRate = 1.0,
    Set<int>? dismissAt,
    this.waitForLoad = const Duration(seconds: 2),
  }) : dismissAt = dismissAt ?? {};

  /// How long each fake ad "plays".
  final Duration adDuration;
  final Duration loadDuration;

  /// 1.0 = always fills, 0.0 = never (simulates no inventory / offline).
  double fillRate;

  /// 1-based show numbers (counted across the session) that the user "skips".
  final Set<int> dismissAt;

  bool _ready = false;
  bool _loading = false;
  int shown = 0;

  /// How long the chain waits for a missing ad before denying.
  final Duration waitForLoad;

  @override
  Duration get loadTimeout => waitForLoad;

  @override
  Future<void> initialize() async => preload();

  @override
  bool get isReady => _ready;

  @override
  Future<void> preload() async {
    if (_ready || _loading) return;
    _loading = true;
    await Future<void>.delayed(loadDuration);
    _loading = false;
    _ready = fillRate > 0; // no fill: the load simply fails
  }

  @override
  Future<AdShowResult> showOne() async {
    if (!_ready) return AdShowResult.unavailable;
    _ready = false;
    shown++;
    await Future<void>.delayed(adDuration);
    return dismissAt.contains(shown) ? AdShowResult.dismissed : AdShowResult.completed;
  }
}
