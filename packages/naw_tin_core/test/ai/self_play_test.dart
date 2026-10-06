import 'package:test/test.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

/// Self-play tests compare strengths, so the AI's deliberate randomness (variety
/// and the capture / safety preferences) is switched off: the same games are
/// played every run.
AiConfig steady(AiConfig c) => c.withVariety(0).withCapturePreference(0).withSafetyPreference(0);

void main() {
  // Compared by search depth (not by clock) so the result does not depend on how
  // fast the machine is.
  test('Hard clearly beats Easy in self-play (both seats)', () {
    final stats = playMatch(
      steady(AiConfig.hard.withDepth(6).withTime(600000).strictTime()),
      steady(AiConfig.easy.withDepth(3).withTime(600000).strictTime()),
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
      steady(AiConfig.medium.withDepth(5).withTime(600000).strictTime()),
      steady(AiConfig.easy.withDepth(3).withTime(600000).strictTime()),
      games: 30,
      openingPlies: 6,
      seed: 11,
    );
    expect(stats.aScore, greaterThanOrEqualTo(0.55), reason: '$stats');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('self-play games are legal from start to finish', () {
    final o = playGame(steady(AiConfig.easy.withTime(20)), steady(AiConfig.easy.withTime(20)),
        openingPlies: 4, seed: 3, maxPlies: 200);
    expect(o.plies, greaterThan(10));
  });
}
