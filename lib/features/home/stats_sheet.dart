import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/stats.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/naw_button.dart';
import '../setup/game_setup.dart';

Future<void> showStatsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _StatsSheet(),
  );
}

class _StatsSheet extends ConsumerWidget {
  const _StatsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tokens;
    final s = ref.watch(statsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tk.space2),
        child: GlassPanel(
          padding: EdgeInsets.all(tk.space3),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Your stats', style: tk.heading(NawTinTokens.scaleM)),
                SizedBox(height: tk.space2),
                if (s.isEmpty) const _Empty() else ..._content(context, s, ref),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, PlayerStats s, WidgetRef ref) {
    final tk = context.tokens;
    return [
      Row(
        children: [
          _Big(label: 'Games', value: '${s.totalGames}'),
          _Big(label: 'Win streak', value: '${s.streak}'),
          _Big(label: 'Best streak', value: '${s.bestStreak}'),
        ],
      ),
      SizedBox(height: tk.space2),
      Text('Against the AI', style: tk.heading(NawTinTokens.scaleS)),
      const SizedBox(height: 8),
      for (final d in Difficulty.values) _Row(label: d.label, record: s.recordFor(d)),
      SizedBox(height: tk.space2),
      Text('Lifetime', style: tk.heading(NawTinTokens.scaleS)),
      const SizedBox(height: 8),
      _Line('Tokens eaten', s.tokensEaten),
      _Line('Lines formed', s.linesFormed),
      _Line('Begi / treghi', s.swings),
      _Line('Friend games', s.friendGames),
      SizedBox(height: tk.space2),
      NawButton(
        label: 'Reset stats',
        style: NawButtonStyle.ghost,
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: tk.bgMid,
              title: Text('Reset all stats?', style: tk.heading(NawTinTokens.scaleM)),
              content: Text('This clears your record on this device. It cannot be undone.', style: tk.body(NawTinTokens.scaleS)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Reset', style: TextStyle(color: tk.danger))),
              ],
            ),
          );
          if (ok == true) ref.read(statsProvider.notifier).reset();
        },
      ),
    ];
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tk.space2),
      child: Column(
        children: [
          Icon(Icons.emoji_events_outlined, size: 48, color: tk.gold),
          const SizedBox(height: 12),
          Text('No games yet', style: tk.heading(NawTinTokens.scaleS)),
          const SizedBox(height: 4),
          Text(
            'Finish a game and your record, streaks and eaten tokens show up here.',
            textAlign: TextAlign.center,
            style: tk.body(NawTinTokens.scaleXS + 1),
          ),
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: tk.digits(NawTinTokens.scaleL, color: tk.goldGlow)),
          Text(label, style: tk.body(NawTinTokens.scaleXS)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.record});
  final String label;
  final Record record;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(label, style: tk.body(NawTinTokens.scaleS, color: tk.textPrimary))),
          Text('${record.wins}', style: tk.digits(NawTinTokens.scaleS, color: tk.lime)),
          Text('  W   ', style: tk.body(NawTinTokens.scaleXS)),
          Text('${record.losses}', style: tk.digits(NawTinTokens.scaleS, color: tk.coral)),
          Text('  L   ', style: tk.body(NawTinTokens.scaleXS)),
          Text('${record.draws}', style: tk.digits(NawTinTokens.scaleS)),
          Text('  D', style: tk.body(NawTinTokens.scaleXS)),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: tk.body(NawTinTokens.scaleS))),
          Text('$value', style: tk.digits(NawTinTokens.scaleS)),
        ],
      ),
    );
  }
}
