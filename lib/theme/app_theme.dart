import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildAppTheme() {
  const t = NawTinTokens.dark;
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: t.violet,
      brightness: Brightness.dark,
      surface: t.bgMid,
    ),
    scaffoldBackgroundColor: t.bgTop,
    splashFactory: NoSplash.splashFactory,
    extensions: const [t],
  );
  return base;
}
