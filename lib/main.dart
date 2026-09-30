import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_router.dart';
import 'services/prefs_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // fonts are bundled in assets/google_fonts: never hit the network for them
  GoogleFonts.config.allowRuntimeFetching = false;
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
  runApp(ProviderScope(
    overrides: [prefsStoreProvider.overrideWithValue(SharedPrefsStore(prefs))],
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
      initialRoute: Routes.splash,
      onGenerateRoute: onGenerateRoute,
    );
  }
}
