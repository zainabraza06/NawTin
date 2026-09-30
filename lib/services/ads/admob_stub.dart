import 'ads_service.dart';

/// AdMob does not exist on web; asking for it there is a programming error.
AdsService createAdMobService() =>
    throw UnsupportedError('AdMob is only available on Android and iOS');
