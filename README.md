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
Online play with a remote friend (private rooms): [protocol](docs/online_protocol.md), [running it locally](docs/online_dev.md), [server](server/README.md), [deploying to Cloud Run](docs/deploy_cloud_run.md), [two-device test plan](docs/two_device_test_plan.md), [store and privacy checklist](docs/store_checklist.md).

## Rules in one screen

- **Placement:** each player opens with two tokens, then turns alternate one
  token at a time. Lines made while placing count.
- **Movement:** slide a token one step along a line to an empty point.
- **PHUTAS** (button): "I am one move from a new line." Only a warning.
- **MACHYAS:** complete a line and eat one opponent token (not one in a finished
  line, unless every token is protected).
- **BEGI / TREGHI:** one token swinging between two / three points completes a
  line at every stop. 32 + 16 patterns, all generated from the board.
- **Win:** opponent down to 2 tokens or no legal move. Draw on 3-fold repetition.

## Architecture

```
packages/naw_tin_core/   shared pure-Dart engine + AI (used by the app and the online server)
lib/
  core/          re-export shims for packages/naw_tin_core (old import paths keep working)
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

Difficulty is how far ahead the search may look and for how long: Easy up to 6
moves in 0.4 s, Medium up to 10 in 1 s, Hard up to 16 in 2 s. The search deepens
one move at a time and stops at the ceiling or the time limit, so a faster phone
looks further than a slow one. Easy cannot see begi/treghi; Medium and Hard can. The search runs on a
background isolate.

**When the turn clock runs out** (the usual casual-game practice): the first
timeout plays a simple legal move for the player (the Easy-level search, never
random and never the Hard hint search, and it also picks which token to eat). A
second timeout **in a row** forfeits the game. Any move the player makes
themselves clears the warning, so only repeated neglect is punished.

Strength (self-play, `dart run tool/self_play.dart 100 120 30`): Hard beats Easy
88-10, Medium beats Easy 82-17.

### Seat balance

Self-play (100+ independent Hard-vs-Hard games per rule) measured three
placement orders:

| Rule | seat 0 wins | seat 1 wins |
|---|---|---|
| Original: seat 0 opens with two, seat 1 places its last two in a row | 24 | 74 |
| Strict alternation, no doubles | 66 | 29 |
| **Both players open with two tokens (the default)** | 61-71% of decisive games | 29-39% |

The default is the third: nobody gets a closing double, and both players start
with two tokens. Being first to move still carries a modest edge, so in
two-player mode a **rematch swaps who starts**. Against the AI you choose who
goes first. The original order is still available as
`Rules.placementRule = PlacementRule.openingAndClosingDouble` (see `lib/main.dart`).

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
