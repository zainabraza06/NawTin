import 'package:flutter/material.dart';

import 'features/game/game_screen.dart';
import 'features/home/home_screen.dart';
import 'features/how_to_play/how_to_play_screen.dart';
import 'features/setup/mode_setup_screen.dart';
import 'features/splash/splash_screen.dart';

abstract final class Routes {
  static const splash = '/';
  static const home = '/home';
  static const setup = '/setup';
  static const game = '/game';
  static const how = '/how';
}

/// Route factory with a shared-axis style transition: the incoming page
/// fades and slides in while the outgoing one eases back.
Route<dynamic> onGenerateRoute(RouteSettings settings) {
  final Widget page = switch (settings.name) {
    Routes.home => const HomeScreen(),
    Routes.setup => const ModeSetupScreen(),
    Routes.game => const GameScreen(),
    Routes.how => const HowToPlayScreen(),
    _ => const SplashScreen(),
  };
  final fadeOnly = settings.name == Routes.home || settings.name == Routes.splash;
  return PageRouteBuilder<void>(
    settings: settings,
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
