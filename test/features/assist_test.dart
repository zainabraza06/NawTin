import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nawtin/core/ai/ai.dart';
import 'package:nawtin/core/engine/engine.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/game/game_screen.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/services/ads/ads_provider.dart';
import 'package:nawtin/services/ads/ads_service.dart';
import 'package:nawtin/services/ads/mock_ads_service.dart';
import 'package:nawtin/services/ai_provider.dart';
import 'package:nawtin/services/turn_clock.dart';
import 'package:nawtin/theme/app_theme.dart';
import 'package:nawtin/theme/tokens.dart';

/// Plays a fixed list of moves for the AI seat; the Hard config (used by
/// Hint 2) is delegated to the real search.
class ScriptedAi extends AiService {
  ScriptedAi(this.moves);
  final List<Move> moves;

  @override
  Future<SearchResult> search(GameState state, AiConfig config, {Move? onlyStep}) async {
    if (config.name == 'Hard') {
      return Searcher(config).search(state, onlyStep: onlyStep);
    }
    return SearchResult(moves.removeAt(0), 0, 1, 1);
  }
}

ProviderContainer makeScripted(List<Move> aiMoves) {
  final c = ProviderContainer(overrides: [
    aiServiceProvider.overrideWithValue(ScriptedAi(aiMoves)),
    adsServiceProvider.overrideWithValue(fastAds()),
  ]);
  addTearDown(c.dispose);
  c.read(setupProvider.notifier)
    ..setMode(GameMode.vsAi)
    ..setDifficulty(Difficulty.easy)
    ..setHumanFirst(true);
  c.read(gameControllerProvider.notifier).newGame();
  return c;
}

MockAdsService fastAds({double fill = 1}) => MockAdsService(
      adDuration: const Duration(milliseconds: 20),
      loadDuration: const Duration(milliseconds: 5),
      waitForLoad: const Duration(milliseconds: 200),
      fillRate: fill,
    );

ProviderContainer make({GameMode mode = GameMode.vsAi, bool humanFirst = true, MockAdsService? ads}) {
  final c = ProviderContainer(overrides: [
    aiServiceProvider.overrideWithValue(DirectAiService()),
    adsServiceProvider.overrideWithValue(ads ?? fastAds()),
  ]);
  addTearDown(c.dispose);
  c.read(setupProvider.notifier)
    ..setMode(mode)
    ..setDifficulty(Difficulty.easy)
    ..setHumanFirst(humanFirst);
  c.read(gameControllerProvider.notifier).newGame();
  return c;
}

GameController ctl(ProviderContainer c) => c.read(gameControllerProvider.notifier);
GameUiState ui(ProviderContainer c) => c.read(gameControllerProvider);

void human(ProviderContainer c, int p) {
  ctl(c).tapPoint(p);
  ctl(c).finishAnimation(ui(c).fxSerial);
}

/// Lets the AI play its whole turn (two tokens on its opening turn) and
/// returns when it is the human's move again.
Future<void> aiReplies(ProviderContainer c) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final s = ui(c);
    if (s.status == GameStatus.animating) {
      ctl(c).finishAnimation(s.fxSerial);
    } else if (s.status == GameStatus.awaitingInput) {
      return;
    }
  }
  fail('AI never replied');
}

