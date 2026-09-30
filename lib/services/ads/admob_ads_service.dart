import 'dart:async';
import 'dart:io' show Platform;

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_service.dart';

/// Real rewarded ads through Google AdMob, using Google's public TEST ad unit
/// ids. Before release swap [_androidUnit] / [_iosUnit] for your own units and
/// replace the test application ids in AndroidManifest.xml / Info.plist.
class AdMobAdsService extends AdsService {
  // https://developers.google.com/admob/android/test-ads
  static const String _androidUnit = 'ca-app-pub-3940256099942544/5224354917';
  static const String _iosUnit = 'ca-app-pub-3940256099942544/1712485313';

  RewardedAd? _ad;
  bool _loading = false;
  bool _started = false;

  String get _unit => Platform.isIOS ? _iosUnit : _androidUnit;

  @override
  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    await MobileAds.instance.initialize();
    await preload();
  }

  @override
  bool get isReady => _ad != null;

  @override
  Future<void> preload() async {
    if (_ad != null || _loading) return;
    _loading = true;
    final done = Completer<void>();
    RewardedAd.load(
      adUnitId: _unit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          done.complete();
        },
        onAdFailedToLoad: (_) {
          _loading = false;
          done.complete();
        },
      ),
    );
    await done.future;
  }

  @override
  Future<AdShowResult> showOne() async {
    final ad = _ad;
    if (ad == null) return AdShowResult.unavailable;
    _ad = null;
    final closed = Completer<AdShowResult>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!closed.isCompleted) {
          closed.complete(earned ? AdShowResult.completed : AdShowResult.dismissed);
        }
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        if (!closed.isCompleted) closed.complete(AdShowResult.unavailable);
      },
    );
    ad.show(onUserEarnedReward: (_, __) => earned = true);
    return closed.future;
  }
}
