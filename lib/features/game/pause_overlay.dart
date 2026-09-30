import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/naw_button.dart';

/// Covers the board while paused so nobody can study the position for free.
class PausedOverlay extends StatelessWidget {
  const PausedOverlay({
    super.key,
    required this.pausesLeft,
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
  });

  final int pausesLeft;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final left = pausesLeft > 0
        ? 'You have $pausesLeft ${pausesLeft == 1 ? "pause" : "pauses"} left in this game.'
        : 'That was your last pause in this game.';
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: tk.bgTop.withValues(alpha: 0.94)),
        Center(
          child: Padding(
            padding: EdgeInsets.all(tk.space3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassPanel(
                padding: EdgeInsets.all(tk.space3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Paused', textAlign: TextAlign.center, style: tk.heading(NawTinTokens.scaleL)),
                    const SizedBox(height: 8),
                    Text(
                      'The clock is stopped and the board is hidden. $left',
                      textAlign: TextAlign.center,
                      style: tk.body(NawTinTokens.scaleS),
                    ),
                    SizedBox(height: tk.space3),
                    NawButton(label: 'Resume', icon: Icons.play_arrow_rounded, onPressed: onResume),
                    SizedBox(height: tk.space1),
                    NawButton(label: 'Restart game', style: NawButtonStyle.secondary, onPressed: onRestart),
                    SizedBox(height: tk.space1),
                    NawButton(label: 'Quit to home', style: NawButtonStyle.ghost, onPressed: onQuit),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
