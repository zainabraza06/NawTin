import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/ai/ai.dart';
import 'package:nawtin/core/ai/self_play.dart';

void main() {
  test('Hard clearly beats Easy in self-play (both seats)', () {
    final stats = playMatch(
      AiConfig.hard.withTime(100),
      AiConfig.easy.withTime(30),
      games: 12,
      openingPlies: 6,
      seed: 7,
    );
    expect(stats.games, 12);
    expect(stats.aWins, greaterThan(stats.bWins));
    expect(stats.aScore, greaterThanOrEqualTo(0.75), reason: '$stats');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Medium beats Easy in self-play', () {
    final stats = playMatch(
      AiConfig.medium.withTime(100),
      AiConfig.easy.withTime(30),
      games: 12,
      openingPlies: 6,
      seed: 11,
    );
    expect(stats.aScore, greaterThanOrEqualTo(0.65), reason: '$stats');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('self-play games are legal from start to finish', () {
    final o = playGame(AiConfig.easy.withTime(20), AiConfig.easy.withTime(20),
        openingPlies: 4, seed: 3, maxPlies: 200);
    expect(o.plies, greaterThan(10));
  });
}
