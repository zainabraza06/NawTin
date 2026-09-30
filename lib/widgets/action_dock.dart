import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// The bottom dock: Hint (left), PHUTAS (centre) and Rewind (right).
/// In two-player mode Hint and Rewind are hidden and PHUTAS stays centred.
class ActionDock extends StatelessWidget {
  const ActionDock({
    super.key,
    required this.phutasReady,
    required this.onPhutas,
    this.showAssist = false,
    this.hintBadge = '1-2 ads',
    this.rewindBadge = '3 ads',
    this.onHint,
    this.onRewind,
  });

  final bool phutasReady;
  final VoidCallback onPhutas;

  /// Whether Hint / Rewind are shown (vs-AI only).
  final bool showAssist;
  final String hintBadge;
  final String rewindBadge;
  final VoidCallback? onHint;
  final VoidCallback? onRewind;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final phutas = DockPill(
      label: 'PHUTAS',
      icon: Icons.bolt_rounded,
      enabled: phutasReady,
      primary: true,
      onTap: onPhutas,
      semanticsLabel: phutasReady
          ? 'Phutas: warn that you threaten a line'
          : 'Phutas unavailable',
    );
    if (!showAssist) {
      return Center(child: SizedBox(width: 220, child: phutas));
    }
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DockPill(
            label: 'Hint',
            icon: Icons.lightbulb_outline_rounded,
            badge: hintBadge,
            enabled: onHint != null,
            onTap: onHint ?? () {},
          ),
        ),
        SizedBox(width: tk.space1),
        Expanded(flex: 4, child: phutas),
        SizedBox(width: tk.space1),
        Expanded(
          flex: 3,
          child: DockPill(
            label: 'Rewind',
            icon: Icons.replay_rounded,
            badge: rewindBadge,
            enabled: onRewind != null,
            onTap: onRewind ?? () {},
          ),
        ),
      ],
    );
  }
}

/// Rounded pill button with a physical press-down scale and light haptics.
class DockPill extends StatefulWidget {
  const DockPill({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
    this.enabled = true,
    this.primary = false,
    this.semanticsLabel,
  });

  final String label;
  final IconData icon;
  final String? badge;
  final bool enabled;
  final bool primary;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  State<DockPill> createState() => _DockPillState();
}

class _DockPillState extends State<DockPill> with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _syncGlow();
  }

  @override
  void didUpdateWidget(DockPill old) {
    super.didUpdateWidget(old);
    _syncGlow();
  }

  void _syncGlow() {
    if (widget.enabled && widget.primary) {
      if (!_glow.isAnimating) _glow.repeat(reverse: true);
    } else {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final on = widget.enabled;
    final base = widget.primary ? tk.lime : tk.violet;
    final fg = widget.primary ? tk.ink : tk.textPrimary;
    return Semantics(
      button: true,
      enabled: on,
      label: widget.semanticsLabel ?? widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapCancel: on ? () => setState(() => _down = false) : null,
        onTapUp: on
            ? (_) {
                setState(() => _down = false);
                HapticFeedback.lightImpact();
                widget.onTap();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: tk.fast,
          curve: tk.emphasized,
          child: AnimatedBuilder(
            animation: _glow,
            builder: (context, child) => Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tk.radiusL),
                gradient: on
                    ? LinearGradient(
                        colors: widget.primary
                            ? [tk.lime, Color.lerp(tk.lime, tk.aqua, 0.35)!]
                            : [base.withValues(alpha: 0.55), base.withValues(alpha: 0.3)],
                      )
                    : null,
                color: on ? null : Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: on ? Colors.white.withValues(alpha: 0.25) : tk.glassBorder.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  if (on && widget.primary)
                    BoxShadow(
                      color: tk.lime.withValues(alpha: 0.35 + 0.3 * _glow.value),
                      blurRadius: 16 + 14 * _glow.value,
                    ),
                ],
              ),
              child: child,
            ),
            child: widget.primary ? _row(tk, on, fg) : _stack(tk, on, fg),
          ),
        ),
      ),
    );
  }

  Widget _row(NawTinTokens tk, bool on, Color fg) {
    final dim = tk.textMuted.withValues(alpha: 0.5);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(widget.icon, size: 22, color: on ? fg : dim),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tk.heading(NawTinTokens.scaleS, color: on ? fg : dim),
          ),
        ),
      ],
    );
  }

  /// Narrow assist pills stack icon, label and ad cost so nothing is squeezed.
  Widget _stack(NawTinTokens tk, bool on, Color fg) {
    final dim = tk.textMuted.withValues(alpha: 0.5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(widget.icon, size: 20, color: on ? fg : dim),
        const SizedBox(height: 2),
        Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tk.heading(NawTinTokens.scaleXS + 1, color: on ? fg : dim),
        ),
        if (widget.badge != null)
          Text(
            widget.badge!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tk.body(NawTinTokens.scaleXS - 2, color: on ? tk.lime : dim),
          ),
      ],
    );
  }
}
