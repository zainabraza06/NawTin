import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'features/game/game_screen.dart';
import 'features/home/home_screen.dart';
import 'features/online/debug/online_debug_screen.dart';
import 'features/how_to_play/how_to_play_screen.dart';
import 'features/setup/mode_setup_screen.dart';
import 'features/splash/splash_screen.dart';

abstract final class Routes {
  static const splash = '/';
  static const home = '/home';
  static const setup = '/setup';
  static const game = '/game';
  static const how = '/how';

  /// Developer console for the online layer. Debug builds only.
  static const onlineDebug = '/online-debug';
}

/// Route factory with a shared-axis style transition: the incoming page
/// fades and slides in while the outgoing one eases back.
/// Developer-only pages. `kDebugMode` is a compile-time constant, so in a
/// release build this whole branch (and the debug screen) is removed.
/// [debugBuild] lets tests prove a release build cannot reach it.
Widget? debugPageFor(String? name, {bool debugBuild = kDebugMode}) {
  if (kDebugMode && debugBuild) {
    if (name == Routes.onlineDebug) return const OnlineDebugScreen();
  }
  return null;
}

/// The screen for a route name.
Widget pageFor(String? name, {bool debugBuild = kDebugMode}) =>
    debugPageFor(name, debugBuild: debugBuild) ??
    switch (name) {
      Routes.home => const HomeScreen(),
      Routes.setup => const ModeSetupScreen(),
      Routes.game => const GameScreen(),
      Routes.how => const HowToPlayScreen(),
      _ => const SplashScreen(),
    };

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  final Widget page = pageFor(settings.name);
  final fadeOnly = settings.name == Routes.home || settings.name == Routes.splash;
  return PageRouteBuilder<void>(
    settings: settings,
    // opaque: Flutter stops animating/painting the screen underneath
    opaque: true,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, anim, secondary, child) {
      final curved = CurvedAnimation(parent: anim, curve: const Cubic(0.22, 1.0, 0.36, 1.0));
      final out = CurvedAnimation(parent: secondary, curve: Curves.easeInOut);
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(curved),
        child: fadeOnly
            ? child
            : SlideTransition(
                position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(curved),
                child: FadeTransition(
                  opacity: Tween<double>(begin: 1, end: 0.6).animate(out),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1, end: 0.97).animate(out),
                    child: child,
                  ),
                ),
              ),
      );
    },
  );
}
