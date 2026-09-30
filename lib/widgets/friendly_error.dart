import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Replaces Flutter's red error screen in release builds with something that
/// matches the game and never shows a stack trace to a player.
class FriendlyError extends StatelessWidget {
  const FriendlyError({super.key, this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    const tk = NawTinTokens.dark;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: tk.bgTop,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, size: 44, color: tk.gold),
                const SizedBox(height: 12),
                Text(
                  'Something went sideways',
                  textAlign: TextAlign.center,
                  style: tk.heading(NawTinTokens.scaleM),
                ),
                const SizedBox(height: 6),
                Text(
                  'Go back and try again. Your stats are safe.',
                  textAlign: TextAlign.center,
                  style: tk.body(NawTinTokens.scaleS),
                ),
                if (detail != null && kDebugMode) ...[
                  const SizedBox(height: 12),
                  Text(detail!, textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleXS)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
