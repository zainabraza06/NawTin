import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/engine/engine.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/setup/game_setup.dart';

ProviderContainer make() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(setupProvider.notifier).setMode(GameMode.friend);
  c.read(gameControllerProvider.notifier).newGame();
  return c;
}

/// Taps [p] and completes the resulting animation, like the board would.
void tap(ProviderContainer c, int p) {
  final ctl = c.read(gameControllerProvider.notifier);
  ctl.tapPoint(p);
  final s = c.read(gameControllerProvider);
  if (s.status == GameStatus.animating) ctl.finishAnimation(s.fxSerial);
}

void main() {
  test('starts in placement with seat 0 to place two', () {
    final c = make();
    final s = c.read(gameControllerProvider);
    expect(s.status, GameStatus.awaitingInput);
    expect(s.game.turn, 0);
    expect(s.game.placesLeft, 2);
    expect(s.targets, Board.fullMask);
  });

  test('opening turns: both players place two tokens, then turns alternate', () {
    final c = make();
    int turn() => c.read(gameControllerProvider).game.turn;
    tap(c, 0);
    expect(turn(), 0);
    tap(c, 4);
    expect(turn(), 1, reason: 'seat 0 has placed its two');
    tap(c, 9);
    expect(turn(), 1, reason: 'seat 1 also places two on its first turn');
    tap(c, 11);
    expect(turn(), 0);
    tap(c, 13);
    expect(turn(), 1, reason: 'one token each from now on');
  });

  test('input is ignored while a move is animating', () {
    final c = make();
    final ctl = c.read(gameControllerProvider.notifier);
    ctl.tapPoint(0);
    expect(c.read(gameControllerProvider).status, GameStatus.animating);
    ctl.tapPoint(4); // ignored
    expect(c.read(gameControllerProvider).game.mask0, bit(0));
    ctl.finishAnimation(c.read(gameControllerProvider).fxSerial);
    expect(c.read(gameControllerProvider).status, GameStatus.awaitingInput);
  });

  test('a stale animation-finished call is ignored', () {
    final c = make();
    final ctl = c.read(gameControllerProvider.notifier);
    ctl.tapPoint(0);
    ctl.finishAnimation(99);
    expect(c.read(gameControllerProvider).status, GameStatus.animating);
  }, );

  test('completing a line enters capture pick; protected tokens are locked', () {
    final c = make();
    tap(c, 0); // seat 0 opens with two
    tap(c, 1);
    tap(c, 8); // seat 1 opens with two
    tap(c, 9);
    tap(c, 3); // seat 0 (decoy)
    tap(c, 10); // seat 1 completes 8-9-10 -> must eat
    var s = c.read(gameControllerProvider);
    expect(s.status, GameStatus.capturePick);
    expect(s.captureMask, maskOf([0, 1, 3]));
    // wrong tap: an empty point does nothing
    c.read(gameControllerProvider.notifier).tapPoint(15);
    expect(c.read(gameControllerProvider).status, GameStatus.capturePick);
    // eat seat 0's token 3
    tap(c, 3);
    s = c.read(gameControllerProvider);
    expect(s.game.mask0, maskOf([0, 1]));
    expect(s.eaten, [0, 1]);
    expect(s.linesFormed, [0, 1]);
    expect(s.status, GameStatus.awaitingInput);
  });

  test('movement: select, change selection, slide, deselect', () {
    final c = make();
    final ctl = c.read(gameControllerProvider.notifier);
    // fast-forward: play a legal scripted placement with no lines
    const a = [0, 2, 4, 6, 9, 11, 13, 15, 17];
    const b = [1, 3, 5, 7, 8, 10, 12, 14, 21];
    tap(c, a[0]);
    tap(c, a[1]);
    tap(c, b[0]);
    tap(c, b[1]);
    for (var i = 2; i < 9; i++) {
      tap(c, a[i]);
      tap(c, b[i]);
    }
    var s = c.read(gameControllerProvider);
    expect(s.game.phase, GamePhase.movement);
    expect(s.game.turn, 0);
    expect(s.targets, 0);

    ctl.tapPoint(17); // select 17: neighbours 16, 18 empty (9 is own)
    s = c.read(gameControllerProvider);
    expect(s.selected, 17);
    expect(s.targets, maskOf([16, 18]));
    ctl.tapPoint(17); // toggle off
    expect(c.read(gameControllerProvider).selected, isNull);
    ctl.tapPoint(17);
    ctl.tapPoint(22); // not a target: deselects
    expect(c.read(gameControllerProvider).selected, isNull);
    ctl.tapPoint(17);
    ctl.tapPoint(16); // slide
    s = c.read(gameControllerProvider);
    expect(s.status, GameStatus.animating);
    expect(s.game.mask0 & bit(16), isNot(0));
    expect(s.game.turn, 1);
  });

  test('PHUTAS becomes available after a new threat and is spent when pressed',
      () {
    final c = make();
    final ctl = c.read(gameControllerProvider.notifier);
    tap(c, 0);
    tap(c, 1); // two on a line -> threat
    var s = c.read(gameControllerProvider);
    expect(s.phutasReady, isTrue);
    expect(s.phutasLines, 1 << 0);
    ctl.callPhutas();
    s = c.read(gameControllerProvider);
    expect(s.phutasReady, isFalse);
    expect(s.phutasSerial, 1);
    ctl.callPhutas(); // no effect once spent
    expect(c.read(gameControllerProvider).phutasSerial, 1);
  });

  test('a two-player rematch swaps who starts; vs AI keeps the seats', () {
    final c = make();
    c.read(setupProvider.notifier).setFriendNames('Zainab', 'Sam');
    c.read(gameControllerProvider.notifier).newGame();
    expect(c.read(gameControllerProvider).names, ['Zainab', 'Sam']);
    c.read(gameControllerProvider.notifier).rematch();
    expect(c.read(gameControllerProvider).names, ['Sam', 'Zainab']);
    c.read(gameControllerProvider.notifier).rematch();
    expect(c.read(gameControllerProvider).names, ['Zainab', 'Sam']);

    c.read(setupProvider.notifier).setMode(GameMode.vsAi);
    c.read(gameControllerProvider.notifier).rematch();
    expect(c.read(gameControllerProvider).names, ['You', GameSetup.aiName]);
  });

  test('newGame resets everything', () {
    final c = make();
    tap(c, 0);
    c.read(gameControllerProvider.notifier).newGame();
    final s = c.read(gameControllerProvider);
    expect(s.game, GameState.initial());
    expect(s.history, isEmpty);
    expect(s.eaten, [0, 0]);
  });
}
