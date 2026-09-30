import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Glassmorphism surface: frosted blur, 1px inner border at 12% white and a
/// soft shadow. [glow] adds a coloured halo (used for the active player).
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius,
    this.glow,
    this.blur = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final Color? glow;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final r = BorderRadius.circular(radius ?? tk.radiusL);
    // Low-power mode skips the frosted blur (the costliest effect on old GPUs)
    // and uses a slightly denser tint so the panel still reads as glass.
    final lowPower = MotionScope.of(context).lowPower;
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        color: tk.glassFill.withValues(alpha: lowPower ? 0.16 : 0.08),
        border: Border.all(
          color: glow?.withValues(alpha: 0.55) ?? tk.glassBorder.withValues(alpha: 0.12),
        ),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          if (glow != null)
            BoxShadow(color: glow!.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: lowPower
            ? decorated
            : BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: decorated),
      ),
    );
  }
}
