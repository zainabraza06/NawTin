import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nawtin/core/ai/ai.dart';
import 'package:nawtin/core/engine/engine.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/game/game_screen.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/services/ai_provider.dart';
import 'package:nawtin/services/turn_clock.dart';
import 'package:nawtin/theme/app_theme.dart';
import 'package:nawtin/theme/tokens.dart';

ProviderContainer make({GameMode mode = GameMode.friend, Difficulty d = Difficulty.easy, bool humanFirst = true}) {
  final c = ProviderContainer(overrides: [
    aiServiceProvider.overrideWithValue(DirectAiService()),
  ]);
  addTearDown(c.dispose);
  c.read(setupProvider.notifier)
    ..setMode(mode)
    ..setDifficulty(d)
    ..setHumanFirst(humanFirst);
  c.read(gameControllerProvider.notifier).newGame();
  return c;
}

GameController ctl(ProviderContainer c) => c.read(gameControllerProvider.notifier);
GameUiState ui(ProviderContainer c) => c.read(gameControllerProvider);
ClockState clock(ProviderContainer c) => c.read(clockProvider);

void tap(ProviderContainer c, int p) {
  ctl(c).tapPoint(p);
  if (ui(c).status == GameStatus.animating) ctl(c).finishAnimation(ui(c).fxSerial);
}

Future<void> settle(ProviderContainer c) async {
  // auto-play waits ~450ms before committing its move
  await Future<void>.delayed(const Duration(milliseconds: 700));
}

