import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/engine/engine.dart';
import 'package:nawtin/theme/tokens.dart';
import 'package:nawtin/widgets/board_fx.dart';
import 'package:nawtin/widgets/board_painter.dart';
import 'package:nawtin/widgets/token_painter.dart';

/// Records [frames] frames through a PictureRecorder and returns the mean
/// milliseconds per frame. This measures the Dart/painter cost of building the
/// display list (not raster time), which is what most of our per-frame
/// allocations and Paint/MaskFilter setup show up in.
double msPerFrame(void Function(Canvas canvas, int frame) paint, {int frames = 240}) {
  // warm up
  for (var i = 0; i < 30; i++) {
    final r = ui.PictureRecorder();
    paint(Canvas(r), i);
    r.endRecording().dispose();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < frames; i++) {
    final r = ui.PictureRecorder();
    paint(Canvas(r), i);
    r.endRecording().dispose();
  }
  return sw.elapsedMicroseconds / 1000 / frames;
}

void main() {
  const tk = NawTinTokens.dark;

  test('board frame cost with a full board and a capture animation', () {
    // a busy position: 9 tokens each, a capture in flight
    final s = GameState.fromMasks(
      mask0: maskOf([0, 2, 4, 6, 9, 11, 13, 15, 17]),
      mask1: maskOf([1, 3, 5, 7, 8, 10, 12, 14, 21]),
    );
    final result = MoveResult.resolve(
      GameState.fromMasks(mask0: maskOf([0, 1, 3, 5]), mask1: maskOf([12, 14, 20, 22])),
      const Move.slide(3, 2, capture: 22),
    );
    final tl = FxTimeline(result);

    final ms = msPerFrame((canvas, i) {
      BoardPainter(
        tk: tk,
        mask0: s.mask0,
        mask1: s.mask1,
        selected: 9,
        targets: maskOf([8, 10]),
        captureMask: 0,
        pickerSeat: 0,
        pulse: (i % 60) / 60,
        fx: tl,
        fxSeconds: (i % 100) / 100 * tl.total,
        phutasLines: 1,
        phutasT: 0.5,
        prefs: const MotionPrefs(),
      ).paint(canvas, const Size(340, 340));
    });
    // ignore: avoid_print
    print('BENCH board   : ${ms.toStringAsFixed(3)} ms/frame');
    expect(ms, lessThan(8), reason: 'must fit comfortably in a 16.6ms frame');
  });

  test('token draw cost (18 tokens)', () {
    final ms = msPerFrame((canvas, i) {
      for (var k = 0; k < 18; k++) {
        paintToken(canvas, Offset(20.0 * k, 50), 14, seat: k % 2, tk: tk);
      }
    });
    // ignore: avoid_print
    print('BENCH tokens  : ${ms.toStringAsFixed(3)} ms/frame');
    expect(ms, lessThan(4));
  });
}