/// A sheet needs one frame to be built and a few more to slide in.
Future<void> sheet(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  group('availability', () {
    test('hints and rewind are off in two-player mode', () {
      final c = make(mode: GameMode.friend);
      expect(ctl(c).canAssist, isFalse);
      expect(ctl(c).canRewind, isFalse);
    });

    test('hints are on for the human turn only, and not while paused', () async {
      final c = make();
      expect(ctl(c).canAssist, isTrue);
      human(c, 0);
      human(c, 4);
      expect(ctl(c).canAssist, isFalse, reason: 'AI is thinking');
      await aiReplies(c);
      expect(ctl(c).canAssist, isTrue);
      ctl(c).pause();
      expect(ctl(c).canAssist, isFalse);
    });
  });

  group('ads gate', () {
    test('the clock is held while ads play, then runs again', () async {
      final c = make();
      final during = <bool>[];
      final f = ctl(c).watchAds(2, onStart: (_) => during.add(c.read(clockProvider).running));
      expect(c.read(clockProvider).running, isFalse);
      final r = await f;
      expect(r.granted, isTrue);
      expect(during, [false, false]);
      expect(c.read(clockProvider).running, isTrue);
    });

    test('no ad available: denied, clock released, nothing granted', () async {
      final c = make(ads: fastAds(fill: 0));
      final r = await ctl(c).watchAds(1);
      expect(r.granted, isFalse);
      expect(r.message, AdsService.noAdMessage);
      expect(c.read(clockProvider).running, isTrue);
      expect(ui(c).hintText, isNull);
    });
  });

  group('hints', () {
    test('hint 1 shows a warning and no move', () {
      final c = make();
      ctl(c).applyWarningHint();
      expect(ui(c).hintText, isNotNull);
      expect(ui(c).hintMove, isNull);
    });

    test('hint 2 shows the warning plus a legal best move', () async {
      final c = make();
      human(c, 0);
      human(c, 4);
      await aiReplies(c);
      await ctl(c).applyBestMoveHint();
      final s = ui(c);
      expect(s.hintMove, isNotNull);
      expect(Rules.isLegal(s.game, s.hintMove!), isTrue);
      expect(s.hintText, contains('Best move'));
      expect(s.hintBusy, isFalse);
    });

    test('a hint disappears once a move is played', () {
      final c = make();
      ctl(c).applyWarningHint();
      ctl(c).tapPoint(0);
      expect(ui(c).hintText, isNull);
      expect(ui(c).hintMove, isNull);
    });

    test('hint 2 during a capture pick picks the token for the pending step', () async {
      final c = makeScripted([const Move.place(20), const Move.place(21)]);
      human(c, 0);
      human(c, 1);
      await aiReplies(c);
      ctl(c).tapPoint(2); // completes 0-1-2 -> choosing what to eat
      expect(ui(c).status, GameStatus.capturePick);
      await ctl(c).applyBestMoveHint();
      expect(ui(c).hintMove!.to, 2);
      expect(ui(c).hintMove!.hasCapture, isTrue);
      expect([20, 21], contains(ui(c).hintMove!.capture));
    });
  });

  group('rewind', () {
    test('nothing to rewind at the start, or after only the AI has moved', () async {
      final c = make();
      expect(ctl(c).canRewind, isFalse);
      final ai = make(humanFirst: false);
      await aiReplies(ai);
      await aiReplies(ai);
      expect(ai.read(gameControllerProvider).game.turn, 1);
      expect(ctl(ai).canRewind, isFalse);
    });

    test('rewind steps back two turns and restores position, stats and clock', () async {
      final c = make();
      human(c, 0);
      human(c, 4);
      await aiReplies(c);
      final beforeSecond = ui(c).game; // start of the human's second turn
      final historyBefore = ui(c).history.length;

      // any free point that cannot complete a line
      final free = [13, 15, 11, 21].firstWhere((p) => ui(c).game.emptyMask & bit(p) != 0);
      human(c, free);
      await aiReplies(c);
      expect(ui(c).history.length, greaterThan(historyBefore));

      c.read(clockProvider.notifier).advance(50000);
      expect(ctl(c).canRewind, isTrue);
      expect(ctl(c).rewind(), isTrue);
      final s = ui(c);
      expect(s.game, beforeSecond);
      expect(s.history.length, historyBefore);
      expect(s.status, GameStatus.awaitingInput);
      expect(c.read(clockProvider).remainingMs, c.read(clockProvider).totalMs);
      expect(c.read(clockProvider).running, isTrue);
      expect(s.phutasReady, isFalse);
    });

    test('rewinding a capture brings the eaten token back with its stats', () async {
      final c = makeScripted([const Move.place(20), const Move.place(21), const Move.place(22)]);
      human(c, 0);
      human(c, 1);
      await aiReplies(c); // AI opens with 20 and 21
      ctl(c).tapPoint(2); // human completes 0-1-2 ...
      ctl(c).tapPoint(20); // ... and eats the AI's token
      ctl(c).finishAnimation(ui(c).fxSerial);
      expect(ui(c).eaten, [1, 0]);
      expect(ui(c).linesFormed, [1, 0]);
      await aiReplies(c); // AI places 22
      expect(ui(c).game.mask1, maskOf([21, 22]));

      expect(ctl(c).rewind(), isTrue);
      final s = ui(c);
      expect(s.game.mask1, maskOf([20, 21]), reason: 'the eaten token is back');
      expect(s.game.mask0, maskOf([0, 1]));
      expect(s.eaten, [0, 0]);
      expect(s.linesFormed, [0, 0]);
      expect(s.game.turn, 0);
    });
  });

  testWidgets('hint flow on screen: chooser, ad prompt, progress, then the warning', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        aiServiceProvider.overrideWithValue(DirectAiService()),
        adsServiceProvider.overrideWithValue(fastAds()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const GameScreen(prefsOverride: MotionPrefs(reduceMotion: true)),
      ),
    ));
    final container = ProviderScope.containerOf(t.element(find.byType(GameScreen)));
    container.read(setupProvider.notifier)
      ..setMode(GameMode.vsAi)
      ..setDifficulty(Difficulty.easy);
    container.read(gameControllerProvider.notifier).newGame();
    await t.pump(const Duration(milliseconds: 300));

    await t.tap(find.text('Hint'));
    await sheet(t);
    expect(find.text('Need a hand?'), findsOneWidget);
    await t.tap(find.text('Best move'));
    await sheet(t);
    expect(find.text('Watch 2 ads to see the best move?'), findsOneWidget);
    expect(find.text('Ad 0 of 2'), findsOneWidget);

    await t.tap(find.text('Watch 2 ads'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('is playing'), findsOneWidget);
    // let both ads and the Hard search finish
    for (var i = 0; i < 30; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(container.read(gameControllerProvider).hintMove, isNotNull);
    expect(find.text('Need a hand?'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with no ad available the sheet says so and grants nothing', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        aiServiceProvider.overrideWithValue(DirectAiService()),
        adsServiceProvider.overrideWithValue(fastAds(fill: 0)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const GameScreen(prefsOverride: MotionPrefs(reduceMotion: true)),
      ),
    ));
    final container = ProviderScope.containerOf(t.element(find.byType(GameScreen)));
    container.read(setupProvider.notifier).setMode(GameMode.vsAi);
    container.read(gameControllerProvider.notifier).newGame();
    await t.pump(const Duration(milliseconds: 300));

    await t.tap(find.text('Hint'));
    await sheet(t);
    await t.tap(find.text('Warning'));
    await sheet(t);
    await t.tap(find.text('Watch 1 ad'));
    await t.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(AdsService.noAdMessage), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(container.read(gameControllerProvider).hintText, isNull);
    await t.pumpWidget(const SizedBox());
  });
}
