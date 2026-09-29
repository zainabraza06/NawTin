import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nawtin/app_router.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/theme/app_theme.dart';
import 'package:nawtin/widgets/board_view.dart';

Widget app() => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        initialRoute: Routes.splash,
        onGenerateRoute: onGenerateRoute,
      ),
    );

/// Lets a route push build and its transition finish (the app never
/// "settles" because the background loops forever).
Future<void> go(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 700));
  await t.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('splash leads to home; tapping skips the intro', (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(app());
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byType(Scaffold).first);
    await go(t);
    expect(find.text('Play vs AI'), findsOneWidget);
  });

  testWidgets('home -> friend setup -> game, with empty-name validation',
      (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(app());
    await t.pump(const Duration(seconds: 4)); // splash plays out
    await go(t);

    await t.tap(find.text('Play with a Friend'));
    await go(t);
    final container = ProviderScope.containerOf(t.element(find.byType(Navigator).first));
    expect(container.read(setupProvider).mode, GameMode.friend);

    // clearing a name blocks the start and shows the error
    await t.enterText(find.byType(TextField).first, '');
    await t.tap(find.text('Start game'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Give each player a name to start.'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, 'Zainab');
    await t.enterText(find.byType(TextField).last, 'Sam');
    await t.tap(find.text('Start game'));
    await go(t);
    expect(container.read(gameControllerProvider).names, ['Zainab', 'Sam']);
    expect(find.byType(BoardView), findsOneWidget);
  });

  testWidgets('vs AI setup: difficulty and first-move choices update the setup',
      (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(app());
    await t.pump(const Duration(seconds: 4));
    await go(t);
    await t.tap(find.text('Play vs AI'));
    await go(t);
    final container = ProviderScope.containerOf(t.element(find.byType(Navigator).first));

    await t.tap(find.text('Hard'));
    await t.pump(const Duration(milliseconds: 400));
    expect(container.read(setupProvider).difficulty, Difficulty.hard);
    expect(container.read(setupProvider).turnSeconds, 60);

    await t.tap(find.text(GameSetup.aiName));
    await t.pump(const Duration(milliseconds: 400));
    expect(container.read(setupProvider).humanFirst, isFalse);
    expect(container.read(setupProvider).names, [GameSetup.aiName, 'You']);
  });

  testWidgets('How to Play swipes through every lesson without errors',
      (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(app());
    await t.pump(const Duration(seconds: 4));
    await go(t);
    await t.tap(find.text('How to Play'));
    await go(t);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(seconds: 3));
      await t.tap(find.text('Next'));
      await t.pump(const Duration(milliseconds: 800));
    }
    await t.pump(const Duration(seconds: 6)); // let the treghi demo run
    expect(find.text('Got it'), findsOneWidget);
    await t.pumpWidget(const SizedBox()); // dispose timers cleanly
  });
}
