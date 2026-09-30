import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/ai/ai.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/services/ai_provider.dart';
import 'package:nawtin/services/haptics.dart';
import 'package:nawtin/services/prefs_store.dart';
import 'package:nawtin/services/settings.dart';
import 'package:nawtin/services/stats.dart';
import 'package:nawtin/services/turn_clock.dart';

ProviderContainer boot(PrefsStore store) {
  final c = ProviderContainer(overrides: [
    prefsStoreProvider.overrideWithValue(store),
    aiServiceProvider.overrideWithValue(DirectAiService()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  tearDown(() => Haptics.enabled = true);

  group('settings', () {
    test('survive a restart', () {
      final store = MemoryPrefsStore();
      final a = boot(store);
      a.read(settingsProvider.notifier)
        ..setSound(false)
        ..setHaptics(false)
        ..setLowPower(true)
        ..setReduceMotion(true);
      final b = boot(store); // "restart": a new container over the same storage
      final s = b.read(settingsProvider);
      expect(s.soundOn, isFalse);
      expect(s.hapticsOn, isFalse);
      expect(s.lowPower, isTrue);
      expect(s.reduceMotion, isTrue);
      expect(Haptics.enabled, isFalse, reason: 'the vibration switch applies on load');
    });

    test('corrupt or foreign data falls back to the defaults', () {
      final store = MemoryPrefsStore()..write('settings.v1', '{not json');
      expect(boot(store).read(settingsProvider).soundOn, isTrue);
      final odd = MemoryPrefsStore()..write('settings.v1', '{"soundOn":"yes","language":7}');
      final s = boot(odd).read(settingsProvider);
      expect(s.soundOn, isTrue);
      expect(s.language, 'en');
    });
  });

  group('setup', () {
    test('remembers difficulty, first move and friend names', () {
      final store = MemoryPrefsStore();
      boot(store).read(setupProvider.notifier)
        ..setDifficulty(Difficulty.hard)
        ..setHumanFirst(false)
        ..setFriendNames('Zainab', 'Sam');
      final s = boot(store).read(setupProvider);
      expect(s.difficulty, Difficulty.hard);
      expect(s.humanFirst, isFalse);
      expect(s.friendNames, ['Zainab', 'Sam']);
      expect(s.mode, GameMode.vsAi, reason: 'the mode is picked on the home screen');
    });

    test('bad saved names are ignored', () {
      final store = MemoryPrefsStore()
        ..write('setup.v1', '{"difficulty":"nightmare","names":["",""]}');
      final s = boot(store).read(setupProvider);
      expect(s.difficulty, Difficulty.medium);
      expect(s.friendNames, ['Player 1', 'Player 2']);
    });
  });

  group('stats', () {
    GameRecord rec({bool won = false, bool draw = false, Difficulty d = Difficulty.easy, int eaten = 0}) =>
        GameRecord(
          mode: GameMode.vsAi,
          difficulty: d,
          humanWon: won,
          draw: draw,
          tokensEaten: eaten,
          linesFormed: 2,
          swings: 1,
        );

    test('records per difficulty and tracks streaks', () {
      final c = boot(MemoryPrefsStore());
      final st = c.read(statsProvider.notifier);
      st.record(rec(won: true, eaten: 5));
      st.record(rec(won: true, eaten: 4));
      st.record(rec(won: true, d: Difficulty.hard));
      expect(c.read(statsProvider).streak, 3);
      st.record(rec()); // a loss
      final s = c.read(statsProvider);
      expect(s.streak, 0);
      expect(s.bestStreak, 3);
      expect(s.recordFor(Difficulty.easy).wins, 2);
      expect(s.recordFor(Difficulty.easy).losses, 1);
      expect(s.recordFor(Difficulty.hard).wins, 1);
      expect(s.tokensEaten, 9);
      expect(s.linesFormed, 8);
      expect(s.totalGames, 4);
    });

    test('a draw keeps the streak alive and counts as a game', () {
      final c = boot(MemoryPrefsStore());
      final st = c.read(statsProvider.notifier);
      st.record(rec(won: true));
      st.record(rec(draw: true));
      expect(c.read(statsProvider).streak, 1);
      expect(c.read(statsProvider).recordFor(Difficulty.easy).draws, 1);
    });

    test('friend games are counted separately', () {
      final c = boot(MemoryPrefsStore());
      c.read(statsProvider.notifier).record(const GameRecord(
        mode: GameMode.friend,
        difficulty: Difficulty.medium,
        humanWon: false,
        draw: false,
        tokensEaten: 3,
        linesFormed: 1,
        swings: 0,
      ));
      final s = c.read(statsProvider);
      expect(s.friendGames, 1);
      expect(s.aiGames, 0);
    });

    test('persist across restarts and can be reset', () {
      final store = MemoryPrefsStore();
      boot(store).read(statsProvider.notifier).record(rec(won: true, eaten: 6));
      final again = boot(store);
      expect(again.read(statsProvider).recordFor(Difficulty.easy).wins, 1);
      again.read(statsProvider.notifier).reset();
      expect(boot(store).read(statsProvider).isEmpty, isTrue);
    });

    test('corrupt stats start fresh', () {
      final store = MemoryPrefsStore()..write('stats.v1', '[1,2');
      expect(boot(store).read(statsProvider).isEmpty, isTrue);
    });
  });

  group('game end feeds the stats exactly once', () {
    Future<void> twoTimeouts(ProviderContainer c, int ms) async {
      final ctl = c.read(gameControllerProvider.notifier);
      c.read(clockProvider.notifier).advance(ms); // first timeout: a move is played
      await Future<void>.delayed(const Duration(milliseconds: 700));
      ctl.finishAnimation(c.read(gameControllerProvider).fxSerial);
      // seat 0 is still on its opening double, so the same player is up again
      expect(c.read(clockProvider).running, isTrue);
      c.read(clockProvider.notifier).advance(ms); // second timeout: disqualified
    }

    test('a disqualification in two-player counts one friend game', () async {
      final c = boot(MemoryPrefsStore());
      c.read(setupProvider.notifier).setMode(GameMode.friend);
      c.read(gameControllerProvider.notifier).newGame();
      await twoTimeouts(c, 120000);
      expect(c.read(gameControllerProvider).status, GameStatus.gameOver);
      final s = c.read(statsProvider);
      expect(s.friendGames, 1);
      expect(s.totalGames, 1);
    });

    test('losing to the AI on timeouts is recorded as a loss at that level', () async {
      final c = boot(MemoryPrefsStore());
      c.read(setupProvider.notifier)
        ..setMode(GameMode.vsAi)
        ..setDifficulty(Difficulty.hard);
      c.read(gameControllerProvider.notifier).newGame();
      await twoTimeouts(c, 60000);
      final s = c.read(statsProvider);
      expect(s.recordFor(Difficulty.hard).losses, 1);
      expect(s.streak, 0);
      expect(s.totalGames, 1);
    });
  });
}
