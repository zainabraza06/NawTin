import 'dart:math' as math;

import '../core/engine/engine.dart';

/// Timing (in seconds) of everything that happens on the board after one move.
///
///   0 ............ moveEnd      token drops (placement) or glides (slide)
///   moveEnd ...... +flashDur    completed line flashes white-gold with a
///                               light sweep (the "slow-motion" beat)
///   shatterStart . +shatterDur  eaten token breaks into particles
///   waveStart .... +waveDur     begi/treghi energy wave along the lines
final class FxTimeline {
  FxTimeline(this.result) {
    moveEnd = result.move.isPlacement ? 0.5 : 0.42;
    var end = moveEnd + 0.12;
    if (result.isMachyas) {
      flashStart = moveEnd;
      shatterStart = flashStart + 0.5;
      end = shatterStart + shatterDur + 0.1;
    }
    final swing = result.announcedSwing;
    if (swing != null) {
      waveStart = result.isMachyas ? shatterStart : moveEnd;
      waveDur = swing.pattern.kind == PatternKind.treghi ? 1.6 : 1.1;
      end = math.max(end, waveStart + waveDur);
    }
    total = end;
  }

  final MoveResult result;

  late final double moveEnd;
  double flashStart = -1;
  final double flashDur = 0.75;
  double shatterStart = -1;
  final double shatterDur = 0.75;
  double waveStart = -1;
  double waveDur = 0;
  late final double total;

  Duration get duration => Duration(milliseconds: (total * 1000).round());

  bool get hasFlash => flashStart >= 0;
  bool get hasWave => waveStart >= 0;

  /// Time within the animation at which the screen should shake.
  double get impactTime => hasFlash ? shatterStart : moveEnd;
}
