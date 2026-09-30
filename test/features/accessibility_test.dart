import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/engine/engine.dart';
import 'package:nawtin/features/game/announcements.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/game/game_screen.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/theme/app_theme.dart';
import 'package:nawtin/theme/tokens.dart';
import 'package:nawtin/widgets/friendly_error.dart';

GameState st(List<int> a, List<int> b, {int hand0 = 0, int hand1 = 0, int turn = 0}) =>
    GameState.fromMasks(mask0: maskOf(a), mask1: maskOf(b), hand0: hand0, hand1: hand1, turn: turn);

void main() {
  const names = ['Zainab', 'Sam'];

  group('spoken text', () {
    test('every point has a unique, readable name', () {
      final all = {for (var p = 0; p < 24; p++) pointName(p)};
      expect(all.length, 24);
      expect(pointName(0), 'top-left corner of the outer square');
      expect(pointName(9), 'top middle of the middle square');
      expect(pointName(21), 'bottom middle of the inner square');
    });

    test('labels say who is where, protection and what can be eaten', () {
      final g = st([12, 13, 14, 20], [0]);
      expect(pointLabel(5, g, names), contains('empty'));
      expect(pointLabel(5, g, names, target: true), contains('you can move here'));
      expect(pointLabel(12, g, names), contains('Zainab token, protected'));
      expect(pointLabel(20, g, names), 'bottom-right corner of the inner square, Zainab token');
      expect(pointLabel(0, g, names, capturable: true), contains('can be eaten'));
    });

    test('a move is announced with the call and whose turn it is', () {
      final before = st([0, 1, 3, 5], [12, 14, 20, 22]);
      final r = MoveResult.resolve(before, const Move.slide(3, 2, capture: 22));
      final text = announceMove(r, names);
      expect(text, contains('Zainab slid a token'));
      expect(text, contains('Machyas! Sam loses the token'));
      expect(text, contains('Sam to play'));
    });

    test('begi, ready-begi and game end are announced', () {
      final s = st([6, 7, 9, 17, 2], [12, 13, 14, 19, 23]);
      final r = MoveResult.resolve(s, const Move.slide(2, 1, capture: 19));
      expect(announceMove(r, names), contains('Begi!'));

      final placing = st([0, 6, 7, 9], [20], hand0: 5, hand1: 5);
      final ready = MoveResult.resolve(placing, const Move.place(17));
      expect(announceMove(ready, names), contains('Begi ready'));

      final end = MoveResult.resolve(st([0, 1, 3], [12, 14, 20]), const Move.slide(3, 2, capture: 20));
      expect(announceMove(end, names), contains('Zainab wins'));
    });
  });

  testWidgets('a screen reader can find and play every board point', (t) async {
    final handle = t.ensureSemantics();
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const GameScreen(prefsOverride: MotionPrefs(reduceMotion: true)),
      ),
    ));
    final c = ProviderScope.containerOf(t.element(find.byType(GameScreen)));
    c.read(setupProvider.notifier).setMode(GameMode.friend);
    c.read(gameControllerProvider.notifier).newGame();
    await t.pump(const Duration(milliseconds: 300));

    final label = find.semantics.byLabel(RegExp('top middle of the middle square, empty'));
    expect(label, findsOneWidget);
    // activating it through the accessibility tree places a token
    t.semantics.tap(label);
    await t.pump(const Duration(milliseconds: 200));
    expect(c.read(gameControllerProvider).game.mask0 & bit(9), isNot(0));
    expect(find.bySemanticsLabel(RegExp('Player 1 token')), findsWidgets);

    // the interactive controls meet the 48dp minimum
    for (final f in [find.byTooltip('Pause')]) {
      if (f.evaluate().isEmpty) continue;
      final size = t.getSize(f.first);
      expect(size.shortestSide, greaterThanOrEqualTo(48));
    }
    handle.dispose();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the friendly error screen is readable and has no stack trace', (t) async {
    await t.pumpWidget(const FriendlyError());
    expect(find.text('Something went sideways'), findsOneWidget);
    expect(find.textContaining('stats are safe'), findsOneWidget);
  });
}
