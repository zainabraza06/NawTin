import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_router.dart';
import 'services/prefs_store.dart';
import 'services/settings.dart';
import 'theme/tokens.dart';
import 'widgets/friendly_error.dart';
import 'services/sound/audio_sound_service.dart';
import 'services/sound/sound_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // fonts are bundled in assets/google_fonts: never hit the network for them
  // Both players open with two tokens (the default). The original order, with
  // a closing double for player 2, is: Rules.placementRule =
  // PlacementRule.openingAndClosingDouble (see README, "Seat balance").
  GoogleFonts.config.allowRuntimeFetching = false;
  // players never see a red error screen or a stack trace in release builds
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => FriendlyError(detail: details.exceptionAsString());
  }
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Bungee', 'Sora', 'Inter', 'Space Grotesk'],
      'These fonts are licensed under the SIL Open Font License, Version 1.1. '
      'See https://openfontlicense.org',
    );
  });
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  final prefs = await SharedPreferences.getInstance();
  final audio = AudioSoundService(voices: await loadVoiceAssets());
  runApp(ProviderScope(
    overrides: [
      prefsStoreProvider.overrideWithValue(SharedPrefsStore(prefs)),
      soundServiceProvider.overrideWith((ref) {
        bindSoundSettings(ref, audio);
        ref.onDispose(audio.dispose);
        return audio;
      }),
    ],
    child: const NawTinApp(),
  ));
}

class NawTinApp extends StatelessWidget {
  const NawTinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Naw Tin',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) => Consumer(
        builder: (context, ref, _) => MotionScope(
          prefs: ref.watch(settingsProvider).motion,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      initialRoute: Routes.splash,
      onGenerateRoute: onGenerateRoute,
    );
  }
}
