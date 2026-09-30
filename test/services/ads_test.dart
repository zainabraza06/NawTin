import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/services/ads/ads_service.dart';
import 'package:nawtin/services/ads/mock_ads_service.dart';

MockAdsService fast({double fill = 1, Set<int>? dismissAt}) => MockAdsService(
      adDuration: const Duration(milliseconds: 10),
      loadDuration: const Duration(milliseconds: 5),
      waitForLoad: const Duration(milliseconds: 150),
      fillRate: fill,
      dismissAt: dismissAt,
    );

void main() {
  test('costs match the design: hint 1, best move 2, rewind 3', () {
    expect(AdCosts.hintWarning, 1);
    expect(AdCosts.hintBestMove, 2);
    expect(AdCosts.rewind, 3);
  });

  test('a chain grants the reward only after every ad finished', () async {
    final ads = fast();
    final started = <int>[];
    final done = <int>[];
    final r = await ads.showChain(3, onStart: started.add, onProgress: done.add);
    expect(r.granted, isTrue);
    expect(r.completed, 3);
    expect(started, [1, 2, 3]);
    expect(done, [1, 2, 3]);
    expect(ads.shown, 3);
  });

  test('an ad closed early denies the whole chain (no partial reward)', () async {
    final ads = fast(dismissAt: {2});
    final done = <int>[];
    final r = await ads.showChain(3, onProgress: done.add);
    expect(r.granted, isFalse);
    expect(r.completed, 1);
    expect(r.message, AdsService.closedEarlyMessage);
    expect(done, [1]);
    expect(ads.shown, 2, reason: 'the third ad is never shown');
  });

  test('no ad available: denied with a clear message, never free', () async {
    final ads = fast(fill: 0);
    final r = await ads.showChain(1);
    expect(r.granted, isFalse);
    expect(r.completed, 0);
    expect(r.message, AdsService.noAdMessage);
    expect(ads.shown, 0);
  });

  test('the supply dries up in the middle of a chain: denied', () async {
    final ads = fast();
    final r = await ads.showChain(2, onProgress: (d) {
      if (d == 1) ads.fillRate = 0; // nothing left to load
    });
    expect(r.granted, isFalse);
    expect(r.completed, 1);
    expect(r.message, AdsService.noAdMessage);
  });

  test('ads are preloaded so the next one is ready straight away', () async {
    final ads = fast();
    await ads.initialize();
    expect(ads.isReady, isTrue);
    final r = await ads.showChain(1);
    expect(r.granted, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(ads.isReady, isTrue, reason: 'the next ad was loaded in the background');
  });

  test('a denied chain can be retried and then succeeds', () async {
    final ads = fast(dismissAt: {1});
    expect((await ads.showChain(1)).granted, isFalse);
    expect((await ads.showChain(1)).granted, isTrue);
  });
}
