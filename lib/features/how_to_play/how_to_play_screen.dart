import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/settings.dart';
import '../../theme/tokens.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/glow_text.dart';
import '../../widgets/naw_button.dart';
import 'demo_player.dart';
import 'demo_scripts.dart';

class _Lesson {
  const _Lesson(this.tag, this.title, this.body, this.script, this.colors);
  final String tag;
  final String title;
  final String body;
  final DemoScript script;
  final List<Color> colors;
}

/// Swipeable illustrated lessons, each with a looping demo on the real board.
class HowToPlayScreen extends ConsumerStatefulWidget {
  const HowToPlayScreen({super.key});

  @override
  ConsumerState<HowToPlayScreen> createState() => _HowToPlayScreenState();
}

class _HowToPlayScreenState extends ConsumerState<HowToPlayScreen> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  List<_Lesson> _lessons(NawTinTokens tk) => [
        _Lesson(
          'THE GOAL',
          'Make three. Eat one.',
          'Each player has 9 tokens on a board of 24 points. Line up three '
              'tokens along a drawn line and you eat one of your opponent\'s. '
              'Reduce them to 2 tokens, or leave them with no legal move, and you win.',
          DemoScripts.board,
          [tk.goldGlow, tk.gold],
        ),
        _Lesson(
          'PLACEMENT',
          'Drop your tokens',
          'Each player opens with two tokens on their first turn, then you take turns '
              'placing one at a time. Lines you '
              'complete while placing count. Once all 18 tokens are down, movement begins.',
          DemoScripts.placement,
          [tk.aqua, tk.violet],
        ),
        _Lesson(
          'PHUTAS',
          'Warn them',
          'Set up a new line you can finish on your next turn, then press PHUTAS. '
              'It is only a friendly warning: forgetting it costs you nothing. '
              'It works while placing and while moving.',
          DemoScripts.phutas,
          [tk.lime, tk.goldGlow],
        ),
        _Lesson(
          'MACHYAS',
          'Line made, token eaten',
          'Complete a line by placing or sliding and you eat one opponent token. '
              'Tokens in a finished line are protected and cannot be eaten, unless '
              'every opponent token is protected. Slide only along the lines, one step at a time.',
          DemoScripts.machyas,
          [tk.goldGlow, tk.gold, tk.coral],
        ),
        _Lesson(
          'BEGI',
          'The double mill',
          'Get four tokens in place so that one token can swing between two '
              'neighbouring points and finish a line at each stop. Every swing '
              'after that is a Machyas. Only the token that is on a finished line is protected.',
          DemoScripts.begi,
          [tk.aqua, tk.violet, tk.coral],
        ),
        _Lesson(
          'TREGHI',
          'The triple mill',
          'The rarest setup: six fixed tokens and one that moves through three '
              'points, finishing a line at every stop. Any two neighbouring stops '
              'also make a begi. Build it and the board is yours.',
          DemoScripts.treghi,
          [tk.goldGlow, tk.coral, tk.violet, tk.aqua],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final prefs = ref.watch(settingsProvider).motion;
    final lessons = _lessons(tk);
    final last = _index == lessons.length - 1;

    return Scaffold(
      body: AuroraBackground(
        prefs: prefs,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
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
                          child: Text('How to Play', maxLines: 1, overflow: TextOverflow.ellipsis, style: tk.heading(NawTinTokens.scaleM)),
                        ),
                        Text('${_index + 1} / ${lessons.length}', style: tk.digits(NawTinTokens.scaleXS, color: tk.textMuted)),
                        SizedBox(width: tk.space2),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _page,
                      itemCount: lessons.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => _LessonCard(lesson: lessons[i], active: i == _index, prefs: prefs),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < lessons.length; i++)
                        AnimatedContainer(
                          duration: tk.medium,
                          curve: tk.emphasized,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 8,
                          width: i == _index ? 26 : 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: i == _index ? tk.violet : Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.all(tk.space3),
                    child: NawButton(
                      label: last ? 'Got it' : 'Next',
                      icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                      onPressed: () {
                        if (last) {
                          Navigator.of(context).maybePop();
                        } else {
                          _page.nextPage(duration: tk.slow, curve: tk.emphasized);
                        }
                      },
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
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.lesson, required this.active, required this.prefs});
  final _Lesson lesson;
  final bool active;
  final MotionPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: tk.space3, vertical: tk.space1),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: GlowText(
              lesson.tag,
              style: tk.display(NawTinTokens.scaleL),
              colors: lesson.colors,
              glow: lesson.colors.last,
            ),
          ),
          SizedBox(height: tk.space2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: DemoPlayer(script: lesson.script, active: active, prefs: prefs),
          ),
          SizedBox(height: tk.space2),
          Text(lesson.title, textAlign: TextAlign.center, style: tk.heading(NawTinTokens.scaleM)),
          const SizedBox(height: 8),
          Text(lesson.body, textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleS - 1, color: tk.textMuted)),
        ],
      ),
    );
  }
}
