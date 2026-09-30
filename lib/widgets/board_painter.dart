import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/engine/engine.dart';
import '../theme/tokens.dart';
import 'board_fx.dart';
import 'token_painter.dart';

/// Paints the whole board: lines, points, tokens and every effect.
///
/// Geometry: the 7x7 grid from `Board.gridOf` is scaled into the square
/// canvas with a margin, so points sit on a regular lattice.
class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.tk,
    required this.mask0,
    required this.mask1,
    required this.selected,
    required this.targets,
    required this.captureMask,
    required this.pickerSeat,
    required this.pulse,
    required this.fx,
    required this.fxSeconds,
    required this.phutasLines,
    required this.phutasT,
    required this.prefs,
    this.hint,
    super.repaint,
  });

  final NawTinTokens tk;
  final int mask0, mask1;
  final int? selected;
  final int targets;
  final int captureMask;
  final int pickerSeat;

  /// 0..1 looping value driving the gentle pulses.
  final double pulse;

  /// Animation of the last move, and how many seconds of it have elapsed.
  final FxTimeline? fx;
  final double fxSeconds;

  /// PHUTAS pulse: threatened lines and progress 0..1 (null = idle).
  final int phutasLines;
  final double? phutasT;
  final MotionPrefs prefs;

  /// Best move from the Hint 2 search, drawn in lime.
  final Move? hint;

  late double _u; // grid unit in pixels
  late double _m; // margin
  late double _r; // token radius

  Offset _pos(int p) {
    final g = Board.gridOf(p);
    return Offset(_m + g[0] * _u, _m + g[1] * _u);
  }

  /// Nearest point to [local] within a generous touch radius, or null.
  static int? pointAt(Offset local, Size size) {
    final side = math.min(size.width, size.height);
    final m = side * 0.09;
    final u = (side - 2 * m) / 6;
    int? best;
    var bestD = math.max(u * 0.62, 24.0);
    for (var p = 0; p < Board.pointCount; p++) {
      final g = Board.gridOf(p);
      final d = (Offset(m + g[0] * u, m + g[1] * u) - local).distance;
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    _m = side * 0.09;
    _u = (side - 2 * _m) / 6;
    _r = _u * 0.36;
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);

    _paintLineHighlights(canvas);
    _paintPoints(canvas);
    _paintTokens(canvas);
    _paintHint(canvas);
    _paintFx(canvas);
  }

  // ------------------------------------------------------------------ lines

  Path _linePath(int l) {
    final pts = Board.lines[l];
    return Path()
      ..moveTo(_pos(pts.first).dx, _pos(pts.first).dy)
      ..lineTo(_pos(pts.last).dx, _pos(pts.last).dy);
  }

  void _paintLineHighlights(Canvas canvas) {
    // the two lines a picked-up token can travel along
    final sel = selected;
    if (sel != null) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _u * 0.12
        ..color = tk.goldGlow.withValues(alpha: 0.35 + 0.15 * math.sin(pulse * math.pi * 2))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _u * 0.1);
      for (final l in Board.linesOfPoint[sel]) {
        canvas.drawPath(_linePath(l), paint);
      }
    }
  }

  // ----------------------------------------------------------------- points

  void _paintPoints(Canvas canvas) {
    final wave = 0.5 + 0.5 * math.sin(pulse * math.pi * 2);
    final placement = selected == null;
    for (var p = 0; p < Board.pointCount; p++) {
      final c = _pos(p);
      if (targets & bit(p) != 0) {
        // valid target: a ring that blooms outward. Placement targets are
        // everywhere, so they stay subtle.
        final a = placement ? 0.28 : 0.85;
        final rr = _u * (0.17 + 0.09 * wave);
        canvas.drawCircle(
          c,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _u * 0.045
            ..color = tk.goldGlow.withValues(alpha: a * (0.55 + 0.45 * wave))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, _u * 0.02),
        );
        if (!placement) {
          canvas.drawCircle(c, _u * 0.06,
              Paint()..color = tk.goldGlow.withValues(alpha: 0.6 + 0.4 * wave));
        }
      }
    }
  }

  // ----------------------------------------------------------------- tokens

  void _paintTokens(Canvas canvas) {
    final result = fx?.result;
    final animating = fx != null && result != null && fxSeconds < fx!.total;
    final movingTo = animating ? result.move.to : -1;
    final mover = result?.mover ?? 0;
    final picking = captureMask != 0;

    for (var seat = 0; seat < 2; seat++) {
      final mask = seat == 0 ? mask0 : mask1;
      final prot = Rules.protectedMask(mask);
      for (final p in bitsOf(mask)) {
        if (animating && p == movingTo && seat == mover) continue;
        var alpha = 1.0;
        var scale = 1.0;
        var center = _pos(p);
        final isSelected = selected == p;
        final capturable = picking && seat != pickerSeat && captureMask & bit(p) != 0;
        if (picking && seat != pickerSeat && !capturable) alpha = 0.4;
        if (isSelected && !picking) {
          // lifted: shadow underneath, spring-like scale
          canvas.drawOval(
            Rect.fromCenter(center: center + Offset(0, _r * 0.95), width: _r * 1.6, height: _r * 0.5),
            Paint()
              ..color = Colors.black.withValues(alpha: 0.4)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, _r * 0.3),
          );
          center = center.translate(0, -_r * 0.32);
          scale = 1.14 + 0.03 * math.sin(pulse * math.pi * 2);
        }
        paintToken(canvas, center, _r, seat: seat, tk: tk, alpha: alpha, scale: scale);
        if (prot & bit(p) != 0) _paintShield(canvas, center, alpha);
        if (capturable) _paintReticle(canvas, center);
      }
    }
  }

  void _paintShield(Canvas canvas, Offset c, double alpha) {
    canvas.drawCircle(
      c,
      _r * 1.32,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, _r * 0.09)
        ..color = tk.goldGlow.withValues(alpha: 0.75 * alpha),
    );
  }

  /// Targeting reticle: pulsing ring with four corner ticks.
  void _paintReticle(Canvas canvas, Offset c) {
    final wave = 0.5 + 0.5 * math.sin(pulse * math.pi * 4);
    final rr = _r * (1.5 + 0.18 * wave);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, _r * 0.11)
      ..strokeCap = StrokeCap.round
      ..color = tk.danger.withValues(alpha: 0.7 + 0.3 * wave);
    canvas.drawCircle(c, rr, paint..color = tk.danger.withValues(alpha: 0.35 + 0.35 * wave));
    paint.color = tk.danger;
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (rr - _r * 0.18), c + d * (rr + _r * 0.28), paint);
    }
  }

  // -------------------------------------------------------------------- hint

  /// Hint 2: lime pulsing ring on the destination, a marked token and a
  /// travelling arrow for slides, and a lime reticle on the token to eat.
  void _paintHint(Canvas canvas) {
    final h = hint;
    if (h == null) return;
    final wave = 0.5 + 0.5 * math.sin(pulse * math.pi * 4);
    final to = _pos(h.to);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _u * 0.06
      ..color = tk.lime.withValues(alpha: 0.6 + 0.4 * wave)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, _u * 0.03);
    canvas.drawCircle(to, _u * (0.3 + 0.1 * wave), ring);
    canvas.drawCircle(to, _u * 0.07, Paint()..color = tk.lime);

    if (!h.isPlacement) {
      final from = _pos(h.from);
      canvas.drawCircle(from, _r * 1.35, ring);
      // dashes flowing from the token to its destination
      final dir = to - from;
      const dashes = 6;
      for (var i = 0; i < dashes; i++) {
        final t = ((i / dashes) + pulse) % 1.0;
        canvas.drawCircle(
          from + dir * t,
          _u * 0.05,
          Paint()..color = tk.lime.withValues(alpha: 0.9 * math.sin(t * math.pi)),
        );
      }
    }
    if (h.hasCapture) {
      final c = _pos(h.capture);
      canvas.drawCircle(
        c,
        _r * (1.5 + 0.15 * wave),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, _r * 0.14)
          ..color = tk.lime.withValues(alpha: 0.5 + 0.5 * wave),
      );
    }
  }

  // --------------------------------------------------------------------- fx

  void _paintFx(Canvas canvas) {
    final f = fx;
    if (f != null && fxSeconds < f.total) {
      _paintMove(canvas, f);
      if (f.hasFlash) _paintFlash(canvas, f);
      if (f.hasFlash) _paintShatter(canvas, f);
      if (f.hasWave) _paintWave(canvas, f);
    }
    final pt = phutasT;
    if (pt != null && phutasLines != 0) _paintPhutas(canvas, pt);
  }

  /// The moving token: a drop with squash-and-stretch for placements, a
  /// glide with a comet trail and slight overshoot for slides.
  void _paintMove(Canvas canvas, FxTimeline f) {
    final m = f.result.move;
    final seat = f.result.mover;
    final s = (fxSeconds / f.moveEnd).clamp(0.0, 1.0);
    final to = _pos(m.to);

    if (m.isPlacement) {
      const fall = 0.68;
      if (s < fall) {
        final k = Curves.easeIn.transform(s / fall);
        final c = to.translate(0, -(1 - k) * _u * 3.2);
        paintToken(canvas, c, _r, seat: seat, tk: tk, squashX: 0.92, squashY: 1.12);
      } else {
        final k = (s - fall) / (1 - fall);
        final sq = math.sin(k * math.pi); // squash on impact, then recover
        paintToken(canvas, to, _r,
            seat: seat, tk: tk, squashX: 1 + 0.2 * sq, squashY: 1 - 0.22 * sq);
        // ring ripple on the point
        final rr = _u * (0.2 + 0.7 * k);
        canvas.drawCircle(
          to,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _u * 0.05 * (1 - k)
            ..color = tk.seatColor(seat).withValues(alpha: 0.8 * (1 - k)),
        );
      }
      return;
    }

    final from = _pos(m.from);
    final e = tk.overshoot.transform(s);
    final c = Offset.lerp(from, to, e)!;
    if (!prefs.lowPower) {
      for (var i = 6; i >= 1; i--) {
        final te = tk.overshoot.transform((s - i * 0.045).clamp(0.0, 1.0));
        final tp = Offset.lerp(from, to, te)!;
        canvas.drawCircle(
          tp,
          _r * (1 - i * 0.11),
          Paint()
            ..color = tk.seatColor(seat).withValues(alpha: 0.32 * (1 - i / 7))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, _r * 0.25),
        );
      }
    }
    paintToken(canvas, c, _r, seat: seat, tk: tk);
    if (s >= 1) {
      final k = ((fxSeconds - f.moveEnd) / 0.3).clamp(0.0, 1.0);
      if (k < 1) {
        canvas.drawCircle(
          to,
          _u * (0.2 + 0.5 * k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _u * 0.04 * (1 - k)
            ..color = tk.seatColor(seat).withValues(alpha: 0.7 * (1 - k)),
        );
      }
    }
  }

  /// White-gold flash on every completed line with a light sweeping along it.
  void _paintFlash(Canvas canvas, FxTimeline f) {
    final k = ((fxSeconds - f.flashStart) / f.flashDur).clamp(0.0, 1.0);
    if (k <= 0 || k >= 1) return;
    final env = math.sin(k * math.pi);
    final sweep = Curves.easeInOut.transform(k);
    for (var l = 0; l < Board.lineCount; l++) {
      if (f.result.completedLines & (1 << l) == 0) continue;
      final path = _linePath(l);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _u * 0.22
          ..color = tk.goldGlow.withValues(alpha: 0.75 * env)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, _u * 0.14),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _u * 0.07
          ..color = Colors.white.withValues(alpha: env),
      );
      final pts = Board.lines[l];
      final spot = Offset.lerp(_pos(pts.first), _pos(pts.last), sweep)!;
      _spot(canvas, spot, Colors.white, _u * 0.38, env);
    }
  }

  /// The eaten token trembles, then bursts into shards.
  void _paintShatter(Canvas canvas, FxTimeline f) {
    final cap = f.result.move.capture;
    if (cap < 0) return;
    final seat = 1 - f.result.mover;
    final c = _pos(cap);
    if (fxSeconds < f.shatterStart) {
      final wob = math.sin(fxSeconds * 60) * _r * 0.05;
      paintToken(canvas, c.translate(wob, 0), _r, seat: seat, tk: tk, glow: 1.4);
      return;
    }
    final k = ((fxSeconds - f.shatterStart) / f.shatterDur).clamp(0.0, 1.0);
    if (k >= 1) return;
    final rnd = math.Random(cap * 31 + 7);
    final n = prefs.lowPower ? 7 : 22;
    final color = tk.seatColor(seat);
    // shockwave
    canvas.drawCircle(
      c,
      _u * (0.2 + 1.1 * k),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _u * 0.08 * (1 - k)
        ..color = Colors.white.withValues(alpha: 0.6 * (1 - k)),
    );
    for (var i = 0; i < n; i++) {
      final ang = rnd.nextDouble() * math.pi * 2;
      final spd = (0.7 + rnd.nextDouble() * 1.7) * _u;
      final spin = rnd.nextDouble() * 6;
      final d = spd * Curves.easeOut.transform(k);
      final p = c + Offset(math.cos(ang), math.sin(ang)) * d + Offset(0, k * k * _u * 0.6);
      final sz = _r * (0.22 + rnd.nextDouble() * 0.26) * (1 - k * 0.8);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(spin * k);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: sz * 1.3, height: sz),
        Paint()..color = Color.lerp(color, Colors.white, 0.3)!.withValues(alpha: 1 - k),
      );
      canvas.restore();
    }
  }

  /// Energy wave running along the lines a begi/treghi connects.
  void _paintWave(Canvas canvas, FxTimeline f) {
    final k = ((fxSeconds - f.waveStart) / f.waveDur).clamp(0.0, 1.0);
    if (k <= 0 || k >= 1) return;
    final swing = f.result.announcedSwing!;
    final treghi = swing.pattern.kind == PatternKind.treghi;
    final color = treghi ? tk.goldGlow : tk.violet;
    final env = math.sin(k * math.pi);
    final lines = {...swing.pattern.stopLines, swing.pattern.travelLine};
    for (final l in lines) {
      final path = _linePath(l);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _u * (treghi ? 0.26 : 0.2)
          ..color = color.withValues(alpha: 0.6 * env)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, _u * 0.16),
      );
      final pts = Board.lines[l];
      final a = _pos(pts.first), b = _pos(pts.last);
      final runs = treghi ? 3 : 2;
      for (var i = 0; i < runs; i++) {
        final s = ((k * 2.2) + i / runs) % 1.0;
        _spot(canvas, Offset.lerp(a, b, s)!, Colors.white, _u * 0.3, env);
      }
    }
    // rings pulsing on the swing stops
    for (final p in swing.pattern.stops) {
      canvas.drawCircle(
        _pos(p),
        _u * (0.25 + 0.5 * k),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _u * 0.05
          ..color = color.withValues(alpha: 0.8 * (1 - k)),
      );
    }
  }

  /// PHUTAS: a travelling light along each threatened line.
  void _paintPhutas(Canvas canvas, double t) {
    final env = math.sin(t * math.pi);
    for (var l = 0; l < Board.lineCount; l++) {
      if (phutasLines & (1 << l) == 0) continue;
      canvas.drawPath(
        _linePath(l),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _u * 0.2
          ..color = tk.lime.withValues(alpha: 0.7 * env)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, _u * 0.14),
      );
      final pts = Board.lines[l];
      final s = (t * 2.4) % 1.0;
      _spot(canvas, Offset.lerp(_pos(pts.first), _pos(pts.last), s)!, tk.lime, _u * 0.4, env);
    }
  }

  void _spot(Canvas canvas, Offset c, Color color, double radius, double alpha) {
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.7 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6),
    );
    canvas.drawCircle(c, radius * 0.28, Paint()..color = Colors.white.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(BoardPainter old) => true; // driven by `repaint` ticks
}


