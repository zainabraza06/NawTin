import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nawtin/core/ai/ai.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/game/game_screen.dart';
import 'package:nawtin/features/home/home_screen.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/features/setup/mode_setup_screen.dart';
import 'package:nawtin/services/ai_provider.dart';
import 'package:nawtin/theme/app_theme.dart';
import 'package:nawtin/theme/tokens.dart';
import 'package:nawtin/widgets/aurora_background.dart';
import 'package:nawtin/widgets/wordmark.dart';

import 'generate_icon_test.dart' show paintIcon;

/// Builds the Play Store graphics into docs/store/:
///   flutter test test/tool/generate_store_assets_test.dart --dart-define=GENERATE_STORE=true
const _generate = bool.fromEnvironment('GENERATE_STORE');

Future<void> _loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _save(WidgetTester t, GlobalKey key, String name, {double ratio = 1.0}) async {
  await t.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: ratio);
    final d = await img.toByteData(format: ui.ImageByteFormat.png);
    File('docs/store/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(d!.buffer.asUint8List());
  });
}

Widget _app(GlobalKey key, Widget home, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: home,
        ),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('store icon 512', (t) async {
    await t.runAsync(() async {
      final rec = ui.PictureRecorder();
      paintIcon(Canvas(rec), 512, background: true);
      final img = await rec.endRecording().toImage(512, 512);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      File('docs/store/icon_512.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(d!.buffer.asUint8List());
    });
  }, skip: !_generate);

  testWidgets('feature graphic 1024x500', (t) async {
    t.view.physicalSize = const Size(1024, 500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(_app(
      key,
      Scaffold(
        body: AuroraBackground(
          child: Row(
            children: [
              const SizedBox(width: 56),
              Expanded(
                flex: 6,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Wordmark(size: 74),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) => Text(
                        'Make three. Eat one.',
                        style: context.tokens
                            .heading(30, color: context.tokens.textPrimary.withValues(alpha: 0.9))
                            .copyWith(letterSpacing: 2),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) => Text(
                        'Place, slide, and outwit the AI or a friend.',
                        style: context.tokens.body(20),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Center(
                  child: CustomPaint(size: const Size(380, 380), painter: _IconPainter()),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await _settle(t);
    await _save(t, key, 'feature_graphic_1024x500.png');
    await t.pumpWidget(const SizedBox());
  }, skip: !_generate);

  testWidgets('phone screenshots', (t) async {
    await _loadMaterialIcons();
    t.view.physicalSize = const Size(1080, 2160);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    // 1. home
    var key = GlobalKey();
    await t.pumpWidget(_app(key, const HomeScreen()));
    await _settle(t);
    await _save(t, key, 'screenshot_1_home.png');

    // 2. vs AI setup on Hard
    key = GlobalKey();
    await t.pumpWidget(_app(key, const ModeSetupScreen()));
    final c2 = ProviderScope.containerOf(t.element(find.byType(ModeSetupScreen)));
    c2.read(setupProvider.notifier)
      ..setMode(GameMode.vsAi)
      ..setDifficulty(Difficulty.hard);
    await t.pump(const Duration(milliseconds: 200));
    await _settle(t);
    await _save(t, key, 'screenshot_2_setup.png');

    // 3. a game with a capture to make
    key = GlobalKey();
    await t.pumpWidget(_app(key, const GameScreen(prefsOverride: MotionPrefs(reduceMotion: true))));
    final c3 = ProviderScope.containerOf(t.element(find.byType(GameScreen)));
    c3.read(setupProvider.notifier).setMode(GameMode.friend);
    final ctl = c3.read(gameControllerProvider.notifier)..newGame();
    await t.pump();
    for (final p in [0, 1, 8, 3, 9, 20, 10]) {
      ctl.tapPoint(p);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 3));
    }
    await _settle(t);
    await _save(t, key, 'screenshot_3_machyas.png');

    // 4. vs AI with the best move highlighted
    await t.pumpWidget(const SizedBox()); // fresh tree so the new overrides apply
    key = GlobalKey();
    await t.pumpWidget(_app(
      key,
      const GameScreen(prefsOverride: MotionPrefs(reduceMotion: true)),
      overrides: [aiServiceProvider.overrideWithValue(DirectAiService())],
    ));
    final c4 = ProviderScope.containerOf(t.element(find.byType(GameScreen)));
    c4.read(setupProvider.notifier)
      ..setMode(GameMode.vsAi)
      ..setDifficulty(Difficulty.medium)
      ..setHumanFirst(true);
    final ctl4 = c4.read(gameControllerProvider.notifier)..newGame();
    await t.pump();
    Future<void> human(int p) async {
      ctl4.tapPoint(p);
      ctl4.finishAnimation(c4.read(gameControllerProvider).fxSerial);
    }

    await human(9);
    await human(11);
    for (var i = 0; i < 60 && c4.read(gameControllerProvider).status != GameStatus.animating; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 50));
    }
    ctl4.finishAnimation(c4.read(gameControllerProvider).fxSerial);
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() => ctl4.applyBestMoveHint());
    await _settle(t);
    await _save(t, key, 'screenshot_4_hint.png');
    await t.pumpWidget(const SizedBox());
  }, skip: !_generate);
}

class _IconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.22));
    canvas.save();
    canvas.clipRRect(r);
    paintIcon(canvas, size.width, background: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) => false;
}
