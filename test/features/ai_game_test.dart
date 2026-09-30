import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/ai/ai.dart';
import 'package:nawtin/core/engine/engine.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/services/ai_provider.dart';

ProviderContainer make({required bool humanFirst}) {
  final c = ProviderContainer(overrides: [
    aiServiceProvider.overrideWithValue(DirectAiService()),
  ]);
  addTearDown(c.dispose);
  c.read(setupProvider.notifier)
    ..setMode(GameMode.vsAi)
    ..setDifficulty(Difficulty.easy)
    ..setHumanFirst(humanFirst);
  return c;
}

/// Lets the AI's think delay pass and finishes the animation it triggers.
Future<void> aiReplies(ProviderContainer c) async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final s = c.read(gameControllerProvider);
    if (s.status == GameStatus.animating) {
      c.read(gameControllerProvider.notifier).finishAnimation(s.fxSerial);
      return;
    }
  }
  fail('AI never replied');
}

void main() {
  test('human first: AI answers after the human finishes the opening double',
      () async {
    final c = make(humanFirst: true);
    final ctl = c.read(gameControllerProvider.notifier);
    ctl.newGame();
    expect(c.read(gameControllerProvider).status, GameStatus.awaitingInput);

    void human(int p) {
      ctl.tapPoint(p);
      ctl.finishAnimation(c.read(gameControllerProvider).fxSerial);
    }

    human(0);
    human(4);
    // AI (seat 1) is now thinking; human input is ignored meanwhile
    expect(c.read(gameControllerProvider).status, GameStatus.aiThinking);
    ctl.tapPoint(9);
    expect(c.read(gameControllerProvider).game.mask0, maskOf([0, 4]));

    await aiReplies(c);
    final s = c.read(gameControllerProvider);
    expect(s.game.mask1, isNot(0));
    expect(s.game.turn, 0);
    expect(s.status, GameStatus.awaitingInput);
    expect(s.phutasReady && s.phutasSeat == 1, isFalse,
        reason: 'the AI never gets the Phutas button');
  });

  test('AI first: it opens with two tokens on its own', () async {
    final c = make(humanFirst: false);
    c.read(gameControllerProvider.notifier).newGame();
    expect(c.read(gameControllerProvider).status, GameStatus.aiThinking);
    await aiReplies(c); // first token
    expect(c.read(gameControllerProvider).game.turn, 0);
    expect(c.read(gameControllerProvider).status, GameStatus.aiThinking);
    await aiReplies(c); // second token
    final s = c.read(gameControllerProvider);
    expect(s.game.turn, 1, reason: 'now it is the human seat');
    expect(popCount(s.game.mask0), 2);
    expect(s.status, GameStatus.awaitingInput);
  });

  test('a rematch discards a search that finishes late', () async {
    final c = make(humanFirst: false);
    final ctl = c.read(gameControllerProvider.notifier);
    ctl.newGame();
    ctl.newGame(); // restarts before the first search is applied
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final s = c.read(gameControllerProvider);
    // exactly one AI move happened, not two from the two searches
    expect(popCount(s.game.mask0), lessThanOrEqualTo(1));
  });

  test('two-player games never call the AI', () {
    final c = ProviderContainer(overrides: [
      aiServiceProvider.overrideWithValue(_ExplodingAi()),
    ]);
    addTearDown(c.dispose);
    c.read(setupProvider.notifier).setMode(GameMode.friend);
    final ctl = c.read(gameControllerProvider.notifier);
    ctl.newGame();
    ctl.tapPoint(0);
    ctl.finishAnimation(c.read(gameControllerProvider).fxSerial);
    expect(c.read(gameControllerProvider).status, GameStatus.awaitingInput);
  });
}

class _ExplodingAi extends AiService {
  @override
  Future<SearchResult> search(GameState state, AiConfig config, {Move? onlyStep}) =>
      throw StateError('AI must not run in two-player mode');
}
