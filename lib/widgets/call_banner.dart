import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/engine/engine.dart';
import '../theme/tokens.dart';
import 'glow_text.dart';

/// One announcement to show: a call plus its copy.
@immutable
class BannerItem {
  const BannerItem(this.call, this.label, this.subtitle, {this.ready = false});
  final Call call;
  final String label;
  final String subtitle;

  /// Begi/treghi formed during placement ("ready", cannot swing yet).
  final bool ready;
}

/// The banners a played move triggers, in order (Machyas first, then the
/// begi/treghi it created). PHUTAS is separate: the player presses it.
List<BannerItem> bannersFor(MoveResult r) {
  final items = <BannerItem>[];
  if (r.isMachyas) {
    items.add(const BannerItem(Call.machyas, 'MACHYAS!', 'Line made. Eat one.'));
  }
  final swing = r.announcedSwing;
  if (swing != null) {
    final t = swing.call == Call.treghi;
    if (swing.readyOnly) {
      items.add(BannerItem(
        swing.call,
        t ? 'TREGHI READY' : 'BEGI READY',
        'It can swing once movement starts.',
        ready: true,
      ));
    } else {
      items.add(BannerItem(
        swing.call,
        t ? 'TREGHI!' : 'BEGI!',
        t ? 'Triple mill. Swing through all three.' : 'Double mill. Swing and eat again.',
      ));
    }
  }
  return items;
}

const BannerItem phutasBanner =
    BannerItem(Call.phutas, 'PHUTAS!', 'A line is one move from done.');

/// Plays a list of [BannerItem]s one after another. Restarts whenever
/// [serial] changes. Never intercepts touches.
class CallBannerOverlay extends StatefulWidget {
  const CallBannerOverlay({super.key, required this.items, required this.serial});

  final List<BannerItem> items;
  final int serial;

  @override
  State<CallBannerOverlay> createState() => _CallBannerOverlayState();
}

class _CallBannerOverlayState extends State<CallBannerOverlay>
    with SingleTickerProviderStateMixin {
  static const double _each = 1.5; // seconds a banner stays
  static const double _gap = 1.0; // seconds between banner starts

  late final AnimationController _c = AnimationController(vsync: this);
  List<BannerItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _items = const []);
    });
  }

  @override
  void didUpdateWidget(CallBannerOverlay old) {
    super.didUpdateWidget(old);
    if (widget.serial != old.serial && widget.items.isNotEmpty) {
      _items = widget.items;
      final total = _gap * (_items.length - 1) + _each;
      _c.duration = Duration(milliseconds: (total * 1000).round());
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final elapsed = _c.value * (_c.duration!.inMilliseconds / 1000);
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < _items.length; i++)
                _Banner(item: _items[i], t: ((elapsed - i * _gap) / _each)),
            ],
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.item, required this.t});
  final BannerItem item;

  /// 0..1 across the banner's lifetime (outside that range it is hidden).
  final double t;

  @override
  Widget build(BuildContext context) {
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final tk = context.tokens;
    final call = item.call;
    final big = call == Call.treghi;

    final colors = switch (call) {
      Call.phutas => [tk.lime, tk.goldGlow],
      Call.machyas => [tk.goldGlow, tk.gold, tk.coral],
      Call.begi => [tk.aqua, tk.violet, tk.coral],
      Call.treghi => [tk.goldGlow, tk.coral, tk.violet, tk.aqua],
    };
    final glow = switch (call) {
      Call.phutas => tk.lime,
      Call.machyas => tk.gold,
      Call.begi => tk.violet,
      Call.treghi => tk.coral,
    };

    final inT = (t / 0.25).clamp(0.0, 1.0);
    final outT = ((t - 0.8) / 0.2).clamp(0.0, 1.0);
    final fade = 1 - outT;
    final slide = call == Call.phutas;
    final scale = slide ? 1.0 : (0.3 + 0.7 * tk.spring.transform(inT));
    final dx = slide ? (1 - Curves.easeOutCubic.transform(inT)) * -1.2 : 0.0;

    final fullWidth = call == Call.begi || call == Call.treghi;
    final size = big ? 52.0 : (fullWidth ? 44.0 : NawTinTokens.scaleXL);

    return Center(
      child: FractionalTranslation(
        translation: Offset(dx, 0),
        child: Opacity(
          opacity: (fade * inT.clamp(0.0, 1.0)).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (fullWidth) _EnergyBand(color: glow, t: t, strong: big),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: GlowText(
                          item.label,
                          style: tk.display(size),
                          colors: colors,
                          glow: glow,
                          glowBlur: big ? 30 : 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.subtitle,
                        textAlign: TextAlign.center,
                        style: tk.body(NawTinTokens.scaleXS, color: tk.textPrimary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width glowing strip with light running along it (BEGI / TREGHI).
class _EnergyBand extends StatelessWidget {
  const _EnergyBand({required this.color, required this.t, required this.strong});
  final Color color;
  final double t;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      height: strong ? 150 : 120,
      child: CustomPaint(painter: _BandPainter(color, t, strong)),
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.color, this.t, this.strong);
  final Color color;
  final double t;
  final bool strong;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: strong ? 0.5 : 0.35),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    final y = size.height / 2;
    for (var i = 0; i < (strong ? 3 : 2); i++) {
      final x = ((t * 2.5 + i / 3) % 1.0) * size.width;
      canvas.drawCircle(
        Offset(x, y + math.sin(t * 10 + i) * 3),
        22,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.t != t;
}
