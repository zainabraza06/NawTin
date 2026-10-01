import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../../widgets/glass_panel.dart';
import '../online_controller.dart';
import '../online_messages.dart';

/// The emote picker: six preset phrases, never free text. Buttons are
/// disabled while the courtesy cooldown (3 s between emotes, 6 a minute) runs.
Future<void> showEmoteSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _EmoteSheet(),
  );
}

class _EmoteSheet extends ConsumerWidget {
  const _EmoteSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tokens;
    final ctl = ref.read(onlineControllerProvider.notifier);
    final hidden = ref.watch(hideEmotesProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tk.space2),
        child: GlassPanel(
          padding: EdgeInsets.all(tk.space2),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Say something', style: tk.heading(NawTinTokens.scaleS)),
                SizedBox(height: tk.space2),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: tk.space1,
                  runSpacing: tk.space1,
                  children: [
                    for (final e in emoteSpecs)
                      ActionChip(
                        key: ValueKey('emote-${e.id}'),
                        avatar: Icon(e.icon, size: 20),
                        label: Text(e.label),
                        onPressed: () {
                          if (ctl.emote(e.id)) {
                            Navigator.of(context).pop();
                          } else {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Easy on the emotes. Try again ${waitText(ctl.emoteWait().inMilliseconds)}.",
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                          }
                        },
                      ),
                  ],
                ),
                SizedBox(height: tk.space1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Hide emotes',
                    style: tk.body(NawTinTokens.scaleXS),
                  ),
                  subtitle: Text(
                    "You won't see or send emotes.",
                    style: tk.body(
                      NawTinTokens.scaleXS - 1,
                      color: tk.textMuted,
                    ),
                  ),
                  value: hidden,
                  onChanged: (v) {
                    ref.read(hideEmotesProvider.notifier).set(v);
                    if (v) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short-lived speech bubble with a preset phrase, shown by the sender's card.
class EmoteBubble extends StatelessWidget {
  const EmoteBubble({super.key, required this.spec, required this.fromYou});

  final EmoteSpec spec;
  final bool fromYou;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final color = fromYou ? tk.violet : tk.aqua;
    return Semantics(
      liveRegion: true,
      label: '${fromYou ? 'You say' : 'Your opponent says'}: ${spec.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tk.radiusL),
          color: color.withValues(alpha: 0.92),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 18),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(spec.icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              spec.label,
              style: tk.heading(NawTinTokens.scaleS, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Report the other player: pick a reason (no free text). Returns the chosen
/// reason id, or null if cancelled.
Future<String?> showReportSheet(BuildContext context, String name) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final tk = ctx.tokens;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tk.space2),
          child: GlassPanel(
            padding: EdgeInsets.all(tk.space2),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Report $name', style: tk.heading(NawTinTokens.scaleS)),
                  SizedBox(height: tk.space1),
                  Text(
                    'What happened? We review reports to keep games friendly.',
                    style: tk.body(NawTinTokens.scaleXS, color: tk.textMuted),
                  ),
                  SizedBox(height: tk.space1),
                  for (final r in reportReasons)
                    ListTile(
                      key: ValueKey('report-${r.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.label, style: tk.body(NawTinTokens.scaleS)),
                      subtitle: Text(
                        r.hint,
                        style: tk.body(
                          NawTinTokens.scaleXS,
                          color: tk.textMuted,
                        ),
                      ),
                      onTap: () => Navigator.of(ctx).pop(r.id),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
