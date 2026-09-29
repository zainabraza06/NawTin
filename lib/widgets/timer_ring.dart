import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Circular countdown: violet normally, amber under 30s, pulsing red under
/// 10s (with a slight shake). Stage 5 feeds it the live countdown; until then
/// the game screen shows a full ring.
class TimerRing extends StatefulWidget {
  const TimerRing({
    super.key,
    required this.progress,
    required this.secondsLeft,
    this.size = 72,
    this.accent,
  });

  /// 1.0 = full time left, 0.0 = out of time.
  final double progress;
  final int secondsLeft;
  final double size;
  final Color? accent;

  @override
  State<TimerRing> createState() => _TimerRingState();
}

class _TimerRingState extends State<TimerRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final s = widget.secondsLeft;
    final urgent = s <= 10;
    final color = urgent ? tk.danger : (s <= 30 ? tk.amber : (widget.accent ?? tk.violet));
    final mm = (s ~/ 60).toString();
    final ss = (s % 60).toString().padLeft(2, '0');
    return Semantics(
      label: 'Time left $mm minutes $ss seconds',
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final pulse = urgent ? _c.value : 0.0;
          final shake = urgent ? math.sin(_c.value * math.pi * 6) * 1.6 : 0.0;
          return Transform.translate(
            offset: Offset(shake, 0),
            child: SizedBox.square(
              dimension: widget.size,
              child: CustomPaint(
                painter: _RingPainter(widget.progress, color, pulse, tk),
                child: Center(
                  child: Text('$mm:$ss', style: tk.digits(widget.size * 0.27, color: urgent ? tk.danger : tk.textPrimary)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color, this.pulse, this.tk);
  final double progress;
  final Color color;
  final double pulse;
  final NawTinTokens tk;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final stroke = size.width * 0.09;
    final r = (size.width - stroke) / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.1),
    );
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.solid, stroke * (0.4 + 0.5 * pulse)),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.pulse != pulse;
}
