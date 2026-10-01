import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_router.dart';
import '../../services/settings.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass_panel.dart';

const _languages = <(String, String, bool)>[
  ('en', 'English', true),
  ('ur', 'اردو (Urdu)', false),
  ('hi', 'हिन्दी (Hindi)', false),
];

/// Bottom sheet with sound, language and accessibility switches.
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tokens;
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tk.space2),
        child: GlassPanel(
          padding: EdgeInsets.all(tk.space3),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: tk.heading(NawTinTokens.scaleM)),
                SizedBox(height: tk.space2),
                _Toggle(
                  title: 'Sound',
                  subtitle: 'Effects and call voices',
                  value: s.soundOn,
                  onChanged: c.setSound,
                ),
                _Toggle(
                  title: 'Vibration',
                  subtitle: 'Haptic taps for moves, calls and the clock',
                  value: s.hapticsOn,
                  onChanged: c.setHaptics,
                ),
                _Toggle(
                  title: 'Reduce motion',
                  subtitle: 'Calmer animations, no board tilt or shake',
                  value: s.reduceMotion,
                  onChanged: c.setReduceMotion,
                ),
                _Toggle(
                  title: 'Low-power mode',
                  subtitle: 'Fewer particles and background effects',
                  value: s.lowPower,
                  onChanged: c.setLowPower,
                ),
                if (kDebugMode)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Online test console (debug)'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed(Routes.onlineDebug);
                    },
                  ),
                SizedBox(height: tk.space2),
                Text('Language', style: tk.heading(NawTinTokens.scaleS)),
                const SizedBox(height: 8),
                for (final (code, name, ready) in _languages)
                  Semantics(
                    button: true,
                    selected: s.language == code,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(tk.radiusS),
                      onTap: ready ? () => c.setLanguage(code) : null,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: tk.body(NawTinTokens.scaleS,
                                    color: ready ? tk.textPrimary : tk.textMuted.withValues(alpha: 0.6)),
                              ),
                            ),
                            if (!ready)
                              Text('Coming soon', style: tk.body(NawTinTokens.scaleXS))
                            else
                              Icon(
                                s.language == code ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: s.language == code ? tk.violet : tk.textMuted,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return MergeSemantics(
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: tk.lime,
        title: Text(title, style: tk.heading(NawTinTokens.scaleS, weight: FontWeight.w600)),
        subtitle: Text(subtitle, style: tk.body(NawTinTokens.scaleXS)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