/// The part of the board that never changes between frames: the gold lines with
/// their glow and the hollow rings at the 24 points. It lives in its own
/// RepaintBoundary, so the expensive blurred glow is rasterised once instead of
/// every frame.
class BoardBasePainter extends CustomPainter {
  const BoardBasePainter(this.tk);

  final NawTinTokens tk;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final m = side * 0.09;
    final u = (side - 2 * m) / 6;
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    Offset pos(int p) {
      final g = Board.gridOf(p);
      return Offset(m + g[0] * u, m + g[1] * u);
    }

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.2
      ..strokeCap = StrokeCap.round
      ..color = tk.gold.withValues(alpha: 0.16)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.16);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, u * 0.05)
      ..strokeCap = StrokeCap.round
      ..color = tk.gold;
    for (var l = 0; l < Board.lineCount; l++) {
      final pts = Board.lines[l];
      final path = Path()
        ..moveTo(pos(pts.first).dx, pos(pts.first).dy)
        ..lineTo(pos(pts.last).dx, pos(pts.last).dy);
      canvas.drawPath(path, glow);
      canvas.drawPath(path, core);
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, u * 0.035)
      ..color = tk.gold.withValues(alpha: 0.9);
    for (var p = 0; p < Board.pointCount; p++) {
      canvas.drawCircle(pos(p), u * 0.11, ring);
    }
  }

  @override
  bool shouldRepaint(BoardBasePainter old) => old.tk != tk;
}
