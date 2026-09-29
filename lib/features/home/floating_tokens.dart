import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/token_painter.dart';

/// Tokens drifting slowly behind the home screen.
class FloatingTokens extends StatefulWidget {
  const FloatingTokens({super.key, this.prefs = const MotionPrefs()});

  final MotionPrefs prefs;

  @override
  State<FloatingTokens> createState() => _FloatingTokensState();
}

class _FloatingTokensState extends State<FloatingTokens>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void initState() {
    super.initState();
    if (!widget.prefs.reduceMotion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _FloatPainter(tk, _c, widget.prefs.lowPower ? 5 : 10),
        ),
      ),
    );
  }
}

class _FloatPainter extends CustomPainter {
  _FloatPainter(this.tk, this.anim, this.count) : super(repaint: anim);
  final NawTinTokens tk;
  final Animation<double> anim;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(3);
    final t = anim.value * math.pi * 2;
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble();
      final y = rnd.nextDouble();
      final r = 10.0 + rnd.nextDouble() * 16;
      final ph = rnd.nextDouble() * math.pi * 2;
      final sp = 1 + rnd.nextInt(2);
      final c = Offset(
        (x + 0.05 * math.sin(t * sp + ph)) * size.width,
        (y + 0.04 * math.cos(t * sp + ph)) * size.height,
      );
      paintToken(canvas, c, r,
          seat: i.isEven ? 0 : 1, tk: tk, alpha: 0.22 + 0.1 * math.sin(t + ph), glow: 0.5);
    }
  }

  @override
  bool shouldRepaint(_FloatPainter old) => false;
}
