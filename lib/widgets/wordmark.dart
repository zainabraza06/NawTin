import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'glow_text.dart';
import 'token_painter.dart';

/// "NAW [mark] TIN": display font, gold-to-coral gradient with a soft glow.
/// Between the words sits the logo mark, a coral-aqua-coral line of three.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    Widget word(String t) => GlowText(
          t,
          style: tk.display(size),
          colors: [tk.goldGlow, tk.gold, tk.coral],
          glow: tk.coral,
          glowBlur: size * 0.45,
        );
    return Semantics(
      label: 'Naw Tin',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            word('NAW'),
            SizedBox(width: size * 0.3),
            LogoMark(width: size * 1.5),
            SizedBox(width: size * 0.3),
            word('TIN'),
          ],
        ),
      ),
    );
  }
}

/// A gold board line with three tokens on it (coral, aqua, coral).
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.width = 60});

  final double width;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return CustomPaint(
      size: Size(width, width * 0.4),
      painter: _LogoMarkPainter(tk),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  _LogoMarkPainter(this.tk);
  final NawTinTokens tk;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final r = size.height * 0.36;
    final line = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.height * 0.09
      ..color = tk.gold;
    canvas.drawLine(Offset(r * 0.2, y), Offset(size.width - r * 0.2, y), line);
    for (var i = 0; i < 3; i++) {
      final x = r + i * (size.width - 2 * r) / 2;
      paintToken(canvas, Offset(x, y), r, seat: i == 1 ? 1 : 0, tk: tk, glow: 0.7, symbol: false);
    }
  }

  @override
  bool shouldRepaint(_LogoMarkPainter old) => false;
}
