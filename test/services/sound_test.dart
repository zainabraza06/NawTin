import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/ai/ai.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/game/game_screen.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/services/ai_provider.dart';
import 'package:nawtin/services/settings.dart';
import 'package:nawtin/services/sound/sound_service.dart';
import 'package:nawtin/services/turn_clock.dart';
import 'package:nawtin/theme/app_theme.dart';
import 'package:nawtin/theme/tokens.dart';

void main() {
  group('assets', () {
    test('every sound has a valid 16-bit mono WAV file', () {
      for (final s in Sfx.values) {
        final f = File('assets/${SoundCatalog.effect(s)}');
        expect(f.existsSync(), isTrue, reason: '${s.name}.wav is missing');
        final b = f.readAsBytesSync();
        expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE');
        final data = b.buffer.asByteData();
        expect(data.getUint16(22, Endian.little), 1, reason: 'mono');
        expect(data.getUint16(34, Endian.little), 16, reason: '16-bit');
        expect(b.length, greaterThan(2000));
      }
    });

    test('the calls sound different from each other', () {
      final sizes = {
        for (final s in [Sfx.phutas, Sfx.machyas, Sfx.begi, Sfx.treghi])
          File('assets/${SoundCatalog.effect(s)}').lengthSync(),
      };
      expect(sizes.length, 4);
    });

    test('voice lines have a predictable place for every language', () {
      expect(SoundCatalog.voice('ur', Sfx.machyas), 'audio/voice/ur/machyas.wav');
      expect(SoundCatalog.voiceManifestKey('ur', Sfx.begi), 'assets/audio/voice/ur/begi.wav');
      expect(SoundCatalog.voiced.contains(Sfx.place), isFalse);
      expect(SoundCatalog.voiced.contains(Sfx.treghi), isTrue);
    });
  });

  group('mute', () {
    test('the sound setting switches the service on and off', () {
      final rec = RecordingSoundService();
      final c = ProviderContainer(overrides: [
        soundServiceProvider.overrideWith((ref) {
          bindSoundSettings(ref, rec);
          return rec;
        }),
      ]);
      addTearDown(c.dispose);
      final sound = c.read(soundServiceProvider);
      sound.play(Sfx.place);
      c.read(settingsProvider.notifier).setSound(false);
      sound.play(Sfx.machyas);
      c.read(settingsProvider.notifier).setSound(true);
      sound.play(Sfx.win);
      expect(rec.played, [Sfx.place, Sfx.win]);
    });

    test('the selected language reaches the service', () {
      final rec = RecordingSoundService();
      final c = ProviderContainer(overrides: [
        soundServiceProvider.overrideWith((ref) {
          bindSoundSettings(ref, rec);
          return rec;
        }),
      ]);
      addTearDown(c.dispose);
      c.read(soundServiceProvider);
      c.read(settingsProvider.notifier).setLanguage('ur');
      expect(rec.language, 'ur');
    });
  });

  group('in the game', () {
    late RecordingSoundService rec;

    Future<(ProviderContainer, WidgetTester)> boot(WidgetTester t) async {
      rec = RecordingSoundService();
      t.view.physicalSize = const Size(1080, 2280);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          aiServiceProvider.overrideWithValue(DirectAiService()),
          soundServiceProvider.overrideWith((ref) {
            bindSoundSettings(ref, rec);
            return rec;
          }),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const GameScreen(prefsOverride: MotionPrefs(reduceMotion: true)),
        ),
      ));
      final c = ProviderScope.containerOf(t.element(find.byType(GameScreen)));
      c.read(setupProvider.notifier).setMode(GameMode.friend);
      c.read(gameControllerProvider.notifier).newGame();
      await t.pump();
      return (c, t);
    }

    Future<void> play(WidgetTester t, ProviderContainer c, int p) async {
      c.read(gameControllerProvider.notifier).tapPoint(p);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 3));
    }

    testWidgets('placing, eating and pressing Phutas each make their own sound', (t) async {
      final (c, _) = await boot(t);
      await play(t, c, 0);
      await play(t, c, 1); // two on a line: Phutas becomes available
      expect(rec.played.where((s) => s == Sfx.place).length, 2);
      c.read(gameControllerProvider.notifier).callPhutas();
      await t.pump(const Duration(milliseconds: 100));
      expect(rec.played, contains(Sfx.phutas));

      for (final p in [8, 9, 3, 10]) {
        await play(t, c, p);
      }
      await play(t, c, 3); // eat
      expect(rec.played, contains(Sfx.machyas));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a muted game is silent', (t) async {
      final (c, _) = await boot(t);
      c.read(settingsProvider.notifier).setSound(false);
      await t.pump();
      await play(t, c, 0);
      expect(rec.played, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('timer warning at 30s, ticks in the last ten, and a fanfare at the end', (t) async {
      final (c, _) = await boot(t);
      final clock = c.read(clockProvider.notifier);
      clock.advance(91000); // 29s left: crossed the 30s mark
      await t.pump(const Duration(milliseconds: 100));
      clock.advance(20000); // 9s left
      await t.pump(const Duration(milliseconds: 100));
      expect(rec.played, contains(Sfx.tick));

      // run out twice: first an auto move, then disqualification -> game over
      clock.advance(10000);
      await t.pump(const Duration(seconds: 2));
      c.read(gameControllerProvider.notifier).finishAnimation(c.read(gameControllerProvider).fxSerial);
      clock.advance(120000);
      await t.pump(const Duration(seconds: 2));
      expect(c.read(gameControllerProvider).status, GameStatus.gameOver);
      expect(rec.played, contains(Sfx.win));
      expect(rec.played, contains(Sfx.warning));
      await t.pumpWidget(const SizedBox());
    });
  });
}
