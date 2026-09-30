# Naw Tin

*Make three. Eat one.*

A polished two-player and vs-AI board game built with Flutter: 24 points on
three nested squares, nine tokens each, place then slide, make a line and eat a
token. Midnight Neon Arcade look, real strategy AI, hints and rewind paid with
rewarded ads.

## Run it

```
flutter pub get
flutter run                          # any device; mock ads
flutter run --dart-define=ADS=admob  # Google AdMob *test* ads (phone only)
flutter test                         # ~190 tests
```

Release builds, signing and the store listing: [docs/PLAY_STORE.md](docs/PLAY_STORE.md).

## Rules in one screen

- **Placement:** player 1 places two tokens, then turns alternate. Lines made
  while placing count.
- **Movement:** slide a token one step along a line to an empty point.
- **PHUTAS** (button): "I am one move from a new line." Only a warning.
- **MACHYAS:** complete a line and eat one opponent token (not one in a finished
  line, unless every token is protected).
- **BEGI / TREGHI:** one token swinging between two / three points completes a
  line at every stop. 32 + 16 patterns, all generated from the board.
- **Win:** opponent down to 2 tokens or no legal move. Draw on 3-fold repetition.

## Architecture

```
lib/
  core/engine/   pure Dart rules: 24-bit bitmasks, immutable state, 48 swing patterns
  core/ai/       negamax + alpha-beta, iterative deepening, Zobrist TT, hints, self-play
  features/      splash, home, setup, game, how_to_play
  services/      clock, ads, sound, haptics, settings, stats, persistence
  theme/         design tokens (ThemeExtension), typography
  widgets/       board painter, cards, dock, banners, glass, buttons
test/            engine first, then AI, services, screens, accessibility, perf
tool/            self-play harness, sound synthesizer
```

State management is **Riverpod**. The engine and AI import no Flutter code, so
they run in an isolate and in plain Dart.

### AI

Difficulty is search depth only: Easy 2, Medium 4, Hard 6, with a time cap per
move. Easy cannot see begi/treghi; Medium and Hard can. The search runs on a
background isolate. Timeouts auto-play with the *Easy* config, never the Hard
hint search.

Strength (self-play, `dart run tool/self_play.dart 100 120 30`): Hard beats Easy
88-10, Medium beats Easy 82-17.

### Seat balance - a decision for the owner

With the agreed placement rules (player 1 opens with two tokens; player 2 places
its last two in a row) 100 Hard-vs-Hard games gave **seat 0: 24 wins, seat 1: 74
wins**. A symmetric alternative, where each player opens with two tokens and there
is no closing double, gave **61 / 35**. Plain alternation gave 66 / 29.

The engine supports both (`Rules.placementRule`). The agreed rules are the default;
to adopt the symmetric opening set
`Rules.placementRule = PlacementRule.symmetricOpening` in `lib/main.dart` (there
is a commented line ready). Validate with human testing before changing.

### Sound, voices and accessibility

- One distinct synthesized effect per call and event (`tool/make_sounds.py`);
  replace any `assets/audio/*.wav` with a recording. Local-language voice lines
  drop into `assets/audio/voice/<lang>/` (see the README there).
- Colour-blind safe tokens (circle vs diamond), reduce-motion and low-power
  settings, 48dp targets, every board point is a labelled screen-reader control,
  and moves are announced.

## Build stages

1. Board data and rules engine with full unit tests
2. Theme tokens, typography, animated board, playable two-player mode
3. Splash, home, mode setup, game over, How to Play, navigation
4. AI (Easy, Medium, Hard) in an isolate, self-play harness
5. Timer, lenient timeout, pause
6. Hints, rewind, AdsService (mock + AdMob test ids)
7. Sound, haptics, persistence, bundled fonts, performance pass, accessibility,
   icon and Play Store prep

All seven stages are complete.
