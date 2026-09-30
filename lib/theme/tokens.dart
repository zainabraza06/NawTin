import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the "Midnight Neon Arcade" look. Widgets never hard-code
/// colours, radii, spacing, durations or curves: they read them from here via
/// `context.tokens`.
@immutable
class NawTinTokens extends ThemeExtension<NawTinTokens> {
  const NawTinTokens({
    required this.bgTop,
    required this.bgMid,
    required this.bgBottom,
    required this.gold,
    required this.goldGlow,
    required this.coral,
    required this.aqua,
    required this.violet,
    required this.lime,
    required this.amber,
    required this.danger,
    required this.glassFill,
    required this.glassBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.ink,
    this.radiusS = 12,
    this.radiusM = 20,
    this.radiusL = 24,
    this.space1 = 8,
    this.space2 = 16,
    this.space3 = 24,
    this.space4 = 32,
    this.fast = const Duration(milliseconds: 160),
    this.medium = const Duration(milliseconds: 320),
    this.slow = const Duration(milliseconds: 640),
    this.standard = Curves.easeOutCubic,
    this.spring = Curves.elasticOut,
    this.emphasized = const Cubic(0.22, 1.0, 0.36, 1.0),
    this.overshoot = const Cubic(0.22, 1.0, 0.36, 1.18),
  });

  /// The one and only theme: dark, glowing, high contrast.
  static const dark = NawTinTokens(
    bgTop: Color(0xFF070B1F),
    bgMid: Color(0xFF141A3F),
    bgBottom: Color(0xFF1E1650),
    gold: Color(0xFFF5C451),
    goldGlow: Color(0xFFFFE9A8),
    coral: Color(0xFFFF4D6D),
    aqua: Color(0xFF2EE6D6),
    violet: Color(0xFF8B5CF6),
    lime: Color(0xFFB6FF3B),
    amber: Color(0xFFFFB020),
    danger: Color(0xFFFF3B4E),
    glassFill: Color(0x1FFFFFFF),
    glassBorder: Color(0x1FFFFFFF),
    textPrimary: Color(0xFFF4F6FF),
    textMuted: Color(0xFFA8B0D6),
    ink: Color(0xFF0B0F26),
  );

  // Colours
  final Color bgTop, bgMid, bgBottom;
  final Color gold, goldGlow;
  final Color coral, aqua;
  final Color violet, lime, amber, danger;
  final Color glassFill, glassBorder;
  final Color textPrimary, textMuted;

  /// Dark ink used for symbols drawn on top of bright tokens.
  final Color ink;

  // Radii (20-24 for surfaces, 12 for small chips)
  final double radiusS, radiusM, radiusL;

  // 8pt spacing grid
  final double space1, space2, space3, space4;

  // Motion
  final Duration fast, medium, slow;
  final Curve standard, spring, emphasized, overshoot;

  /// Player 1 = ruby-coral (circle), Player 2 / AI = electric aqua (diamond).
  Color seatColor(int seat) => seat == 0 ? coral : aqua;

  // Typography. Scale: 40 / 28 / 20 / 16 / 13, with one strong jump between
  // call banners (display) and everything else.

  /// Bungee: wordmark and call banners. Uppercase, wide tracking.
  TextStyle display(double size, {Color? color}) => GoogleFonts.bungee(
        fontSize: size,
        letterSpacing: size * 0.06,
        color: color ?? textPrimary,
        height: 1.05,
      );

  /// Sora 600-700: headings and buttons.
  TextStyle heading(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.sora(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w700,
        color: color ?? textPrimary,
        height: 1.15,
      );

  /// Inter 400-500: body and labels.
  TextStyle body(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w500,
        color: color ?? textMuted,
        height: 1.3,
      );

  /// Space Grotesk with tabular figures: timer digits and counts.
  TextStyle digits(double size, {Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static const double scaleXL = 40;
  static const double scaleL = 28;
  static const double scaleM = 20;
  static const double scaleS = 16;
  static const double scaleXS = 13;

  @override
  NawTinTokens copyWith() => this; // single theme, nothing to override

  @override
  NawTinTokens lerp(ThemeExtension<NawTinTokens>? other, double t) => this;
}

extension NawTinTokensContext on BuildContext {
  NawTinTokens get tokens => Theme.of(this).extension<NawTinTokens>()!;
}

/// Global switches that trim effects (Stage 7 exposes them in settings).
@immutable
class MotionPrefs {
  const MotionPrefs({this.lowPower = false, this.reduceMotion = false});
  final bool lowPower;
  final bool reduceMotion;
}

/// Makes the motion / power preferences available to any widget below the
/// app root, without threading them through constructors.
class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.prefs, required super.child});

  final MotionPrefs prefs;

  /// Defaults to full effects when there is no scope (for example in tests).
  static MotionPrefs of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.prefs ?? const MotionPrefs();

  @override
  bool updateShouldNotify(MotionScope old) =>
      old.prefs.lowPower != prefs.lowPower || old.prefs.reduceMotion != prefs.reduceMotion;
}
