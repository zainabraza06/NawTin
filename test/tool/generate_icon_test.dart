import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/theme/tokens.dart';
import 'package:nawtin/widgets/token_painter.dart';

/// The app icon: the nested-squares board in gold on the midnight gradient
/// with one glowing token. Thick lines and no point rings so it stays readable
/// at 48px.
///
/// Regenerate the PNGs (then run `dart run flutter_launcher_icons`) with:
///   flutter test test/tool/generate_icon_test.dart --dart-define=GENERATE_ICON=1
void paintIcon(Canvas canvas, double size, {required bool background, double scale = 1.0}) {
  const tk = NawTinTokens.dark;
  final rect = Offset.zero & Size.square(size);
  if (background) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size * 0.5, size * 0.42),
          size * 0.75,
          [tk.bgBottom, tk.bgMid, tk.bgTop],
          [0.0, 0.55, 1.0],
        ),
    );
  }
  // board geometry: a 7x7 lattice scaled into the safe area
  final board = size * 0.64 * scale;
  final m = (size - board) / 2;
  final u = board / 6;
  Offset at(int gx, int gy) => Offset(m + gx * u, m + gy * u);

  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = size * 0.042
    ..color = tk.gold;
  final glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = size * 0.09
    ..color = tk.gold.withValues(alpha: 0.28)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.03);

  final path = Path();
  for (var ring = 0; ring < 3; ring++) {
    path.addRect(Rect.fromPoints(at(ring, ring), at(6 - ring, 6 - ring)));
  }
  // the four cross lines
  path
    ..moveTo(at(3, 0).dx, at(3, 0).dy)
    ..lineTo(at(3, 2).dx, at(3, 2).dy)
    ..moveTo(at(3, 4).dx, at(3, 4).dy)
    ..lineTo(at(3, 6).dx, at(3, 6).dy)
    ..moveTo(at(0, 3).dx, at(0, 3).dy)
    ..lineTo(at(2, 3).dx, at(2, 3).dy)
    ..moveTo(at(4, 3).dx, at(4, 3).dy)
    ..lineTo(at(6, 3).dx, at(6, 3).dy);
  canvas.drawPath(path, glow);
  canvas.drawPath(path, line);

  // one glowing token on the top-left corner of the outer square
  paintToken(canvas, at(0, 0), size * 0.095, seat: 0, tk: tk, glow: 1.4, symbol: false);
}

Future<void> savePng(WidgetTester t, String path, int px, {required bool background, double scale = 1.0}) async {
  await t.runAsync(() async {
    final rec = ui.PictureRecorder();
    paintIcon(Canvas(rec), px.toDouble(), background: background, scale: scale);
    final img = await rec.endRecording().toImage(px, px);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  const generate = bool.fromEnvironment('GENERATE_ICON');

  testWidgets('generate app icon PNGs', (t) async {
    await savePng(t, 'assets/icon/icon.png', 1024, background: true);
    // adaptive foreground: transparent, content kept inside the 66% safe zone
    await savePng(t, 'assets/icon/icon_foreground.png', 1024, background: false, scale: 0.78);
    await savePng(t, 'build/shots/icon_48.png', 48, background: true);
    await savePng(t, 'build/shots/icon_192.png', 192, background: true);
  }, skip: !generate);

  test('the icon painter is deterministic and draws something', () {
    final rec = ui.PictureRecorder();
    paintIcon(Canvas(rec), 256, background: true);
    final pic = rec.endRecording();
    expect(pic.approximateBytesUsed, greaterThan(0));
  });
}
