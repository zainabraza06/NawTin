import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nawtin/core/engine/engine.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/game/game_screen.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/theme/app_theme.dart';
import 'package:nawtin/theme/tokens.dart';
import 'package:nawtin/widgets/board_view.dart';

Widget app(GlobalKey shot, {MotionPrefs prefs = const MotionPrefs()}) => ProviderScope(
      child: RepaintBoundary(
        key: shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: GameScreen(prefsOverride: prefs),
        ),
      ),
    );

/// Board point -> global tap position, using the same maths as the painter.
Offset pointOnScreen(WidgetTester t, int p) {
  final box = t.getRect(find.byType(BoardView));
  final side = box.width;
  final m = side * 0.09;
  final u = (side - 2 * m) / 6;
  final g = Board.gridOf(p);
  return box.topLeft + Offset(m + g[0] * u, m + g[1] * u);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('game screen builds and plays through a capture without errors',
      (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final shot = GlobalKey();
    await t.pumpWidget(app(shot));
    await t.pump(const Duration(milliseconds: 500));

    final container = ProviderScope.containerOf(t.element(find.byType(GameScreen)));
    container.read(setupProvider.notifier).setMode(GameMode.friend);
    container.read(gameControllerProvider.notifier).newGame();
    Future<void> play(int p) async {
      container.read(gameControllerProvider.notifier).tapPoint(p);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 3)); // let effects + banners finish
    }

    // seat 1 completes 8-9-10 and eats
    for (final p in [0, 1, 8, 9, 3, 10]) {
      await play(p);
    }
    expect(container.read(gameControllerProvider).status, GameStatus.capturePick);
    await t.pump(const Duration(milliseconds: 300));
    await _save(t, shot, 'capture_pick');
    await play(3);
    expect(container.read(gameControllerProvider).status, GameStatus.awaitingInput);
    expect(container.read(gameControllerProvider).eaten, [0, 1]);
    await _save(t, shot, 'after_capture');
  });

  testWidgets('tapping the board through the gesture layer places a token',
      (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final shot = GlobalKey();
    await t.pumpWidget(app(shot, prefs: const MotionPrefs(reduceMotion: true)));
    await t.pump(const Duration(milliseconds: 600));
    final container = ProviderScope.containerOf(t.element(find.byType(GameScreen)));
    container.read(setupProvider.notifier).setMode(GameMode.friend);
    container.read(gameControllerProvider.notifier).newGame();
    await t.tapAt(pointOnScreen(t, 9));
    await t.pump(const Duration(milliseconds: 200));
    expect(container.read(gameControllerProvider).game.mask0, isNot(0));
    await t.pump(const Duration(seconds: 3));
  });
}

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/shots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}
