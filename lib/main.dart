import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/game/game_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const ProviderScope(child: NawTinApp()));
}

class NawTinApp extends StatelessWidget {
  const NawTinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Naw Tin',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Stage 3 replaces this with splash / home navigation.
      home: const GameScreen(),
    );
  }
}
