import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Draws one glowing token. Shared by the board, the player cards and the
/// captured-token icons so every token looks identical.
///
/// Colour-blind safe: seat 0 carries a hollow circle, seat 1 a diamond.
void paintToken(
  Canvas canvas,
  Offset center,
  double r, {
  required int seat,
  required NawTinTokens tk,
  double glow = 1,
  double alpha = 1,
  double scale = 1,
  double squashX = 1,
  double squashY = 1,
  bool symbol = true,
}) {
  if (alpha <= 0) return;
  final base = tk.seatColor(seat);
  final light = Color.lerp(base, Colors.white, 0.55)!;
  final dark = Color.lerp(base, const Color(0xFF1A0A2A), 0.45)!;

  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(scale * squashX, scale * squashY);

  // outer glow
  if (glow > 0) {
    // a radial falloff reads like a blurred halo but costs no blur filter
    final halo = r * 1.9;
    canvas.drawCircle(
      Offset.zero,
      halo,
      Paint()
        ..shader = RadialGradient(
          colors: [
            base.withValues(alpha: 0.55 * glow * alpha),
            base.withValues(alpha: 0.22 * glow * alpha),
            base.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: halo)),
    );
  }

  // body with an off-centre radial highlight
  final body = Rect.fromCircle(center: Offset.zero, radius: r);
  canvas.drawCircle(
    Offset.zero,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 1.0,
        colors: [
          light.withValues(alpha: alpha),
          base.withValues(alpha: alpha),
          dark.withValues(alpha: alpha),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(body),
  );

  // thin rim
  canvas.drawCircle(
    Offset.zero,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.08)
      ..color = Colors.white.withValues(alpha: 0.35 * alpha),
  );

  // specular dot
  canvas.drawCircle(
    Offset(-r * 0.32, -r * 0.38),
    r * 0.16,
    Paint()..color = Colors.white.withValues(alpha: 0.55 * alpha),
  );

  if (symbol) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, r * 0.13)
      ..strokeJoin = StrokeJoin.round
      ..color = tk.ink.withValues(alpha: 0.7 * alpha);
    if (seat == 0) {
      canvas.drawCircle(Offset.zero, r * 0.34, p);
    } else {
      final d = r * 0.42;
      canvas.drawPath(
        Path()
          ..moveTo(0, -d)
          ..lineTo(d, 0)
          ..lineTo(0, d)
          ..lineTo(-d, 0)
          ..close(),
        p,
      );
    }
  }
  canvas.restore();
}

/// Small token icon for cards and counters.
class TokenIcon extends StatelessWidget {
  const TokenIcon({super.key, required this.seat, this.size = 24, this.glow = 0.6});

  final int seat;
  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return CustomPaint(
      size: Size.square(size),
      painter: _TokenIconPainter(seat, tk, glow),
    );
  }
}

class _TokenIconPainter extends CustomPainter {
  _TokenIconPainter(this.seat, this.tk, this.glow);
  final int seat;
  final NawTinTokens tk;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    paintToken(canvas, size.center(Offset.zero), size.width * 0.36,
        seat: seat, tk: tk, glow: glow);
  }

  @override
  bool shouldRepaint(_TokenIconPainter old) =>
      old.seat != seat || old.glow != glow;
}
