import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../services/haptics.dart';

enum NawButtonStyle { primary, secondary, ghost }

/// Full-width rounded button with a physical press-down scale, light haptics
/// and a 56px minimum height (comfortable thumb target).
class NawButton extends StatefulWidget {
  const NawButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = NawButtonStyle.primary,
    this.caption,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NawButtonStyle style;

  /// Small second line under the label.
  final String? caption;

  @override
  State<NawButton> createState() => _NawButtonState();
}

class _NawButtonState extends State<NawButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final enabled = widget.onPressed != null;
    final primary = widget.style == NawButtonStyle.primary;
    final ghost = widget.style == NawButtonStyle.ghost;
    final fg = primary ? Colors.white : tk.textPrimary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                Haptics.light();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: tk.fast,
          curve: tk.emphasized,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: tk.fast,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tk.radiusL),
                gradient: primary
                    ? LinearGradient(colors: [tk.violet, Color.lerp(tk.violet, tk.coral, 0.45)!])
                    : null,
                color: primary ? null : Colors.white.withValues(alpha: ghost ? 0.0 : 0.08),
                border: Border.all(
                  color: primary
                      ? Colors.white.withValues(alpha: 0.28)
                      : tk.glassBorder.withValues(alpha: ghost ? 0.1 : 0.22),
                ),
                boxShadow: [
                  if (primary && enabled)
                    BoxShadow(color: tk.violet.withValues(alpha: 0.5), blurRadius: 22, offset: const Offset(0, 6)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: fg, size: 22),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tk.heading(NawTinTokens.scaleS, color: fg)),
                        if (widget.caption != null)
                          Text(widget.caption!, style: tk.body(NawTinTokens.scaleXS, color: fg.withValues(alpha: 0.75))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
