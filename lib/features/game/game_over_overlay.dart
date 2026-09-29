import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/engine/engine.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/glow_text.dart';
import 'game_controller.dart';

/// Winner banner with confetti, per-player stats and a rematch button.
/// (Stage 3 adds Change mode / Home and the final layout.)
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({
    super.key,
    required this.ui,
    required this.onRematch,
    this.prefs = const MotionPrefs(),
  });

  final GameUiState ui;
  final VoidCallback onRematch;
  final MotionPrefs prefs;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _reason(GameResult r) => switch (r.reason) {
        GameEndReason.tokensReduced => 'Reduced to two tokens.',
        GameEndReason.noLegalMoves => 'No legal move left.',
        GameEndReason.repetition => 'The same position came up three times.',
        GameEndReason.disqualified => 'Disqualified after two timeouts.',
      };

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final ui = widget.ui;
    final r = ui.game.result!;
    final winner = r.winner;
    final color = winner == null ? tk.gold : tk.seatColor(winner);
    final title = winner == null ? 'DRAW' : '${ui.names[winner].toUpperCase()} WINS';

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        if (winner != null && !widget.prefs.reduceMotion)
          IgnorePointer(
            child: CustomPaint(
              painter: _ConfettiPainter(_c, [color, tk.gold, tk.violet, tk.lime], widget.prefs.lowPower ? 30 : 90),
            ),
          ),
        Center(
          child: Padding(
            padding: EdgeInsets.all(tk.space3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassPanel(
                glow: color,
                padding: EdgeInsets.all(tk.space3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: GlowText(
                        title,
                        style: tk.display(NawTinTokens.scaleL + 6),
                        colors: [tk.goldGlow, color],
                        glow: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_reason(r), textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleS)),
                    SizedBox(height: tk.space2),
                    _StatRow(label: 'Tokens eaten', values: ui.eaten, names: ui.names),
                    _StatRow(label: 'Lines formed', values: ui.linesFormed, names: ui.names),
                    _StatRow(label: 'Begi / Treghi', values: ui.swings, names: ui.names),
                    SizedBox(height: tk.space3),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: tk.violet,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tk.radiusL)),
                        ),
                        onPressed: widget.onRematch,
                        child: Text('Rematch', style: tk.heading(NawTinTokens.scaleS)),
                      ),
                    ),
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

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.values, required this.names});
  final String label;
  final List<int> values;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text('${values[0]}', style: tk.digits(NawTinTokens.scaleM, color: tk.coral)),
          Expanded(
            child: Text(label, textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleXS)),
          ),
          Text('${values[1]}', style: tk.digits(NawTinTokens.scaleM, color: tk.aqua)),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.anim, this.colors, this.count) : super(repaint: anim);
  final Animation<double> anim;
  final List<Color> colors;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(5);
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble();
      final speed = 0.5 + rnd.nextDouble();
      final phase = rnd.nextDouble();
      final y = ((anim.value * speed + phase) % 1.0);
      final sway = math.sin((anim.value * 6 + phase * 10) * math.pi) * 18;
      canvas.save();
      canvas.translate(x * size.width + sway, y * (size.height + 40) - 20);
      canvas.rotate(anim.value * 8 * speed + i);
      canvas.drawRect(
        const Rect.fromLTWH(-4, -2, 8, 4),
        Paint()..color = colors[i % colors.length].withValues(alpha: 0.9),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
