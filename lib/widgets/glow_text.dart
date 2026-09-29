import 'package:flutter/material.dart';

/// Text with a gradient fill and a soft glow behind it. Used for the wordmark
/// and the call banners (PHUTAS / MACHYAS / BEGI / TREGHI).
class GlowText extends StatelessWidget {
  const GlowText(
    this.text, {
    super.key,
    required this.style,
    required this.colors,
    this.glow,
    this.glowBlur = 18,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final TextStyle style;
  final List<Color> colors;
  final Color? glow;
  final double glowBlur;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final glowColor = glow ?? colors.first;
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: textAlign,
          style: style.copyWith(
            color: glowColor.withValues(alpha: 0.75),
            shadows: [Shadow(color: glowColor, blurRadius: glowBlur)],
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(colors: colors).createShader(rect),
          child: Text(text, textAlign: textAlign, style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}