void main() {
  group('ClockController', () {
    test('drains only while running and expires exactly once', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final k = c.read(clockProvider.notifier);
      var expired = 0;
      k.onExpired = () => expired++;
      k.reset(10000);
      k.advance(4000); // not running: nothing happens
      expect(c.read(clockProvider).remainingMs, 10000);
      k.setRunning(true);
      k.advance(4000);
      expect(c.read(clockProvider).remainingMs, 6000);
      expect(c.read(clockProvider).secondsLeft, 6);
      k.advance(6000);
      expect(expired, 1);
      expect(c.read(clockProvider).running, isFalse);
      k.advance(1000);
      expect(expired, 1);
    });

    test('warning and urgent thresholds, and refill restores the full time', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final k = c.read(clockProvider.notifier);
      k.reset(90000);
      k.setRunning(true);
      k.advance(61000); // 29s left
      expect(c.read(clockProvider).warning, isTrue);
      expect(c.read(clockProvider).urgent, isFalse);
      k.advance(20000);
      expect(c.read(clockProvider).secondsLeft, 9);
      expect(c.read(clockProvider).urgent, isTrue);
      k.refill();
      expect(c.read(clockProvider).remainingMs, 90000);
    });
  });

  group('turn clock in the game', () {
    test('runs on a human turn, stops during animation, refills each action', () {
      final c = make();
      expect(clock(c).running, isTrue);
      expect(clock(c).totalMs, 120000);
      c.read(clockProvider.notifier).advance(30000);
      expect(clock(c).remainingMs, 90000);
      ctl(c).tapPoint(0);
      expect(ui(c).status, GameStatus.animating);
      expect(clock(c).running, isFalse);
      ctl(c).finishAnimation(ui(c).fxSerial);
      expect(clock(c).running, isTrue);
      expect(clock(c).remainingMs, 120000);
    });

    test('per-level clocks: Hard 1:00, Medium 1:30, two-player 2:00', () {
      expect(clock(make(mode: GameMode.vsAi, d: Difficulty.hard)).totalMs, 60000);
      expect(clock(make(mode: GameMode.vsAi, d: Difficulty.medium)).totalMs, 90000);
      expect(clock(make(mode: GameMode.vsAi, d: Difficulty.easy)).totalMs, 120000);
      expect(clock(make()).totalMs, 120000);
    });

    test('does not run while the AI is thinking', () async {
      final c = make(mode: GameMode.vsAi);
      tap(c, 0);
      tap(c, 4);
      expect(ui(c).status, GameStatus.aiThinking);
      expect(clock(c).running, isFalse);
      await settle(c);
    });

    test('backgrounding pauses the clock vs the AI but not in two-player', () {
      final ai = make(mode: GameMode.vsAi);
      expect(clock(ai).running, isTrue);
      ctl(ai).setBackgrounded(true);
      expect(clock(ai).running, isFalse);
      ctl(ai).setBackgrounded(false);
      expect(clock(ai).running, isTrue);

      final friend = make();
      ctl(friend).setBackgrounded(true);
      expect(clock(friend).running, isTrue);
    });

    test('an ad holds the clock, rewind can refill it', () {
      final c = make();
      c.read(clockProvider.notifier).advance(40000);
      ctl(c).setAdHold(true);
      expect(clock(c).running, isFalse);
      ctl(c).setAdHold(false);
      expect(clock(c).running, isTrue);
      ctl(c).refillClock();
      expect(clock(c).remainingMs, 120000);
    });
  });

  group('timeouts', () {
    test('first timeout plays a move for the player, second disqualifies', () async {
      final c = make();
      c.read(clockProvider.notifier).advance(120000);
      expect(ui(c).status, GameStatus.autoPlaying);
      expect(ui(c).timeouts, [1, 0]);
      expect(ui(c).timeoutDisqualified, isFalse);
      await settle(c);
      expect(ui(c).status, GameStatus.animating);
      expect(popCount(ui(c).game.mask0), 1, reason: 'a legal move was auto-played');
      ctl(c).finishAnimation(ui(c).fxSerial);

      // still seat 0's opening turn; the clock is running again with full time
      expect(clock(c).running, isTrue);
      c.read(clockProvider.notifier).advance(120000);
      expect(ui(c).status, GameStatus.gameOver);
      expect(ui(c).game.result!.winner, 1);
      expect(ui(c).game.result!.reason, GameEndReason.disqualified);
      expect(ui(c).timeoutDisqualified, isTrue);
    });

    test('timeouts are counted per player', () async {
      final c = make();
      tap(c, 0);
      tap(c, 4);
      // seat 1 times out once, then plays normally, seat 0 times out once
      c.read(clockProvider.notifier).advance(120000);
      await settle(c);
      ctl(c).finishAnimation(ui(c).fxSerial);
      expect(ui(c).timeouts, [0, 1]);
      c.read(clockProvider.notifier).advance(120000);
      await settle(c);
      ctl(c).finishAnimation(ui(c).fxSerial);
      expect(ui(c).timeouts, [1, 1]);
      expect(ui(c).isOver, isFalse);
    });

    test('a timeout while choosing a capture eats a token on the same step', () async {
      final c = make();
      for (final p in [0, 1, 8, 3, 9, 20]) {
        tap(c, p);
      }
      ctl(c).tapPoint(10); // completes 8-9-10, now choosing what to eat
      expect(ui(c).status, GameStatus.capturePick);
      c.read(clockProvider.notifier).advance(120000);
      await settle(c);
      final s = ui(c);
      expect(s.game.mask1 & bit(10), isNot(0), reason: 'the chosen step stands');
      expect(popCount(s.game.mask0), 3, reason: 'one token was eaten');
      expect(s.eaten, [0, 1]);
    });

    test('a timeout is never a Hard-quality move: it uses the Easy config', () async {
      final seen = <String>[];
      final c = ProviderContainer(overrides: [
        aiServiceProvider.overrideWithValue(_Spy(seen)),
      ]);
      addTearDown(c.dispose);
      c.read(setupProvider.notifier)
        ..setMode(GameMode.vsAi)
        ..setDifficulty(Difficulty.hard);
      ctl(c).newGame();
      c.read(clockProvider.notifier).advance(60000);
      await settle(c);
      expect(seen, ['Easy']);
    });
  });

  group('pause', () {
    test('at most two pauses per game; the clock stops and input is ignored', () {
      final c = make();
      expect(ctl(c).pause(), isTrue);
      expect(ui(c).paused, isTrue);
      expect(clock(c).running, isFalse);
      ctl(c).tapPoint(0);
      expect(ui(c).game.mask0, 0, reason: 'board input is blocked while paused');
      ctl(c).resume();
      expect(clock(c).running, isTrue);

      expect(ctl(c).pause(), isTrue);
      ctl(c).resume();
      expect(ctl(c).pause(), isFalse, reason: 'third pause is refused');
      expect(ui(c).pausesUsed, 2);
    });

    test('cannot pause during an animation or after the game ends', () {
      final c = make();
      ctl(c).tapPoint(0);
      expect(ctl(c).pause(), isFalse);
      ctl(c).finishAnimation(ui(c).fxSerial);
      expect(ctl(c).pause(), isTrue);
    });

    test('a new game resets the pause allowance', () {
      final c = make();
      ctl(c).pause();
      ctl(c).resume();
      ctl(c).newGame();
      expect(ui(c).pausesUsed, 0);
    });
  });

  testWidgets('the ring counts down on screen and pause freezes it', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const GameScreen(prefsOverride: MotionPrefs(reduceMotion: true)),
      ),
    ));
    final container = ProviderScope.containerOf(t.element(find.byType(GameScreen)));
    container.read(setupProvider.notifier).setMode(GameMode.friend);
    container.read(gameControllerProvider.notifier).newGame();
    await t.pump();
    expect(find.text('2:00'), findsWidgets);

    await t.pump(const Duration(seconds: 5));
    expect(find.text('1:55'), findsOneWidget);

    expect(container.read(gameControllerProvider.notifier).pause(), isTrue);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Paused'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    expect(container.read(clockProvider).secondsLeft, 115);
    container.read(gameControllerProvider.notifier).resume();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Paused'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}

class _Spy extends AiService {
  _Spy(this.seen);
  final List<String> seen;

  @override
  Future<SearchResult> search(GameState state, AiConfig config, {Move? onlyStep}) async {
    seen.add(config.name);
    return Searcher(config.withTime(100)).search(state, onlyStep: onlyStep);
  }
}
