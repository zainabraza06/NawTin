import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Midnight gradient with a slow aurora (violet + teal blobs at 15% opacity)
/// and faint drifting stars.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child, this.prefs = const MotionPrefs()});

  final Widget child;
  final MotionPrefs prefs;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

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
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _AuroraPainter(tk, _c, widget.prefs.lowPower ? 18 : 48),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _Star {
  const _Star(this.x, this.y, this.speed, this.phase, this.radius);
  final double x, y, speed, phase, radius;
}

/// Star field generated once (not re-rolled with a Random every frame).
final List<_Star> _stars = () {
  final rnd = math.Random(11);
  return List.generate(
    64,
    (_) => _Star(rnd.nextDouble(), rnd.nextDouble(), 0.2 + rnd.nextDouble() * 0.6,
        rnd.nextDouble() * math.pi * 2, 0.6 + rnd.nextDouble() * 1.1),
  );
}();

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.tk, this.anim, this.starCount) : super(repaint: anim);

  final NawTinTokens tk;
  final Animation<double> anim;
  final int starCount;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tk.bgTop, tk.bgMid, tk.bgBottom],
        ).createShader(rect),
    );

    final t = anim.value * math.pi * 2;
    // a soft radial falloff instead of a full-screen blur filter
    void blob(Color color, Offset center, double radius) {
      canvas.drawCircle(
        center,
        radius * 1.6,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.08), color.withValues(alpha: 0)],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius * 1.6)),
      );
    }

    blob(
      tk.violet,
      Offset(size.width * (0.25 + 0.12 * math.sin(t)), size.height * (0.28 + 0.06 * math.cos(t))),
      size.shortestSide * 0.55,
    );
    blob(
      tk.aqua,
      Offset(size.width * (0.8 + 0.1 * math.cos(t * 1.0)), size.height * (0.72 + 0.07 * math.sin(t))),
      size.shortestSide * 0.5,
    );

    final star = Paint();
    for (var i = 0; i < _stars.length && i < starCount; i++) {
      final st = _stars[i];
      final dx = (st.x + anim.value * st.speed * 0.15) % 1.0;
      final tw = 0.35 + 0.35 * math.sin(t * 2 + st.phase);
      star.color = Colors.white.withValues(alpha: 0.12 + 0.3 * tw);
      canvas.drawCircle(Offset(dx * size.width, st.y * size.height), st.radius, star);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.tk != tk || old.starCount != starCount;
}
