import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_router.dart';
import '../../services/settings.dart';
import '../../theme/tokens.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/naw_button.dart';
import '../../widgets/sliding_segments.dart';
import '../../widgets/token_painter.dart';
import '../game/game_controller.dart';
import 'game_setup.dart';
import '../../services/haptics.dart';

/// Mode setup: difficulty + who goes first (vs AI) or player names (friend).
class ModeSetupScreen extends ConsumerStatefulWidget {
  const ModeSetupScreen({super.key});

  @override
  ConsumerState<ModeSetupScreen> createState() => _ModeSetupScreenState();
}

class _ModeSetupScreenState extends ConsumerState<ModeSetupScreen> {
  late final TextEditingController _a;
  late final TextEditingController _b;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    final names = ref.read(setupProvider).friendNames;
    _a = TextEditingController(text: names[0]);
    _b = TextEditingController(text: names[1]);
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _start() {
    final setup = ref.read(setupProvider);
    if (setup.mode == GameMode.friend) {
      final a = _a.text.trim(), b = _b.text.trim();
      if (a.isEmpty || b.isEmpty) {
        Haptics.medium();
        setState(() => _showError = true);
        return;
      }
      ref.read(setupProvider.notifier).setFriendNames(a, b == a ? '$b 2' : b);
    }
    ref.read(gameControllerProvider.notifier).newGame();
    Navigator.of(context).pushNamed(Routes.game);
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final setup = ref.watch(setupProvider);
    final ctl = ref.read(setupProvider.notifier);
    final prefs = ref.watch(settingsProvider).motion;
    final ai = setup.mode == GameMode.vsAi;

    return Scaffold(
      body: AuroraBackground(
        prefs: prefs,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: tk.space1, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(Icons.arrow_back_rounded, color: tk.textPrimary),
                        ),
                        Expanded(
                          child: Text(ai ? 'Play vs AI' : 'Play with a Friend',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: tk.heading(NawTinTokens.scaleM)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(tk.space3, tk.space1, tk.space3, tk.space2),
                      child: ai ? _aiForm(context, setup, ctl) : _friendForm(context),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(tk.space3, 0, tk.space3, tk.space3),
                    child: NawButton(
                      label: 'Start game',
                      icon: Icons.play_arrow_rounded,
                      onPressed: _start,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) {
    final tk = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(t, style: tk.heading(NawTinTokens.scaleS)),
    );
  }

  Widget _aiForm(BuildContext context, GameSetup setup, SetupController ctl) {
    final tk = context.tokens;
    final d = setup.difficulty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Difficulty'),
        SlidingSegments(
          labels: [for (final x in Difficulty.values) x.label],
          selected: d.index,
          onChanged: (i) => ctl.setDifficulty(Difficulty.values[i]),
        ),
        SizedBox(height: tk.space2),
        GlassPanel(
          radius: tk.radiusM,
          padding: EdgeInsets.all(tk.space2),
          child: AnimatedSize(
            duration: tk.medium,
            curve: tk.emphasized,
            child: AnimatedSwitcher(
              duration: tk.medium,
              child: Column(
                key: ValueKey(d),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Stat(icon: Icons.psychology_rounded, label: 'Search', value: d.depth),
                      SizedBox(width: tk.space2),
                      _Stat(icon: Icons.timer_rounded, label: 'Turn timer', value: d.clock),
                    ],
                  ),
                  SizedBox(height: tk.space1 + 4),
                  Text(d.blurb, style: tk.body(NawTinTokens.scaleXS + 1)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: tk.space3),
        _label('Who goes first?'),
        SlidingSegments(
          labels: const ['You', GameSetup.aiName],
          selected: setup.humanFirst ? 0 : 1,
          thumbColor: setup.humanFirst ? tk.coral : tk.aqua,
          onChanged: (i) => ctl.setHumanFirst(i == 0),
        ),
        const SizedBox(height: 10),
        Text(
          setup.humanFirst
              ? 'You place two tokens on the opening turn. Naw Bot places the last two.'
              : 'Naw Bot opens with two tokens. You place the last two.',
          style: tk.body(NawTinTokens.scaleXS + 1),
        ),
      ],
    );
  }

  Widget _friendForm(BuildContext context) {
    final tk = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Player names'),
        _NameField(seat: 0, controller: _a, hint: 'Player 1', error: _showError && _a.text.trim().isEmpty),
        SizedBox(height: tk.space2),
        _NameField(seat: 1, controller: _b, hint: 'Player 2', error: _showError && _b.text.trim().isEmpty),
        SizedBox(height: tk.space2),
        Text(
          'Player 1 goes first and places two tokens on the opening turn. Each turn has a 2:00 clock.',
          style: tk.body(NawTinTokens.scaleXS + 1),
        ),
        if (_showError)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Give each player a name to start.', style: tk.body(NawTinTokens.scaleXS + 1, color: tk.danger)),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: tk.violet, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tk.body(NawTinTokens.scaleXS)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: tk.digits(NawTinTokens.scaleS)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.seat, required this.controller, required this.hint, required this.error});
  final int seat;
  final TextEditingController controller;
  final String hint;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final color = tk.seatColor(seat);
    return TextField(
      controller: controller,
      maxLength: 12,
      textCapitalization: TextCapitalization.words,
      style: tk.heading(NawTinTokens.scaleS, weight: FontWeight.w600),
      cursorColor: color,
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: tk.body(NawTinTokens.scaleS),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(8),
          child: TokenIcon(seat: seat, size: 32),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tk.radiusM),
          borderSide: BorderSide(color: error ? tk.danger : tk.glassBorder.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tk.radiusM),
          borderSide: BorderSide(color: error ? tk.danger : color, width: 1.6),
        ),
      ),
    );
  }
}
