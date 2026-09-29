import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Segmented selector whose thumb slides between options.
class SlidingSegments extends StatelessWidget {
  const SlidingSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.thumbColor,
    this.height = 52,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final Color? thumbColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final color = thumbColor ?? tk.violet;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth / labels.length;
        return Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tk.radiusM),
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: tk.glassBorder.withValues(alpha: 0.14)),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: tk.medium,
                curve: tk.overshoot,
                left: w * selected,
                top: 4,
                bottom: 4,
                width: w,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(tk.radiusM - 4),
                      gradient: LinearGradient(colors: [color, Color.lerp(color, tk.coral, 0.35)!]),
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 14)],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == selected,
                        label: labels[i],
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (i != selected) HapticFeedback.selectionClick();
                            onChanged(i);
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: tk.fast,
                              style: tk.heading(
                                NawTinTokens.scaleS,
                                color: i == selected ? Colors.white : tk.textMuted,
                                weight: FontWeight.w600,
                              ),
                              child: Text(labels[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
