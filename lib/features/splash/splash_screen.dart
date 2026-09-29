import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/engine.dart';
import '../../services/settings.dart';
import '../../theme/tokens.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/token_painter.dart';
import '../../widgets/wordmark.dart';
import '../../app_router.dart';

/// Splash: the board lines draw themselves in gold, three tokens drop onto a
/// line, then the wordmark and tagline fade in. Tap to skip.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    final reduce = ref.read(settingsProvider).reduceMotion;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: reduce ? 900 : 3600),
    )
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _leave();
      })
      ..forward();
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacementNamed(Routes.home);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final prefs = ref.watch(settingsProvider).motion;
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _leave,
        child: AuroraBackground(
          prefs: prefs,
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                final word = Curves.easeOut.transform(((t - 0.62) / 0.22).clamp(0.0, 1.0));
                final tag = Curves.easeOut.transform(((t - 0.78) / 0.2).clamp(0.0, 1.0));
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LayoutBuilder(
                      builder: (context, box) {
                        final side = math.min(MediaQuery.sizeOf(context).width * 0.66, 320.0);
                        return SizedBox.square(
                          dimension: side,
                          child: CustomPaint(painter: _SplashBoardPainter(tk, t)),
                        );
                      },
                    ),
                    SizedBox(height: tk.space4),
                    Opacity(
                      opacity: word,
                      child: Transform.translate(
                        offset: Offset(0, (1 - word) * 12),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Wordmark(size: 44),
                        ),
                      ),
                    ),
                    SizedBox(height: tk.space2),
                    Opacity(
                      opacity: tag,
                      child: Text(
                        'Make three. Eat one.',
                        style: tk.body(NawTinTokens.scaleS, color: tk.textPrimary.withValues(alpha: 0.85))
                            .copyWith(letterSpacing: 1.4),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashBoardPainter extends CustomPainter {
  _SplashBoardPainter(this.tk, this.t);
  final NawTinTokens tk;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final m = size.width * 0.06;
    final u = (size.width - 2 * m) / 6;
    Offset pos(int p) {
      final g = Board.gridOf(p);
      return Offset(m + g[0] * u, m + g[1] * u);
    }

    // 0.00 - 0.50: the 16 lines draw themselves one after another
    for (var l = 0; l < Board.lineCount; l++) {
      final start = l * 0.024;
      final k = Curves.easeInOut.transform(((t / 0.5 - start) / 0.4).clamp(0.0, 1.0));
      if (k <= 0) continue;
      final pts = Board.lines[l];
      final a = pos(pts.first), b = Offset.lerp(a, pos(pts.last), k)!;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = u * 0.2
          ..strokeCap = StrokeCap.round
          ..color = tk.gold.withValues(alpha: 0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.15),
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = math.max(2, u * 0.05)
          ..strokeCap = StrokeCap.round
          ..color = tk.gold,
      );
    }
    for (var p = 0; p < Board.pointCount; p++) {
      final k = ((t / 0.5 - 0.3) / 0.5).clamp(0.0, 1.0);
      if (k > 0) {
        canvas.drawCircle(
          pos(p),
          u * 0.11 * k,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, u * 0.035)
            ..color = tk.gold,
        );
      }
    }

    // 0.42 - 0.66: three tokens drop onto the outer top line (0, 1, 2)
    const seats = [0, 1, 0];
    for (var i = 0; i < 3; i++) {
      final s = ((t - 0.42 - i * 0.07) / 0.14).clamp(0.0, 1.0);
      if (s <= 0) continue;
      final fall = Curves.easeIn.transform((s / 0.75).clamp(0.0, 1.0));
      final land = ((s - 0.75) / 0.25).clamp(0.0, 1.0);
      final sq = math.sin(land * math.pi);
      final target = pos(i);
      paintToken(
        canvas,
        target.translate(0, -(1 - fall) * u * 3.5),
        u * 0.36,
        seat: seats[i],
        tk: tk,
        squashX: land > 0 ? 1 + 0.2 * sq : 0.92,
        squashY: land > 0 ? 1 - 0.22 * sq : 1.12,
      );
    }
  }

  @override
  bool shouldRepaint(_SplashBoardPainter old) => old.t != t;
}
