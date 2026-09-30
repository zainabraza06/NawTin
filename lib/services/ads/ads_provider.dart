import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ads_service.dart';
import 'admob_stub.dart' if (dart.library.io) 'admob_factory.dart';
import 'mock_ads_service.dart';

/// Mock ads by default so the game runs anywhere (desktop, web, tests).
/// Real AdMob test ads on a phone:
///   flutter run --dart-define=ADS=admob
final adsServiceProvider = Provider<AdsService>((ref) {
  const mode = String.fromEnvironment('ADS', defaultValue: 'mock');
  return mode == 'admob' ? createAdMobService() : MockAdsService();
});
