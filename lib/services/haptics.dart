import 'package:flutter/services.dart';

/// Single place for vibration feedback so one setting can switch it all off.
abstract final class Haptics {
  static bool enabled = true;

  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  static void tick() {
    if (enabled) HapticFeedback.selectionClick();
  }
}
