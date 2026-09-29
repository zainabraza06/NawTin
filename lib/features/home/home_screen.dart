import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_router.dart';
import '../../services/settings.dart';
import '../../theme/tokens.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/naw_button.dart';
import '../../widgets/wordmark.dart';
import '../setup/game_setup.dart';
import 'floating_tokens.dart';
import 'settings_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tokens;
    final prefs = ref.watch(settingsProvider).motion;

    void open(GameMode m) {
      ref.read(setupProvider.notifier).setMode(m);
      Navigator.of(context).pushNamed(Routes.setup);
    }

    return Scaffold(
      body: AuroraBackground(
        prefs: prefs,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FloatingTokens(prefs: prefs),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: tk.space3),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Settings',
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            onPressed: () => showSettingsSheet(context),
                            icon: Icon(Icons.tune_rounded, color: tk.textPrimary),
                          ),
                        ),
                        const Spacer(flex: 2),
                        const Wordmark(size: 44),
                        SizedBox(height: tk.space1),
                        Text(
                          'Make three. Eat one.',
                          style: tk.body(NawTinTokens.scaleS, color: tk.textPrimary.withValues(alpha: 0.8))
                              .copyWith(letterSpacing: 1.4),
                        ),
                        const Spacer(flex: 3),
                        NawButton(
                          label: 'Play vs AI',
                          caption: 'Easy, Medium or Hard',
                          icon: Icons.smart_toy_rounded,
                          onPressed: () => open(GameMode.vsAi),
                        ),
                        SizedBox(height: tk.space2),
                        NawButton(
                          label: 'Play with a Friend',
                          caption: 'Two players, one device',
                          icon: Icons.people_alt_rounded,
                          style: NawButtonStyle.secondary,
                          onPressed: () => open(GameMode.friend),
                        ),
                        SizedBox(height: tk.space2),
                        NawButton(
                          label: 'How to Play',
                          icon: Icons.menu_book_rounded,
                          style: NawButtonStyle.ghost,
                          onPressed: () => Navigator.of(context).pushNamed(Routes.how),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
